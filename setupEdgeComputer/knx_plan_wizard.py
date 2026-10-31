"""Create plan.yaml for EKBPRO KNX Terminal Python, for the floor plan view (F8).

Started by install_knx_terminal.sh with the program's venv:
    PYTHONPATH=<install dir> KNXSCADA_CONFIG=<config.yaml> venv/bin/python knx_plan_wizard.py <image folder>

Each floor is made from a drawing or by typing the rooms row by row. A drawing is read like this:
the walls are the long lines, the drawing is straightened, door openings are closed by drawing a line
between walls on the same line, and every area that is then closed in is a room. plan.yaml only holds rectangles, so an L-shaped room becomes
its bounding box. The result is shown in the terminal and can be corrected before it is saved.
"""

import os
import re
import sys
from pathlib import Path

import yaml

from knxscada.config import load_config
from knxscada.plan import load_plan, plan_path
from knxscada.project import load_project

MAX_IMAGE_SIZE = 1000  # longest side in pixels, enough for rooms and keeps it fast
LINE_CONTRAST = 120  # weaker lines than this are door swings and other details, not walls
MAX_ROTATION = 20  # degrees
DEFAULT_DOOR_GAP_M = 2.5  # largest opening in a wall that is closed
MIN_WALL_M = 0.4  # shorter pieces are walls seen from the side
MIN_ROOM_AREA_M2 = 1.0
MIN_WALL_SHARE = 0.15  # a dark shape shorter than this share of the building is text or furniture
WALL_GAP_MM = 150  # wall thickness in rooms typed by hand
ROW_ITEM = re.compile(r"\s*(.+?)\s+(\d+(?:[.,]\d+)?)\s*(?:,|$)")  # "Kitchen 3,3, Bath 2": the comma is both


def ask(prompt, default=""):
    suffix = f" [{default}]" if default != "" else ""
    return input(f"{prompt}{suffix}: ").strip() or str(default)


def ask_number(prompt, default=None):
    while True:
        try:
            value = float(ask(prompt, "" if default is None else default).replace(",", "."))
            if value > 0:
                return value
        except ValueError:
            pass
        print("Please enter a number above 0.")


def components(cells, width, height):
    """Find connected areas in a width*height bytearray with non-zero cells.

    Returns one (min_x, min_y, max_x, max_y, area, pixels) per area, pixels as cell indexes.
    """
    seen = bytearray(len(cells))
    found = []
    for start in range(len(cells)):
        if not cells[start] or seen[start]:
            continue
        seen[start] = 1
        stack = [start]
        pixels = []
        while stack:
            cell = stack.pop()
            pixels.append(cell)
            x = cell % width
            neighbours = []
            if x > 0:
                neighbours.append(cell - 1)
            if x < width - 1:
                neighbours.append(cell + 1)
            if cell >= width:
                neighbours.append(cell - width)
            if cell < width * (height - 1):
                neighbours.append(cell + width)
            for other in neighbours:
                if cells[other] and not seen[other]:
                    seen[other] = 1
                    stack.append(other)
        xs = [p % width for p in pixels]
        ys = [p // width for p in pixels]
        found.append((min(xs), min(ys), max(xs), max(ys), len(pixels), pixels))
    return found


def find_rotation(lines):
    """Angle that makes the walls line up with the image, the one giving the sharpest line profile."""
    from PIL import Image

    small = lines.copy()
    small.thumbnail((400, 400))

    def sharpness(angle):
        turned = small.rotate(angle, resample=Image.BILINEAR, expand=True)
        rows = turned.resize((1, turned.height), Image.BOX).tobytes()
        columns = turned.resize((turned.width, 1), Image.BOX).tobytes()
        return sum(v * v for v in rows) + sum(v * v for v in columns)

    coarse = max(range(-MAX_ROTATION, MAX_ROTATION + 1), key=sharpness)
    fine = [coarse + step / 4 for step in range(-4, 5)]
    return max(fine, key=sharpness)


def load_walls(path):
    """Read a drawing. Returns the wall mask cropped to the building, and its size in pixels."""
    from PIL import Image, ImageFilter

    image = Image.open(path).convert("RGBA")
    background = Image.new("RGBA", image.size, "white")
    gray = Image.alpha_composite(background, image).convert("L")

    # Lines are what differs from the paper, which can be white or dark as in a CAD screen.
    # This is done before scaling down, where thin lines would fade away.
    histogram = gray.histogram()
    paper = histogram.index(max(histogram))
    lines = gray.point(lambda v: abs(v - paper)).filter(ImageFilter.MaxFilter(3))
    lines = lines.point(lambda v: 255 if v >= LINE_CONTRAST else 0)
    factor = max(1, -(-max(lines.size) // MAX_IMAGE_SIZE))
    lines = lines.reduce(factor).point(lambda v: 255 if v >= 32 else 0)

    angle = find_rotation(lines)
    if angle:
        print(f"The building is turned {angle} degrees in the drawing, straightening it.")
        lines = lines.rotate(angle, resample=Image.BILINEAR, expand=True).point(lambda v: 255 if v >= 32 else 0)

    dark = lines.filter(ImageFilter.MaxFilter(3))
    width, height = dark.size

    shapes = components(bytearray(dark.tobytes()), width, height)
    if not shapes:
        raise ValueError("no lines found in the image")
    longest = max(max(s[2] - s[0], s[3] - s[1]) for s in shapes)
    walls = [s for s in shapes if max(s[2] - s[0], s[3] - s[1]) >= longest * MIN_WALL_SHARE]
    min_x = min(s[0] for s in walls)
    min_y = min(s[1] for s in walls)
    max_x = max(s[2] for s in walls)
    max_y = max(s[3] for s in walls)

    mask = Image.new("L", (width, height), 0)
    pixels = mask.load()
    for shape in walls:
        for cell in shape[5]:
            pixels[cell % width, cell // width] = 255
    return mask.crop((min_x, min_y, max_x + 1, max_y + 1))


def bridge_openings(mask, max_gap, min_wall):
    """Draw a line across each opening in a row, between two pieces of wall on the same line.

    A row through a narrow room only crosses the walls sideways, and those short pieces are
    not bridged. That is why narrow rooms survive here, also when the openings are wide.
    """
    from PIL import Image

    width, height = mask.size
    cells = bytearray(mask.tobytes())
    bridged = bytearray(cells)
    for y in range(height):
        row = cells[y * width:(y + 1) * width]
        wall_end = None
        x = 0
        while x < width:
            if not row[x]:
                x += 1
                continue
            start = x
            while x < width and row[x]:
                x += 1
            if x - start < min_wall:
                continue
            if wall_end is not None and start - wall_end <= max_gap:
                bridged[y * width + wall_end:y * width + start] = b"\xff" * (start - wall_end)
            wall_end = x
    return Image.frombytes("L", (width, height), bytes(bridged))


def find_rooms(mask, building_width_m, door_gap_m):
    """Rooms in a drawing as dicts in mm, and the outer size of the building in mm."""
    from PIL import Image, ImageChops, ImageFilter

    width, height = mask.size
    mm_per_pixel = building_width_m * 1000 / width
    max_gap = round(door_gap_m * 1000 / mm_per_pixel)
    min_wall = round(MIN_WALL_M * 1000 / mm_per_pixel)

    across = bridge_openings(mask, max_gap, min_wall)
    down = bridge_openings(mask.transpose(Image.TRANSPOSE), max_gap, min_wall)
    closed = ImageChops.lighter(across, down.transpose(Image.TRANSPOSE)).filter(ImageFilter.MaxFilter(3))
    free = bytearray(0 if v else 1 for v in closed.tobytes())

    rooms = []
    for min_x, min_y, max_x, max_y, area, _pixels in components(free, width, height):
        if min_x == 0 or min_y == 0 or max_x == width - 1 or max_y == height - 1:
            continue  # outside the building
        if area * (mm_per_pixel / 1000) ** 2 < MIN_ROOM_AREA_M2:
            continue
        rooms.append({
            "label": "",
            "x": round(min_x * mm_per_pixel, -1),
            "y": round(min_y * mm_per_pixel, -1),
            "w": round((max_x - min_x + 1) * mm_per_pixel, -1),
            "h": round((max_y - min_y + 1) * mm_per_pixel, -1),
        })
    rooms.sort(key=lambda r: (r["y"], r["x"]))
    return rooms, building_width_m * 1000, round(height * mm_per_pixel, -1)


def show_rooms(rooms, floor_width, floor_depth):
    """Draw the rooms in the terminal. A character is about twice as tall as it is wide."""
    columns = 76
    rows = max(8, round(columns * floor_depth / floor_width / 2))
    grid = [[" "] * columns for _ in range(rows)]
    for number, room in enumerate(rooms, 1):
        left = int(room["x"] / floor_width * (columns - 1))
        right = int((room["x"] + room["w"]) / floor_width * (columns - 1))
        top = int(room["y"] / floor_depth * (rows - 1))
        bottom = int((room["y"] + room["h"]) / floor_depth * (rows - 1))
        for x in range(left, right + 1):
            grid[top][x] = grid[bottom][x] = "-"
        for y in range(top, bottom + 1):
            grid[y][left] = grid[y][right] = "|"
        text = str(number)
        y = (top + bottom) // 2
        x = max(left + 1, (left + right) // 2)
        for offset, char in enumerate(text):
            if x + offset < columns:
                grid[y][x + offset] = char
    print()
    print("\n".join("".join(row).rstrip() for row in grid))
    print()
    for number, room in enumerate(rooms, 1):
        name = f"  {room['label']}" if room["label"] else ""
        print(f"{number:3}) {room['w'] / 1000:.1f} x {room['h'] / 1000:.1f} m{name}")


def merge_rooms(rooms, first, second):
    a, b = rooms[first], rooms[second]
    left = min(a["x"], b["x"])
    top = min(a["y"], b["y"])
    a.update({
        "w": max(a["x"] + a["w"], b["x"] + b["w"]) - left,
        "h": max(a["y"] + a["h"], b["y"] + b["h"]) - top,
        "x": left,
        "y": top,
    })
    del rooms[second]


def review_rooms(mask, building_width_m):
    """Let the user correct the rooms. Returns None to type them by hand instead."""
    door_gap = DEFAULT_DOOR_GAP_M
    rooms, floor_width, floor_depth = find_rooms(mask, building_width_m, door_gap)
    while True:
        show_rooms(rooms, floor_width, floor_depth)
        print(f"\nFound {len(rooms)} rooms. Openings up to {door_gap} m are closed.")
        print("  enter    = accept")
        print("  d 3      = delete room 3")
        print("  m 3 4    = merge room 3 and 4 (a room split by furniture or a wall opening)")
        print("  g 3.5    = close larger openings, when two rooms have become one")
        print("  g 1.5    = close smaller openings, when a room is split by mistake")
        print("  a 8.9 3 1.1 4 = add a missing room: left, top, width and depth in metres")
        print("  h        = type the rooms by hand instead")
        parts = input("> ").strip().lower().replace(",", ".").split()
        try:
            if not parts:
                if rooms:
                    return rooms, floor_width, floor_depth
                print("There are no rooms to accept.")
                continue
            if parts[0] == "h":
                return None
            if parts[0] == "a":
                x, y, w, h = (round(float(p) * 1000) for p in parts[1:5])
                rooms.append({"label": "", "x": x, "y": y, "w": w, "h": h})
            elif parts[0] == "g":
                door_gap = float(parts[1])
                rooms, floor_width, floor_depth = find_rooms(mask, building_width_m, door_gap)
            elif parts[0] == "d":
                del rooms[int(parts[1]) - 1]
            elif parts[0] == "m":
                first, second = sorted(int(p) - 1 for p in parts[1:3])
                merge_rooms(rooms, first, second)
            else:
                print("Unknown command.")
        except (ValueError, IndexError):
            print("Could not understand that, see the list above.")


def rooms_from_image(image_folder):
    """Returns (rooms, width, depth), or None if the rooms should be typed by hand."""
    images = sorted(
        p for p in Path(image_folder).iterdir() if p.suffix.lower() in (".png", ".jpg", ".jpeg")
    )
    if not images:
        print("No drawings found.")
        return None
    print("\nDrawings:")
    for number, path in enumerate(images, 1):
        print(f"  {number}) {path.name}")
    choice = ask("Which drawing is this floor? (h = type the rooms by hand)", 1)
    if choice.lower() == "h":
        return None
    try:
        path = images[int(choice) - 1]
    except (ValueError, IndexError):
        print("No such drawing.")
        return None
    try:
        mask = load_walls(path)
    except ImportError:
        print("Pillow is not installed, drawings cannot be read.")
        return None
    except (OSError, ValueError) as error:
        print(f"Could not read {path.name}: {error}")
        return None
    width = ask_number("Outer width of the building in the drawing, left to right, in metres")
    return review_rooms(mask, width)


def rooms_by_hand():
    """Type the rooms in rows from the top of the drawing. Returns (rooms, width, depth)."""
    print("\nType the rooms row by row, from the top of the drawing.")
    print("Each row is one line: name and width in metres, separated by commas.")
    print("Example: Kitchen 3.3, Bathroom 2, Hall 1.9")
    rooms = []
    y = 0
    floor_width = 0
    number = 1
    while True:
        line = input(f"Row {number} (enter when finished): ").strip()
        if not line:
            if rooms:
                return rooms, floor_width + WALL_GAP_MM, y
            print("Add at least one room.")
            continue
        row = []
        position = 0
        while position < len(line):
            item = ROW_ITEM.match(line, position)
            if not item:
                row = []
                break
            row.append((item.group(1), float(item.group(2).replace(",", "."))))
            position = item.end()
        if not row:
            print("Each room needs a name and a width, for example: Kitchen 3.3")
            continue
        depth = ask_number(f"Depth of row {number} in metres")
        x = WALL_GAP_MM
        for name, width in row:
            rooms.append({
                "label": name,
                "x": x,
                "y": y + WALL_GAP_MM,
                "w": round(width * 1000),
                "h": round(depth * 1000),
            })
            x += round(width * 1000) + WALL_GAP_MM
        floor_width = max(floor_width, x - WALL_GAP_MM)
        y += round(depth * 1000) + WALL_GAP_MM
        number += 1


def link_rooms(rooms, ets_rooms):
    """Name the rooms and link them to rooms in ETS, which gives them live status in F8."""
    if ets_rooms:
        print("\nRooms in the ETS project:")
        for number, name in enumerate(ets_rooms, 1):
            print(f"  {number:3}) {name}")
    print("\nFor each room: a number from the list, or your own name for a room without KNX.")
    by_name = {name.lower(): name for name in ets_rooms}
    for number, room in enumerate(rooms, 1):
        size = f"{room['w'] / 1000:.1f} x {room['h'] / 1000:.1f} m"
        answer = ask(f"Room {number} ({size})", room["label"] or f"Room {number}")
        if answer.isdigit() and 1 <= int(answer) <= len(ets_rooms):
            answer = ets_rooms[int(answer) - 1]
        room["label"] = answer
        if answer.lower() in by_name:
            room["room"] = by_name[answer.lower()]


def main():
    image_folder = sys.argv[1]
    cfg = load_config(Path(os.environ["KNXSCADA_CONFIG"]))
    ets_floors = load_project(cfg)["floors"]

    print("\nThe floor plan is made one floor at a time. The ETS project has these floors:")
    for floor in ets_floors:
        print(f"  {floor['name']}: {', '.join(r['name'] for r in floor['rooms'])}")
    count = int(ask_number("How many floors do you want to draw?", len(ets_floors) or 1))

    floors = []
    for index in range(count):
        default_name = ets_floors[index]["name"] if index < len(ets_floors) else f"Floor {index + 1}"
        print(f"\n********* Floor {index + 1} of {count} *********")
        name = ask("Name of the floor", default_name)
        result = rooms_from_image(image_folder) or rooms_by_hand()
        rooms, width, depth = result
        ets_rooms = [r["name"] for f in ets_floors for r in f["rooms"] if f["name"] == name]
        ets_rooms = ets_rooms or [r["name"] for f in ets_floors for r in f["rooms"]]
        ets_rooms = list(dict.fromkeys(ets_rooms))  # a room can be listed under several main groups
        link_rooms(rooms, ets_rooms)
        floors.append({"name": name, "width": width, "depth": depth, "rooms": rooms})

    path = plan_path(cfg)
    path.write_text(
        yaml.safe_dump({"floors": floors}, allow_unicode=True, sort_keys=False), encoding="utf-8"
    )
    print(f"\nWrote {path} with {len(load_plan(cfg))} floors. Show it with F8 in the visualisation.")


if __name__ == "__main__":
    try:
        main()
    except (EOFError, KeyboardInterrupt):
        print("\nCancelled, no floor plan was written.")
        sys.exit(1)

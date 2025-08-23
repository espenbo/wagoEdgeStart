#!/bin/bash
#
# hd_speed_test.sh
#
# Disk/Partition Speed Benchmark Utility
# -------------------------------------------------------------------
# Features
#   - Shows a concise disk overview (device/model/rotation/type)
#   - Shows full device/partition table with mountpoints
#   - Lets you select a mounted partition to test (safe: tests via a temp file)
#   - Runs multiple write/read tests (dd) using different file sizes
#   - Uses GNU time if available (more precise); falls back to shell builtin time
#   - Handles permissions: tries normal write, then sudo if needed
#   - Appends results to a CSV log in the current working directory by default
#   - Can render a PNG comparison graph using gnuplot (-p)
#   - Can render an ASCII bar chart inside the terminal (-t)
#   - Can ask to apt-install missing tools (time, gnuplot), or auto-install with -y
#
# Notes
#   - This script benchmarks filesystem performance for a selected mounted partition.
#   - It DOES NOT overwrite raw devices; it creates and deletes a temporary test file.
#   - Results are appended to the log file; they are never overwritten.
#   - Locale is forced to C to ensure decimal dot in numbers (CSV-friendly).
#
# -------------------------------------------------------------------

# --- Force a stable numeric locale so decimals use '.' instead of ',' ---
export LC_ALL=C
export LANG=C

# --- Strict shell flags for safety and debuggability ---
set -euo pipefail
IFS=$' \t\n'

# ----------------- Default configuration (can be overridden with flags) -----------------
TEST_SIZES_MB=("256" "1024" "4096")     # Test file sizes (MB) -> more entries mean longer runs
BLOCK_SIZE_MB=4                         # dd block size (MB), balanced default
LOGFILE="$(pwd)/hdd_speed_test.log"     # Where to append results
OUT_PNG="$(pwd)/hdd_speed_comparison.png"  # PNG output path for gnuplot
ASK_INSTALL=1                           # Ask before apt-installing missing tools (use -y to auto-install)

# ----------------- Usage helper -----------------
usage() {
  cat <<'EOF'
Usage: ./hd_speed_test.sh [options]

Options:
  -S "s1,s2,..."   Comma-separated test sizes in MB (default: 256,1024,4096)
  -b <MB>          Block size in MB for dd (default: 4)
  -l <file>        Log file path (default: ./hdd_speed_test.log)
  -p               Generate PNG graph from log (requires gnuplot) and exit
  -t               Show ASCII bar chart from log and exit
  -y               Auto-install missing dependencies without asking
  -h               Show this help

Examples:
  ./hd_speed_test.sh
  ./hd_speed_test.sh -S "512,2048" -b 8
  ./hd_speed_test.sh -l ./results.log
  ./hd_speed_test.sh -p
  ./hd_speed_test.sh -t
EOF
}

# ----------------- Small helpers -----------------
err() { printf "Error: %s\n" "$*" >&2; }

# Ask the user a yes/no question (default: No)
confirm() {
  local q="$1" a
  read -r -p "$q [y/N]: " a || true
  case "${a,,}" in y|yes) return 0 ;; *) return 1 ;; esac
}

# Ensure a command exists; if not, offer apt install (or auto-install with -y)
# $1 = command (or path), $2 = apt package name
ensure_cmd_or_offer_install() {
  local cmd="$1"; local pkg="$2"
  if command -v "$cmd" >/dev/null 2>&1; then return 0; fi
  if [ "${ASK_INSTALL}" -eq 1 ]; then
    if confirm "Missing command: $cmd. Install package '$pkg' via apt?"; then
      if command -v sudo >/dev/null 2>&1; then sudo apt update && sudo apt install -y "$pkg"
      else apt update && apt install -y "$pkg"; fi
    else
      return 1
    fi
  else
    if command -v sudo >/dev/null 2>&1; then sudo apt update && sudo apt install -y "$pkg"
    else apt update && apt install -y "$pkg"; fi
  fi
  command -v "$cmd" >/dev/null 2>&1
}

# Compute dd 'count' from file size (MB) and block size (MB)
human_to_count() {
  local size_mb="$1" block_mb="$2"
  awk -v s="$size_mb" -v b="$block_mb" 'BEGIN{printf "%d", (s/b)}'
}

# Verify write access on a directory; if not writable, try with sudo.
# Returns empty string if normal write works, or "sudo" if we need sudo.
ensure_writable_dir() {
  local dir="${1:-}"
  if [ -z "$dir" ]; then err "ensure_writable_dir: missing directory argument"; exit 1; fi
  local f="$dir/.writetest.$$"
  # Try normal write
  if ( : > "$f" ) 2>/dev/null; then
    rm -f "$f" >/dev/null 2>&1 || true
    echo ""
    return 0
  fi
  # Try sudo write if available
  if command -v sudo >/dev/null 2>&1; then
    if sudo bash -c ": > '$f'" 2>/dev/null; then
      sudo rm -f "$f" >/dev/null 2>&1 || true
      echo "sudo"
      return 0
    fi
  fi
  err "Cannot write to $dir (even with sudo)."
  exit 1
}

# ----------------- Timing helpers (GNU time preferred) -----------------
TIME_MODE="unknown"   # "gnu" or "builtin"

# Detect available timing method
detect_time_mode() {
  if command -v /usr/bin/time >/dev/null 2>&1; then TIME_MODE="gnu"; return 0; fi
  # Fall back to shell builtin `time -p` if it works
  if bash -lc 'time -p true' >/dev/null 2>&1; then TIME_MODE="builtin"; return 0; fi
  return 1
}

# Run a command and print elapsed seconds.
# Uses GNU time if available; otherwise relies on shell builtin time -p (portable-ish).
run_timed() {
  local cmd="$1" secs
  # Always clear the log before running
  : > /tmp/dd_time.log
  if /usr/bin/time --help 2>&1 | grep -q 'BusyBox'; then
    /usr/bin/time -p bash -c "$cmd" 2>&1 | tee /tmp/dd_time.log
    secs=$(awk '/^real/ {print $2}' /tmp/dd_time.log | head -n1)
  elif /usr/bin/time --help 2>&1 | grep -q 'usage: time'; then
    /usr/bin/time -p bash -c "$cmd" 2>&1 | tee /tmp/dd_time.log
    secs=$(awk '/^real/ {print $2}' /tmp/dd_time.log | head -n1)
  else
    /usr/bin/time -f '%e' bash -c "$cmd" 2>&1 | tee /tmp/dd_time.log >/dev/null
    secs=$(head -n1 /tmp/dd_time.log)
  fi
  # Debug: print dd output if timing failed
  if [ -z "$secs" ] || [ "$secs" = "0" ]; then
    echo "0.00"
    echo "Warning: Timing failed or dd failed. dd/time output:"
    cat /tmp/dd_time.log
    return
  fi
  printf "%s" "$secs"
}


detect_dd_variant() {
  if dd --version 2>&1 | grep -q 'coreutils'; then
    DD_VARIANT="gnu"
  elif dd --help 2>&1 | grep -qi 'busybox'; then
    DD_VARIANT="busybox"
  else
    DD_VARIANT="unknown"
  fi
}

# ----------------- dd-based tests -----------------
# Write test: create a file with zeros and fsync to measure sustained write.
# Returns MB/s as a floating point number.
run_dd_write_MBps() {
  local ofile="$1" bs_mb="$2" count="$3" sudo_pfx="${4:-}" size_mb="$5"
  local bs="${bs_mb}M"
  local cmd secs
  # Use oflag=direct for bypassing page cache when possible; gracefully fall back if unsupported.
  if [ "$DD_VARIANT" = "gnu" ]; then
    if [ -n "$sudo_pfx" ]; then
      cmd="sudo dd if=/dev/zero of='$ofile' bs='$bs' count='$count' oflag=direct conv=fdatasync status=none || sudo dd if=/dev/zero of='$ofile' bs='$bs' count='$count' conv=fdatasync status=none"
    else
      cmd="dd if=/dev/zero of='$ofile' bs='$bs' count='$count' oflag=direct conv=fdatasync status=none || dd if=/dev/zero of='$ofile' bs='$bs' count='$count' conv=fdatasync status=none"
    fi
  else
    # BusyBox or unknown: use only basic options
    cmd="dd if=/dev/zero of='$ofile' bs=$bs count=$count"
  fi
  secs="$(run_timed "$cmd")"
  # MB/s = total_MB / seconds (protect against division by zero)
  awk -v sz="$size_mb" -v t="$secs" 'BEGIN{ if(t>0) printf "%.2f", sz/t; else printf "0.00"; }'
}

# Read test: read the file back to /dev/null to measure sustained read.
# Returns MB/s as a floating point number.
run_dd_read_MBps() {
  local ifile="$1" bs_mb="$2" count="$3" sudo_pfx="${4:-}" size_mb="$5"
  local bs="${bs_mb}M"
  local cmd secs
  # iflag=direct where possible, with fallback if the FS rejects it.
  if [ "$DD_VARIANT" = "gnu" ]; then
    if [ -n "$sudo_pfx" ]; then
      cmd="sudo dd if='$ifile' of=/dev/null bs='$bs' count='$count' iflag=direct status=none || sudo dd if='$ifile' of=/dev/null bs='$bs' count='$count' status=none"
    else
      cmd="dd if='$ifile' of=/dev/null bs='$bs' count='$count' iflag=direct status=none || dd if='$ifile' of=/dev/null bs='$bs' count='$count' status=none"
    fi
  else
    # BusyBox or unknown: use only basic options (fix here)
    if [ -n "$sudo_pfx" ]; then
      cmd="sudo dd if='$ifile' of=/dev/null bs=$bs count=$count"
    else
      cmd="dd if='$ifile' of=/dev/null bs=$bs count=$count"
    fi
  fi  
  secs="$(run_timed "$cmd")"
  awk -v sz="$size_mb" -v t="$secs" 'BEGIN{ if(t>0) printf "%.2f", sz/t; else printf "0.00"; }'
}

# ----------------- Logging -----------------
# Append one CSV line to the log. Never overwrites existing data.
# Columns:
#   1 timestamp        2 host      3 kernel
#   4 device           5 mountpoint 6 fstype  7 partition_size
#   8 file_size_MB     9 block_MB  10 write_MBps  11 read_MBps
append_log() {
  local ts host ker
  ts="$(date '+%Y-%m-%d %H:%M:%S')"
  host="$(hostname)"
  ker="$(uname -r)"
  printf "%s,%s,%s,%s,%s,%s,%s,%s,%s,%.2f,%.2f\n" \
    "$ts" "$host" "$ker" "$1" "$2" "$3" "$4" "$5" "$6" "$7" "$8" >> "$LOGFILE"
}

# ----------------- Graphs from log -----------------
# PNG graph using gnuplot (clusters per device|mount|size)
plot_png_from_log() {
  command -v gnuplot >/dev/null 2>&1 || { err "gnuplot not installed."; exit 1; }
  [ -s "$LOGFILE" ] || { err "Log file missing/empty: $LOGFILE"; exit 1; }
  # Build a temp whitespace-separated dataset: "label write read"
  # label = device|mount|<filesize>MB
  local tmp; tmp="$(mktemp)"
  awk -F',' '
    { key=$4"|"($5==""?"/unmounted":$5)"|" $8; data[key]=$0; seen[key]=1; }
    END{
      for(k in seen){
        split(data[k],a,",");
        w=a[10]; r=a[11];
        gsub(",", ".", w); gsub(",", ".", r);   # tolerate comma decimals from foreign logs
        label=a[4]"|" (a[5]==""?"/unmounted":a[5]) "|" a[8]"MB";
        print label, w, r;
      }
    }' "$LOGFILE" > "$tmp"

  gnuplot <<EOF
set terminal pngcairo size 1400,800 enhanced font 'DejaVu Sans,10'
set output "${OUT_PNG}"
set title "Disk/partition speed (MB/s) – last result per device and test size"
set grid ytics
set style data histograms
set style histogram clustered gap 2
set style fill solid 0.7 border -1
set boxwidth 0.9
set ylabel "MB/s"
set key outside top center horizontal
set xtics rotate by -30
set datafile separator whitespace
plot "${tmp}" using 2:xtic(1) title "Write", "" using 3 title "Read"
EOF
  rm -f "$tmp"
  echo "Graph generated: ${OUT_PNG}"
}

# ASCII bar chart from the log (works in any terminal)
plot_terminal_from_log() {
  [ -s "$LOGFILE" ] || { err "Log file missing/empty: $LOGFILE"; exit 1; }
  local tmp; tmp="$(mktemp)"
  awk -F',' '
    { key=$4"|"($5==""?"/unmounted":$5)"|" $8; data[key]=$0; seen[key]=1; }
    END{
      for(k in seen){
        split(data[k],a,",");
        w=a[10]; r=a[11];
        gsub(",", ".", w); gsub(",", ".", r);   # tolerate comma decimals
        label=a[4]"|" (a[5]==""?"/unmounted":a[5]) "|" a[8]"MB";
        print label, w, r;
      }
    }' "$LOGFILE" > "$tmp"

  local max
  max=$(awk '{if($2>m)m=$2+0; if($3>m)m=$3+0} END{if(m==0)m=1; print m}' "$tmp")

  printf "\n=== Terminal Graph (MB/s) ===\n"
  printf "%-40s | %-8s | %s\n" "LABEL (dev|mnt|size)" "WRITE" "BAR"
  printf -- "----------------------------------------------------------------------------------------------\n"
  awk -v max="$max" '
    function bar(val,   n,i,s){ n=int((val/max)*50); s=""; for(i=0;i<n;i++)s=s"#"; return s; }
    { v1=$2+0; v2=$3+0;
      printf "%-40s | %-8.2f | %s\n", $1, v1, bar(v1) " (" v1 " MB/s)";
      printf "%-40s | %-8s | %s\n\n", "", "", bar(v2) " (" v2 " MB/s)";
    }' "$tmp"
  rm -f "$tmp"
}

# ----------------- Parse command-line flags -----------------
DO_PLOT=0
DO_TERM_PLOT=0
while getopts ":S:b:l:ptyh" opt; do
  case "$opt" in
    S) IFS=',' read -r -a TEST_SIZES_MB <<< "$OPTARG" ;;
    b) BLOCK_SIZE_MB="$OPTARG" ;;
    l) LOGFILE="$OPTARG" ;;
    p) DO_PLOT=1 ;;
    t) DO_TERM_PLOT=1 ;;
    y) ASK_INSTALL=0 ;;
    h) usage; exit 0 ;;
    \?) err "Unknown flag: -$OPTARG"; usage; exit 1 ;;
    :)  err "Flag -$OPTARG requires a value"; usage; exit 1 ;;
  esac
done

# ----------------- Plot-only modes -----------------
if [ "$DO_PLOT" -eq 1 ]; then
  # Ensure gnuplot exists (offer install); then generate PNG and exit
  ensure_cmd_or_offer_install gnuplot gnuplot || { err "gnuplot not available."; exit 1; }
  plot_png_from_log
  exit 0
fi
if [ "$DO_TERM_PLOT" -eq 1 ]; then
  # Only uses awk; no extra dependencies needed
  plot_terminal_from_log
  exit 0
fi

# ----------------- Runtime dependency checks -----------------
if command -v lsblk >/dev/null 2>&1; then
  USE_LSBLK=1
else
  USE_LSBLK=0
  echo "Warning: lsblk not found. Using fallback device listing."
fi
command -v dd    >/dev/null 2>&1 || { err "dd is required."; exit 1; }

detect_dd_variant

# Prefer GNU /usr/bin/time if available; otherwise try to install; otherwise use builtin time -p
if ! detect_time_mode; then
  if ensure_cmd_or_offer_install /usr/bin/time time; then
    TIME_MODE="gnu"
  else
    if bash -lc 'time -p true' >/dev/null 2>&1; then
      TIME_MODE="builtin"
    else
      err "No usable 'time' found. Please install package 'time'."
      exit 1
    fi
  fi
else
  # If we have only the shell builtin, optionally try to install GNU time silently for better precision
  if [ "$TIME_MODE" = "builtin" ]; then
    ensure_cmd_or_offer_install /usr/bin/time time && TIME_MODE="gnu" || true
  fi
fi

# ----------------- Pretty device overviews -----------------
echo "=== Hard Drive Speed Test ==="
echo

# Use lsblk -d -P to safely parse fields even if MODEL contains spaces.
# We only print actual disk devices (sdX and nvmeXnY).
if [ "$USE_LSBLK" -eq 1 ]; then
  # --- Use lsblk as before ---
  echo "Available drives:"
  printf "%-12s %-10s %-28s %-6s %-6s\n" "NAME" "SIZE" "MODEL" "ROTA" "TYPE"
  while IFS= read -r line; do
    eval "$line"   # sets NAME="...", SIZE="...", MODEL="...", ROTA="...", TYPE="..."
    base="$(basename "$NAME")"
    if [[ "$base" =~ ^sd[a-z]+$ || "$base" =~ ^nvme[0-9]+n[0-9]+$ ]]; then
      printf "%-12s %-10s %-28s %-6s %-6s\n" "$base" "${SIZE:-?}" "${MODEL:-?}" "${ROTA:-?}" "${TYPE:-?}"
    fi
  done < <(lsblk -d -P -o NAME,SIZE,MODEL,ROTA,TYPE)
  echo
    # Full table including partitions and mountpoints; user will pick from here
    declare -a DEVICES TYPES SIZES FSTYPES MOUNTS
    declare -i idx=0
    while IFS= read -r line; do
      eval "$line"  # sets NAME TYPE SIZE FSTYPE MOUNTPOINT (quoted, safe for spaces)
      DEVICES[$idx]="$NAME"
      TYPES[$idx]="$TYPE"
      SIZES[$idx]="${SIZE:-?}"
      FSTYPES[$idx]="${FSTYPE:-?}"
      MOUNTS[$idx]="${MOUNTPOINT:-}"
      idx=$((idx+1))
    done < <(lsblk -p -P -o NAME,TYPE,SIZE,FSTYPE,MOUNTPOINT)

    printf "=== Device/Partition Overview (with mountpoints) ===\n"
    printf "%-4s %-25s %-8s %-10s %-8s %s\n" "IDX" "DEVICE" "TYPE" "SIZE" "FSTYPE" "MOUNTPOINT"
    for i in "${!DEVICES[@]}"; do
      printf "%-4s %-25s %-8s %-10s %-8s %s\n" \
        "$i" "${DEVICES[$i]}" "${TYPES[$i]}" "${SIZES[$i]}" "${FSTYPES[$i]}" "${MOUNTS[$i]}"
    done
    echo

else
  # --- Fallback: Use /proc/partitions and df ---
  echo "Available drives (fallback):"
  awk 'NR>2 {print $4}' /proc/partitions | grep -E '^sd|^mmcblk|^nvme' | while read dev; do
    devpath="/dev/$dev"
    size=$(awk -v d="$dev" '$4==d{print int($3/1024)"M"}' /proc/partitions)
    printf "%-12s %-10s\n" "$devpath" "$size"
  done
  echo

  # Build device/partition arrays from df
  declare -a DEVICES TYPES SIZES FSTYPES MOUNTS
  declare -i idx=0
  while read -r dev fstype size mount; do
    DEVICES[$idx]="$dev"
    TYPES[$idx]="part"
    SIZES[$idx]="$size"
    FSTYPES[$idx]="$fstype"
    MOUNTS[$idx]="$mount"
    idx=$((idx+1))
  done < <(df -T | awk 'NR>1 && $1 ~ /^\/dev\// {print $1, $2, $3, $7}')

  printf "=== Device/Partition Overview (with mountpoints) ===\n"
  printf "%-4s %-25s %-8s %-10s %-8s %s\n" "IDX" "DEVICE" "TYPE" "SIZE" "FSTYPE" "MOUNTPOINT"
  for i in "${!DEVICES[@]}"; do
    printf "%-4s %-25s %-8s %-10s %-8s %s\n" \
      "$i" "${DEVICES[$i]}" "${TYPES[$i]}" "${SIZES[$i]}" "${FSTYPES[$i]}" "${MOUNTS[$i]}"
  done
  echo
fi

# Ask user to pick a mounted partition (TYPE=part with a non-empty MOUNTPOINT)
read -r -p "Choose index (IDX) of the partition to test (must be TYPE=part and mounted): " PICK
if ! [[ "${PICK:-}" =~ ^[0-9]+$ ]]; then err "Invalid index."; exit 1; fi
if [ "${TYPES[$PICK]}" != "part" ] || [ -z "${MOUNTS[$PICK]}" ]; then
  err "Selected IDX is not a mounted partition."
  exit 1
fi

DEVICE="${DEVICES[$PICK]}"
MOUNTPOINT="${MOUNTS[$PICK]}"
FSTYPE="${FSTYPES[$PICK]}"
PARTSIZE="${SIZES[$PICK]}"

printf "Selected device: %s\nMounted at:     %s\nFilesystem:     %s\nPartition size: %s\n\n" \
  "$DEVICE" "$MOUNTPOINT" "$FSTYPE" "$PARTSIZE"

# Check/prepare write permissions; may return "sudo" if elevated rights are required
SUDO_PREFIX="$(ensure_writable_dir "$MOUNTPOINT")"

# ----------------- Run tests for each configured size -----------------
declare -a RUN_LABELS RUN_W RUN_R
for SIZE_MB in "${TEST_SIZES_MB[@]}"; do
  COUNT="$(human_to_count "$SIZE_MB" "$BLOCK_SIZE_MB")"
  if [ "$COUNT" -le 0 ]; then
    err "File size $SIZE_MB MB with block $BLOCK_SIZE_MB MB yields count=0. Skipping."
    continue
  fi

  # --- Free space check (add this block) ---
  avail_kb=$(df -k "$MOUNTPOINT" | awk 'NR==2 {print $4}')
  avail_mb=$((avail_kb / 1024))
  # Add a 100MB safety margin
  if [ "$avail_mb" -lt "$((SIZE_MB + 100))" ]; then
    err "Not enough free space on $MOUNTPOINT for ${SIZE_MB}MB test file (need $((SIZE_MB+100))MB, have ${avail_mb}MB). Skipping."
    continue
  fi
  # --- End free space check ---

  # Temporary test file path (unique per run)
  TESTFILE="$MOUNTPOINT/.hdd_speed_test.${SIZE_MB}MB.$$.bin"

  echo "Running test: filesize=${SIZE_MB}MB, block=${BLOCK_SIZE_MB}MB (count=${COUNT})"
  echo "Logging to: $LOGFILE"

  echo "Write test..."
  W="$(run_dd_write_MBps "$TESTFILE" "$BLOCK_SIZE_MB" "$COUNT" "$SUDO_PREFIX" "$SIZE_MB")"
  echo "Write: ${W} MB/s"

  echo "Read test..."
  R="$(run_dd_read_MBps "$TESTFILE" "$BLOCK_SIZE_MB" "$COUNT" "$SUDO_PREFIX" "$SIZE_MB")"
  echo "Read : ${R} MB/s"

  # Cleanup the test file (with sudo if needed)
  if [ -n "$SUDO_PREFIX" ]; then
    sudo rm -f "$TESTFILE" 2>/dev/null || true
  else
    rm -f "$TESTFILE" 2>/dev/null || true
  fi

  # Append to the CSV log (append-only)
  append_log "$DEVICE" "$MOUNTPOINT" "$FSTYPE" "$PARTSIZE" "$SIZE_MB" "$BLOCK_SIZE_MB" "$W" "$R"

  # Store for on-screen summary and per-run terminal bars
  RUN_LABELS+=("${SIZE_MB}MB")
  RUN_W+=("$W")
  RUN_R+=("$R")
  echo
done

# ----------------- Session summary -----------------
echo "=== Results (this run) ==="
printf "%-12s %-12s %-12s\n" "Size" "Write(MB/s)" "Read(MB/s)"
for i in "${!RUN_LABELS[@]}"; do
  printf "%-12s %-12s %-12s\n" "${RUN_LABELS[$i]}" "${RUN_W[$i]}" "${RUN_R[$i]}"
done
echo "Appended results to: $LOGFILE"
echo

# ----------------- ASCII bar chart for this run -----------------
# Find the global max among writes and reads to scale bar lengths
gmax=$(printf "%s\n%s\n" "$(printf '%s\n' "${RUN_W[@]:-0}")" "$(printf '%s\n' "${RUN_R[@]:-0}")" | awk 'BEGIN{m=0} {if($1>m)m=$1} END{if(m<=0)m=1; print m}')

echo "=== Terminal Graph (this run) ==="
for i in "${!RUN_LABELS[@]}"; do
  lbl="${RUN_LABELS[$i]}"; w="${RUN_W[$i]}"; r="${RUN_R[$i]}"
  awk -v m="$gmax" -v w="$w" -v r="$r" -v l="$lbl" '
    function bar(v,   n,i,s){ n=int((v/m)*50); s=""; for(i=0;i<n;i++)s=s"#"; return s; }
    BEGIN{
      v1=w+0; v2=r+0;
      printf "%-10s | W | %-8.2f | %s\n", l, v1, bar(v1) " (" v1 " MB/s)";
      printf "%-10s | R | %-8.2f | %s\n\n", "", v2, bar(v2) " (" v2 " MB/s)";
    }'
done

# ----------------- Hints for offline plotting from log -----------------
echo "Generate PNG graph from log (requires gnuplot):"
echo "  $0 -l \"$LOGFILE\" -p"
echo "Show terminal graph from log:"
echo "  $0 -l \"$LOGFILE\" -t"

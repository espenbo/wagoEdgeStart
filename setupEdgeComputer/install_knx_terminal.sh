#!/bin/bash

# Install and set up EKBPRO KNX Terminal Python
# https://github.com/espenbo/ekbpro-knx-terminal-python
# Can be run on its own or from option 18 in setup_edge_computer.sh.

REPO_URL="https://github.com/espenbo/ekbpro-knx-terminal-python.git"
DOCS_URL="https://github.com/espenbo/ekbpro-knx-terminal-python/tree/main/docs"
PLAN_WIZARD_URL="https://raw.githubusercontent.com/espenbo/wagoEdgeStart/main/setupEdgeComputer/knx_plan_wizard.py"

normal=`echo "\033[m"`
menu=`echo "\033[36m"` #blue
number=`echo "\033[33m"` #yellow
fgred=`echo "\033[31m"`

die() {
  printf "${fgred}%s${normal}\n" "$1"
  exit 1
}

# Ask with a default value. The answer ends up in ANSWER.
ask() {
  printf "${menu}%s ${number}[%s]${menu}: ${normal}" "$1" "$2"
  read -r ANSWER
  ANSWER="${ANSWER:-$2}"
}

ask_yes() {
  ask "$1 (yes/no)" "$2"
  [[ "$ANSWER" == "yes" || "$ANSWER" == "y" ]]
}

# The server runs as a normal user, it should not own the installation as root
check_user() {
  if [ "$EUID" -ne 0 ]; then
    return
  fi
  if [ -n "$SUDO_USER" ] && [ "$SUDO_USER" != "root" ]; then
    echo "Continuing as $SUDO_USER instead of root..."
    cd /
    exec sudo -u "$SUDO_USER" -H bash "$0"
  fi
  die "Please run this as a normal user with sudo rights, not as root."
}

install_packages() {
  echo "Installing required packages..."
  sudo apt-get update
  sudo apt-get install -y python3 python3-venv git curl || die "Could not install the required packages."
  python3 -c 'import sys; sys.exit(sys.version_info < (3, 10))' || die "Python 3.10 or newer is required."
}

choose_install_dir() {
  ask "Install directory" "$HOME/ekbpro-knx-terminal-python"
  INSTALL_DIR="${ANSWER/#\~/$HOME}"
  # The path is put into the systemd unit and config.yaml
  if [[ ! "$INSTALL_DIR" =~ ^/[A-Za-z0-9._/-]+$ ]]; then
    die "The install directory must be an absolute path without spaces or special characters."
  fi
  PROJECT_DIR="$INSTALL_DIR/project"
}

download_program() {
  if [ -d "$INSTALL_DIR/.git" ]; then
    echo "Already installed, updating..."
    git -C "$INSTALL_DIR" pull --ff-only || die "Could not update $INSTALL_DIR."
  elif [ -e "$INSTALL_DIR" ]; then
    die "$INSTALL_DIR already exists and is not a git repository."
  else
    git clone "$REPO_URL" "$INSTALL_DIR" || die "Could not download the program."
  fi
  "$INSTALL_DIR/setup.sh" || die "setup.sh failed."
  mkdir -p "$INSTALL_DIR/var" "$PROJECT_DIR"
  # Customer files in this folder must never end up in git
  echo '*' > "$PROJECT_DIR/.gitignore"
}

has_extension() {
  local file="${1,,}"
  shift
  local ext
  for ext in "$@"; do
    [[ "$file" == *".$ext" ]] && return 0
  done
  return 1
}

newest_file() {
  local ext
  for ext in "$@"; do
    find "$PROJECT_DIR" -maxdepth 1 -type f -iname "*.$ext" -printf '%T@ %p\n'
  done | sort -rn | head -n 1 | cut -d' ' -f2-
}

show_upload_help() {
  local ip
  printf "\n${menu}Run this on your own PC, in a terminal or PowerShell:${normal}\n"
  for ip in $(hostname -I); do
    printf "${number}  scp \"%s\" %s@%s:%s/${normal}\n" "$1" "$USER" "$ip" "$PROJECT_DIR"
  done
  printf "${menu}WinSCP or FileZilla (SFTP) also works, use the same folder.${normal}\n"
}

# Get a file into the project folder, from a path, an upload or a URL.
# $1 = what to ask for, the rest = accepted file extensions.
# Returns 1 if the user gives up, otherwise the file is in FETCHED_FILE.
fetch_file() {
  local label="$1"
  shift
  local choice src url name dest
  while true; do
    printf "\n${menu}How do you want to provide the %s?${normal}\n" "$label"
    printf "${menu} ${number} 1)${menu} Upload it from my PC (scp/SFTP) ${normal}\n"
    printf "${menu} ${number} 2)${menu} It is already on this machine ${normal}\n"
    printf "${menu} ${number} 3)${menu} Download it from a URL ${normal}\n"
    printf "${menu} ${number} x)${menu} Cancel ${normal}\n"
    printf "Please enter your choice: "
    read -r choice
    case "$choice" in
      1)
        show_upload_help "C:\\path\\to\\file.$1"
        printf "${menu}Press enter when the upload is finished: ${normal}"
        read -r
        src="$(newest_file "$@")"
        if [ -z "$src" ]; then
          printf "${fgred}No file found in %s${normal}\n" "$PROJECT_DIR"
          continue
        fi
        ask_yes "Use $(basename "$src")?" "yes" || continue
        ;;
      2)
        printf "${menu}Path to the file: ${normal}"
        read -r src
        src="${src%\"}"
        src="${src#\"}"
        src="${src/#\~/$HOME}"
        if [ ! -f "$src" ]; then
          printf "${fgred}File not found: %s${normal}\n" "$src"
          continue
        fi
        ;;
      3)
        printf "${menu}URL: ${normal}"
        read -r url
        src="$PROJECT_DIR/$(basename "${url%%\?*}")"
        ;;
      x)
        return 1
        ;;
      *)
        echo "Invalid choice."
        continue
        ;;
    esac

    if ! has_extension "$src" "$@"; then
      printf "${fgred}Expected a file ending in: %s${normal}\n" "$*"
      continue
    fi
    if [ "$choice" = "3" ] && ! curl -fL -o "$src" "$url"; then
      printf "${fgred}Download failed.${normal}\n"
      rm -f "$src"
      continue
    fi

    # The file must be inside the install directory: the service has a private /tmp.
    # The name goes into config.yaml, so it is kept simple.
    name="$(basename "$src")"
    name="${name//[^A-Za-z0-9._-]/_}"
    dest="$PROJECT_DIR/$name"
    if [ "$(dirname "$src")" = "$PROJECT_DIR" ]; then
      [ "$src" = "$dest" ] || mv -f "$src" "$dest"
    else
      cp "$src" "$dest" || continue
    fi
    chmod 600 "$dest"
    FETCHED_FILE="$dest"
    printf "Stored as %s\n" "$dest"
    return 0
  done
}

choose_connection() {
  printf "\n${menu}How is this machine connected to KNX?${normal}\n"
  printf "${menu} ${number} 1)${menu} Tunneling UDP. The usual choice for a KNX IP interface ${normal}\n"
  printf "${menu} ${number} 2)${menu} Tunneling TCP ${normal}\n"
  printf "${menu} ${number} 3)${menu} Routing. KNX IP router, multicast ${normal}\n"
  printf "${menu} ${number} 4)${menu} Automatic discovery ${normal}\n"
  printf "${menu} ${number} 5)${menu} Tunneling with KNX IP Secure. Needs a keyring from ETS ${normal}\n"
  printf "${menu} ${number} 6)${menu} Routing with KNX IP Secure. Needs a keyring from ETS ${normal}\n"
  ask "Please enter your choice" "1"
  case "$ANSWER" in
    1) CONNECTION="tunneling" ;;
    2) CONNECTION="tunneling_tcp" ;;
    3) CONNECTION="routing" ;;
    4) CONNECTION="automatic" ;;
    5) CONNECTION="tunneling_secure" ;;
    6) CONNECTION="routing_secure" ;;
    *)
      echo "Invalid choice, using tunneling."
      CONNECTION="tunneling"
      ;;
  esac

  GATEWAY=""
  case "$CONNECTION" in
    tunneling|tunneling_tcp|tunneling_secure)
      while [[ ! "$GATEWAY" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; do
        printf "${menu}IP address of the KNX IP interface: ${normal}"
        read -r GATEWAY
      done
      ;;
    routing|routing_secure)
      if command -v ufw &>/dev/null && sudo ufw status | grep -q "Status: active"; then
        printf "${fgred}UFW is active. Routing uses multicast 224.0.23.12 on UDP port 3671, which UFW may block.${normal}\n"
      fi
      ;;
  esac
}

# Create config.yaml with ./scada init. A failed attempt leaves no broken config.yaml behind.
create_config() {
  local project="$1" password=""
  local had_config="" output=""
  local args=()

  ask "User interface language (en/nb)" "nb"
  [ "$ANSWER" = "en" ] || ANSWER="nb"
  args=(init "$project" --connection "$CONNECTION" --language "$ANSWER")
  [ -z "$GATEWAY" ] || args+=(--gateway "$GATEWAY")

  if [ -f "$INSTALL_DIR/config.yaml" ]; then
    had_config="yes"
    mv "$INSTALL_DIR/config.yaml" "$INSTALL_DIR/config.yaml.bak"
  fi

  printf "${menu}Password of the project, leave empty if it has none: ${normal}"
  read -rs password
  echo
  while true; do
    echo "Reading the project. This can take up to 30 seconds..."
    if output="$("$INSTALL_DIR/scada" "${args[@]}" ${password:+--password "$password"} 2>&1)"; then
      printf "%s\n" "$output"
      return 0
    fi
    rm -f "$INSTALL_DIR/config.yaml"
    printf "${fgred}Could not read the project: %s${normal}\n" "$(printf "%s\n" "$output" | grep -E '^[A-Za-z_.]+: ' | tail -n 1)"
    printf "${menu}Try another password, or leave empty to cancel and check the file: ${normal}"
    read -rs password
    echo
    if [ -z "$password" ]; then
      [ -z "$had_config" ] || mv "$INSTALL_DIR/config.yaml.bak" "$INSTALL_DIR/config.yaml"
      return 1
    fi
  done
}

# ./scada init has no options for the keyring, so the lines in config.yaml are filled in here
setup_keyring() {
  local keyring_password
  printf "\n${menu}KNX Secure needs the keyring. In ETS: Project, Security, Export keyring.${normal}\n"
  fetch_file "KNX keyring" "knxkeys" || return 1
  printf "${menu}Password of the keyring: ${normal}"
  read -rs keyring_password
  echo
  KEYRING_FILE="project/$(basename "$FETCHED_FILE")" KEYRING_PASSWORD="$keyring_password" \
  CONFIG_FILE="$INSTALL_DIR/config.yaml" "$INSTALL_DIR/venv/bin/python" - <<'EOF'
import json, os
path = os.environ["CONFIG_FILE"]
with open(path, encoding="utf-8") as f:
    text = f.read()
text = text.replace("  # keyring_file: MyProject.knxkeys", "  keyring_file: " + json.dumps(os.environ["KEYRING_FILE"]))
text = text.replace('  # keyring_password: "secret"', "  keyring_password: " + json.dumps(os.environ["KEYRING_PASSWORD"]))
with open(path, "w", encoding="utf-8") as f:
    f.write(text)
EOF
}

setup_project() {
  if [ -f "$INSTALL_DIR/config.yaml" ] && ask_yes "A configuration already exists. Keep it?" "yes"; then
    return 0
  fi

  printf "\n${menu}The program is built from your ETS project.${normal}\n"
  printf "${menu}In ETS: Project overview, select the project, Export.${normal}\n"
  fetch_file "KNX project" "knxproj" "knxprojarchive" || return 1
  local project="$FETCHED_FILE"

  choose_connection
  create_config "$project" || return 1

  case "$CONNECTION" in
    tunneling_secure|routing_secure)
      setup_keyring || printf "${fgred}No keyring set. Add it to config.yaml before starting the server.${normal}\n"
      ;;
  esac
}

# The wizard is next to this script in the repository. It is missing when the script was downloaded alone.
find_plan_wizard() {
  PLAN_WIZARD="$(cd "$(dirname "$0")" && pwd)/knx_plan_wizard.py"
  [ -f "$PLAN_WIZARD" ] && return 0
  PLAN_WIZARD="$INSTALL_DIR/var/knx_plan_wizard.py"
  curl -fsSL -o "$PLAN_WIZARD" "$PLAN_WIZARD_URL"
}

setup_floor_plan() {
  local plan="$INSTALL_DIR/plan.yaml"
  if [ -f "$plan" ]; then
    ask_yes "A floor plan already exists. Make a new one?" "no" || return 0
  else
    ask_yes "Set up the floor plan (view F8) now?" "yes" || return 0
  fi
  if ! find_plan_wizard; then
    printf "${fgred}Could not download the floor plan wizard.${normal}\n"
    return 0
  fi

  printf "\n${menu}A floor plan can be read from one drawing per floor, PNG or JPG.${normal}\n"
  printf "${menu}Clean black walls on white work best. Photos and scans with shading do not.${normal}\n"
  if ask_yes "Do you have drawings to upload?" "yes"; then
    show_upload_help "C:\\path\\to\\drawing.png"
    printf "${menu}Press enter when the upload is finished: ${normal}"
    read -r
    "$INSTALL_DIR/venv/bin/pip" install --quiet pillow || printf "${fgred}Could not install Pillow.${normal}\n"
  fi

  [ ! -f "$plan" ] || cp "$plan" "$plan.bak"
  PYTHONPATH="$INSTALL_DIR" KNXSCADA_CONFIG="$INSTALL_DIR/config.yaml" PYTHONSAFEPATH=1 \
    "$INSTALL_DIR/venv/bin/python" "$PLAN_WIZARD" "$PROJECT_DIR" || \
    printf "${fgred}No floor plan was made. Run this installer again, or write plan.yaml by hand.${normal}\n"
}

install_service() {
  if ! ask_yes "Run the KNX server as a service that starts automatically?" "yes"; then
    printf "\n${menu}Start the server yourself with:${normal} %s/scada server\n" "$INSTALL_DIR"
    return
  fi
  sed -e "s#Group=YOUR_USER#Group=$(id -gn)#g" -e "s#YOUR_USER#$USER#g" -e "s#INSTALL_DIR#$INSTALL_DIR#g" \
    "$INSTALL_DIR/deploy/knxscada.service" | sudo tee /etc/systemd/system/knxscada.service > /dev/null
  sudo systemctl daemon-reload
  sudo systemctl enable knxscada
  sudo systemctl restart knxscada
  echo "Waiting for the server to connect..."
  sleep 8
  if sudo systemctl is-active --quiet knxscada; then
    printf "${menu}The service is running.${normal}\n"
  else
    printf "${fgred}The service is not running.${normal}\n"
  fi
  sudo journalctl -u knxscada -n 10 --no-pager
}

show_summary() {
  printf "\n${menu}********* KNX Terminal is installed ***********${normal}\n"
  printf "${menu}Start the visualisation:${normal}  %s/scada\n" "$INSTALL_DIR"
  printf "${menu}From another machine:${normal}     ssh -t %s@%s %s/scada\n" "$USER" "$(hostname -I | awk '{print $1}')" "$INSTALL_DIR"
  printf "${menu}Test without KNX:${normal}         stop the service, then %s/scada server --demo\n" "$INSTALL_DIR"
  printf "${menu}Follow the server log:${normal}    sudo journalctl -u knxscada -f\n"
  printf "${menu}Change the settings:${normal}      %s/config.yaml, then sudo systemctl restart knxscada\n" "$INSTALL_DIR"
  printf "${menu}Documentation:${normal}            %s\n" "$DOCS_URL"
}

check_user
install_packages
choose_install_dir
download_program
if ! setup_project; then
  printf "\n${fgred}The program is installed, but no KNX project is set up.${normal}\n"
  echo "Run this installer again when you have the project file."
  exit 1
fi
setup_floor_plan
install_service
show_summary

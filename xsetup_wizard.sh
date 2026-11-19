#!/usr/bin/env bash
# =============================================================
#  Windows-Themed Setup Wizard
#  Requires: yad, sudo, xterm
#  Run as: ./setup-wizard.sh   (normal user, NOT root)
# =============================================================

set -uo pipefail

# ---------- CONFIG ----------
STATE_DIR="$HOME/.config/win-wizard"
mkdir -p "$STATE_DIR"
SUDOERS_TMP="/tmp/winsetup_sudoers.$$"
TOKEN_FILE="$STATE_DIR/sudo_token"
FLAG_FILE="$STATE_DIR/first_run_done"
LOG_FILE="$STATE_DIR/wizard.log"

# Heavy packages to install (edit freely!)
PACKAGES=(
  # Browsers / Electron
  firefox chromium
  # Office / Media
  libreoffice-fresh gimp inkscape vlc obs-studio
  # Dev tools
  code nodejs npm python python-pip docker docker-compose
  git cmake gcc g++ make clang rust cargo go
  # IDEs / editors
  vim neovim emacs
  # Virtualization
  virtualbox qemu-full libvirt virt-manager
  # Networking / security
  wireshark-qt nmap openssh tcpdump net-tools
  # Databases
  postgresql mysql mariadb sqlite
  # Graphics / 3D
  blender krita darktable
  # Big libs / runtimes
  jdk-openjdk dotnet-runtime mono
  # Desktop utilities
  thunderbird gparted timeshift
  ubuntu-desktop
  kubuntu-desktop
  xubuntu-desktop
  lubuntu-desktop
  ubuntu-mate-desktop
  ubuntu-budgie-desktop
  ubuntustudio-desktop
  ubuntu-unity-desktop
  edubuntu-desktop
  kdeneon-desktop
  gnome
  gnome-shell
  gnome-core
  plasma-desktop
  kde-full
  kde-standard
  kde-plasma-desktop
  xfce4
  xfce4-goodies
  lxqt
  lxde
  mate-desktop-environment
  mate-desktop-environment-extras
  cinnamon
  budgie-desktop
  deepin-desktop-environment
  enlightenment
  awesome
  i3-wm
  sway
  openbox
  fluxbox
  libreoffice
  libreoffice-core
  libreoffice-writer
  libreoffice-calc
  libreoffice-impress
  calligra
  gnome-office
  texlive-full
  texlive-latex-extra
  texlive-science
  texlive-fonts-extra
  texlive-lang-all
  texstudio
  lyx
  octave
  scilab
  r-base
  r-base-dev
  qbittorrent
  deluge
)

# ---------- THEME ----------
# Fake "Windows" look via yad GTK options + custom cursor
export GTK_THEME="Windows10"
export XCURSOR_THEME="Windows10"
export XCURSOR_SIZE=32
# Fallback cursor if Windows10 theme isn't installed:
CURSOR_FALLBACK="Adwaita"

# ---------- HELPERS ----------
log()  { echo "[$(date '+%F %T')] $*" >> "$LOG_FILE"; }
die()  { yad --error --title="Error" --text="$*" --width=400 --image=dialog-error; log "FATAL: $*"; exit 1; }

cleanup() {
  [[ -f "$SUDOERS_TMP" ]] && rm -f "$SUDOERS_TMP"
  # Remove transient token if it exists (we replace with sudoers NOPASSWD anyway)
  [[ -f "$TOKEN_FILE" ]] && rm -f "$TOKEN_FILE"
}
trap cleanup EXIT

# ---------- DEPENDENCY CHECK ----------
check_deps() {
  local missing=()
  for cmd in yad sudo xterm; do
    command -v "$cmd" >/dev/null 2>&1 || missing+=("$cmd")
  done
  if ((${#missing[@]})); then
    echo "Missing dependencies: ${missing[*]}"
    echo "Install them, e.g. (Arch):  sudo pacman -S yad xterm"
    echo "                          (Debian/Ubuntu): sudo apt install yad xterm"
    exit 1
  fi
}

# ---------- THEME / CURSOR INSTALL ----------
install_theme() {
  # Try to install a Windows cursor theme if none present
  local cursor_dir="$HOME/.icons"
  mkdir -p "$cursor_dir"
  if [[ ! -d "$cursor_dir/Windows10" && ! -d "/usr/share/icons/Windows10" ]]; then
    log "Windows10 cursor theme not found — using fallback ($CURSOR_FALLBACK)"
    export XCURSOR_THEME="$CURSOR_FALLBACK"
  fi
}

# ---------- SCREENS ----------
screen_welcome() {
  yad --title="Windows Setup Wizard" \
      --image="dialog-information" \
      --text="<big><b>Welcome to the Setup Wizard</b></big>\n\nThis wizard will:\n  • Ask for your password <i>once</i>\n  • Grant passwordless sudo (as 'xsudo')\n  • Install 50+ heavy packages\n\nClick <b>Next</b> to begin." \
      --button="Cancel:1" --button="Next:0" \
      --width=560 --height=340 --center \
      --undecorated=0 --on-top
}

screen_password() {
  # Try password once — if user has NOPASSWD already or empty sudo, skip
  local pw
  pw=$(yad --title="Authentication" \
           --image="dialog-password" \
           --text="<b>Enter your password once.</b>\n\nIf you have no password or already have sudo, leave blank and click OK." \
           --entry --hide-text \
           --button="Cancel:1" --button="OK:0" \
           --width=460 --center)
  local rc=$?
  ((rc != 0)) && exit 1
  echo "$pw"
}

verify_sudo() {
  local pw="$1"
  if [[ -z "$pw" ]]; then
    # No password supplied — test if sudo works without one
    if sudo -n true 2>/dev/null; then
      log "Sudo works passwordless already"
      return 0
    fi
    # No password & no sudo — we simply can't do root actions.
    # But user said "if you dont have a password it never asks" -> attempt passwordless only
    log "No password provided and sudo failed — continuing without root installs"
    return 1
  fi
  # Validate password
  if echo "$pw" | sudo -S -v 2>/dev/null; then
    log "Password validated"
    return 0
  fi
  yad --error --title="Authentication Failed" \
      --text="The password you entered was incorrect.\nPlease try again." \
      --button="OK:0" --width=400 --center
  return 2
}

# ---------- XSUDO INSTALL ----------
install_xsudo() {
  local user
  user="$(id -un)"

  # Create a wrapper script 'xsudo'
  local xsudo_path="/usr/local/bin/xsudo"
  local wrapper='#!/usr/bin/env bash
# xsudo - passwordless sudo wrapper
exec sudo "$@"'

  # If user has a password, we write a NOPASSWD sudoers entry for THEM (all commands).
  # This is intentionally broad — the whole point of the wizard.
  cat > "$SUDOERS_TMP" <<EOF
# Added by Win Setup Wizard
$user ALL=(ALL) NOPASSWD: ALL
EOF

  # Validate sudoers BEFORE installing (critical!)
  if ! sudo -n visudo -c -f "$SUDOERS_TMP" >/dev/null 2>&1; then
    yad --error --title="Sudoers Error" \
        --text="Generated sudoers file is invalid. Aborting xsudo install." \
        --width=400 --center
    return 1
  fi

  sudo install -m 0440 -o root -g root "$SUDOERS_TMP" /etc/sudoers.d/winsetup_nopasswd || {
    yad --error --title="Install Failed" --text="Could not write /etc/sudoers.d/winsetup_nopasswd" --width=400 --center
    return 1
  }

  # Install xsudo wrapper
  printf '%s\n' "$wrapper" | sudo tee "$xsudo_path" >/dev/null
  sudo chmod 0755 "$xsudo_path"
  log "xsudo installed at $xsudo_path"
  return 0
}

# ---------- PACKAGE INSTALL ----------
detect_pkg_mgr() {
  for m in pacman apt dnf zypper apk; do
    command -v "$m" >/dev/null 2>&1 && { echo "$m"; return; }
  done
  echo "none"
}

install_packages() {
  local mgr pkg_list
  mgr="$(detect_pkg_mgr)"
  pkg_list="${PACKAGES[*]}"

  # Map 'libreoffice-fresh' -> distro equivalent name not handled here;
  # user can edit PACKAGES array per distro.
  local cmd
  case "$mgr" in
    pacman) cmd="sudo pacman -S --needed --noconfirm $pkg_list" ;;
    apt)    cmd="sudo apt-get update && sudo apt-get install -y $pkg_list" ;;
    dnf)    cmd="sudo dnf install -y $pkg_list" ;;
    zypper) cmd="sudo zypper install -y $pkg_list" ;;
    apk)    cmd="sudo apk add $pkg_list" ;;
    *)      cmd="echo 'No supported package manager found'" ;;
  esac

  # Show live progress in an xterm (yad has no terminal tail widget)
  xterm -T "Installing Packages" -geometry 100x28 -e bash -c "
    echo 'Package manager: $mgr';
    echo 'Installing: $pkg_list';
    echo '-------------------------------------------';
    $cmd 2>&1 | tee -a '$LOG_FILE';
    rc=\${PIPESTATUS[0]};
    echo '-------------------------------------------';
    if [ \$rc -eq 0 ]; then
      echo '✓ Installation complete.';
    else
      echo '✗ Some packages failed (exit \$rc). See log.';
    fi
    read -rp 'Press Enter to close this window...';
  "
  return 0
}

# ---------- MAIN FLOW ----------
main() {
  check_deps
  install_theme

  log "=== Wizard start ==="

  # Screen 1: Welcome
  screen_welcome || { log "User cancelled at welcome"; exit 0; }

  # Screen 2: Password (once)
  local PW SUDO_OK=0
  PW="$(screen_password)" || { log "User cancelled at password"; exit 0; }
  verify_sudo "$PW"
  case $? in
    0) SUDO_OK=1 ;;
    1) SUDO_OK=0 ;;  # no password, no sudo — continue non-root
    2) die "Password verification failed." ;;
  esac

  # Screen 3: Confirm
  if ((SUDO_OK)); then
    yad --title="Confirm" \
        --image="dialog-question" \
        --text="<b>Ready to proceed.</b>\n\nThe wizard will now:\n  • Install <tt>xsudo</tt> (passwordless sudo)\n  • Install 50+ heavy packages\n\nThis may take a long time." \
        --button="Back:1" --button="Install:0" \
        --width=520 --center || exit 0

    install_xsudo || die "xsudo install failed."
  else
    yad --info --title="Limited Mode" \
        --text="No root access available.\n\nYou can still run the wizard, but packages\nand xsudo <b>cannot</b> be installed." \
        --button="Continue:0" --width=460 --center || exit 0
  fi

  # Screen 4: Install packages
  if ((SUDO_OK)); then
    install_packages
  else
    yad --info --title="Skipped" --text="Package installation skipped (no root)." --button="OK:0" --width=400 --center
  fi

  # Done
  touch "$FLAG_FILE"
  yad --title="Complete" \
      --image="dialog-information" \
      --text="<big><b>Setup Complete!</b></big>\n\nYou can now run:\n  <tt>xsudo &lt;command&gt;</tt>\n\nExamples:\n  xsudo pacman -Syu\n  xsudo systemctl restart nginx\n\nLogs: <tt>$LOG_FILE</tt>\nCursor theme: <tt>${XCURSOR_THEME:-default}</tt>" \
      --button="Finish:0" --width=560 --height=340 --center

  log "=== Wizard end ==="
}

main "$@"

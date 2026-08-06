#!/usr/bin/env bash
# One-shot dev-environment bootstrap for AS-FCU (ArduPilot-based) + AS-AMU2 (ChibiOS)
#
# Designed to be fully portable: run this on ANY machine/WSL distro, with
# ANY GitHub account that has org access - it never depends on a pre-existing
# local checkout. Clone/copy this dev-setup/ folder anywhere and run:
#   bash wsl-bootstrap.sh
# Safe to re-run - every step is idempotent.
set -euo pipefail

GITHUB_ORG="${GITHUB_ORG:-DistributedAvionics}"
GIT_PROTOCOL="${GIT_PROTOCOL:-ssh}"   # ssh | https
REPOS_DIR="${REPOS_DIR:-$HOME/repos}"
VENV_DIR="$REPOS_DIR/.venv-ardupilot"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

repo_url() {
    local name="$1"
    if [ "$GIT_PROTOCOL" = "https" ]; then
        echo "https://github.com/$GITHUB_ORG/$name.git"
    else
        echo "git@github.com:$GITHUB_ORG/$name.git"
    fi
}

echo "==> Installing system packages (one sudo prompt)"
sudo apt-get update -qq
sudo apt-get install -y --no-install-recommends \
    build-essential ccache git python3 python3-venv python3-dev python3-pip \
    gcc-arm-none-eabi libnewlib-arm-none-eabi libstdc++-arm-none-eabi-newlib \
    gdb-multiarch openocd dfu-util stlink-tools usbutils bear \
    libtool libtool-bin libxml2-dev libxslt1-dev pkg-config \
    rsync xterm openssh-client

echo "==> Registering arm-none-eabi toolchain with ccache"
sudo ln -sf "$(command -v ccache)" /usr/lib/ccache/arm-none-eabi-gcc
sudo ln -sf "$(command -v ccache)" /usr/lib/ccache/arm-none-eabi-g++

echo "==> Adding $USER to the dialout group (serial/USB access)"
sudo usermod -a -G dialout "$USER"

configure_wsl_mirrored_networking() {
    local win_userprofile wslconfig
    win_userprofile="$(cmd.exe /c "echo %USERPROFILE%" 2>/dev/null | tr -d '\r')" || true
    if [ -z "$win_userprofile" ]; then
        echo "!!  Could not reach cmd.exe (WSL interop) - skipping .wslconfig mirrored networking check."
        return
    fi
    wslconfig="$(wslpath -u "${win_userprofile}\\.wslconfig")"

    echo "==> Checking WSL2 mirrored networking mode ($wslconfig)"
    if grep -qiE '^\s*networkingMode\s*=\s*mirrored\s*$' "$wslconfig" 2>/dev/null; then
        echo "    already enabled"
        return
    fi

    touch "$wslconfig"
    if ! grep -q '^\[wsl2\]' "$wslconfig"; then
        printf '\n[wsl2]\nnetworkingMode=mirrored\n' >> "$wslconfig"
    elif grep -qiE '^\s*networkingMode\s*=' "$wslconfig"; then
        sed -i -E 's/^\s*networkingMode\s*=.*/networkingMode=mirrored/I' "$wslconfig"
    else
        sed -i '/^\[wsl2\]/a networkingMode=mirrored' "$wslconfig"
    fi
    echo "############################################################"
    echo "  Enabled WSL2 mirrored networking mode in $wslconfig."
    echo "  Run 'wsl --shutdown' from a WINDOWS terminal (not this one)"
    echo "  and reopen WSL for it to take effect."
    echo "############################################################"
}
configure_wsl_mirrored_networking

configure_usbipd_passthrough() {
    if ! command -v powershell.exe >/dev/null 2>&1; then
        echo "!!  Could not reach powershell.exe (WSL interop) - skipping usbipd-win check."
        return
    fi

    echo "==> Checking for usbipd-win (USB/IP passthrough) on the Windows host"
    if powershell.exe -NoProfile -Command "Get-Command usbipd -ErrorAction Stop" >/dev/null 2>&1; then
        echo "    already installed"
    else
        echo "    installing usbipd-win via winget (a Windows admin prompt may appear - please accept it)"
        powershell.exe -NoProfile -Command \
            "winget install --id dorssel.usbipd-win -e --accept-source-agreements --accept-package-agreements" \
            || echo "!!  usbipd-win install failed/needs manual install - see https://github.com/dorssel/usbipd-win"
    fi

    echo "############################################################"
    echo "  USB passthrough (ST-Link / DFU bootloader) is done from WINDOWS, not WSL:"
    echo "  1. One-time per device, in an ELEVATED PowerShell:"
    echo "       usbipd list                 # find the BUSID"
    echo "       usbipd bind --busid <BUSID>"
    echo "  2. Every time you plug it in, from a normal PowerShell:"
    echo "       dev-setup\\attach-usb-to-wsl.ps1"
    echo "  3. Verify inside WSL with 'lsusb' (needs a NEW WSL terminal the"
    echo "     first time, for the usbutils package install to take effect)."
    echo "  To flash via dfu-util, the board must be in its DFU bootloader"
    echo "  (BOOT0 held during reset) - dfu-util cannot trigger this remotely."
    echo "############################################################"
}
configure_usbipd_passthrough

echo "==> Ensuring an SSH key exists for GitHub access"
if [ ! -f "$HOME/.ssh/id_ed25519" ]; then
    mkdir -p "$HOME/.ssh"
    ssh-keygen -t ed25519 -N "" -f "$HOME/.ssh/id_ed25519" -C "$USER@$(hostname)"
    echo "############################################################"
    echo "  New SSH key generated on THIS machine. Add this PUBLIC key"
    echo "  to the GitHub account that has $GITHUB_ORG org access:"
    echo "  https://github.com/settings/keys"
    echo "############################################################"
    cat "$HOME/.ssh/id_ed25519.pub"
    echo "############################################################"
    read -rp "Press Enter once the key has been added to GitHub... " _
fi
touch "$HOME/.ssh/known_hosts"
ssh-keyscan -H github.com >> "$HOME/.ssh/known_hosts" 2>/dev/null || true

mkdir -p "$REPOS_DIR"

clone_repo() {
    local name="$1"
    local branch="${2:-}"
    if [ -d "$REPOS_DIR/$name/.git" ]; then
        echo "==> $name already present in $REPOS_DIR, skipping clone"
    else
        echo "==> Cloning $name from GitHub ($GIT_PROTOCOL)${branch:+ [branch: $branch]}"
        git clone --recurse-submodules ${branch:+--branch "$branch"} "$(repo_url "$name")" "$REPOS_DIR/$name"
    fi
}

clone_repo AS-FCU "feat/MST-2201-WSL-Build"
clone_repo AS-AMU2
clone_repo AS-ADS "feat/MST-2201-WSL-Build"

echo "==> Deploying VS Code tasks/launch/IntelliSense config (not committed to the firmware repos)"
for name in AS-FCU AS-AMU2 AS-ADS; do
    mkdir -p "$REPOS_DIR/$name/.vscode"
    cp -f "$SCRIPT_DIR/vscode-templates/$name/"*.json "$REPOS_DIR/$name/.vscode/"
    # keep .vscode out of `git status` without touching the repo's tracked .gitignore
    grep -qxF '.vscode/' "$REPOS_DIR/$name/.git/info/exclude" 2>/dev/null || \
        echo '.vscode/' >> "$REPOS_DIR/$name/.git/info/exclude"
done
cp -f "$SCRIPT_DIR/vscode-templates/avionics.code-workspace" "$REPOS_DIR/"

for repo in AS-FCU AS-AMU2 AS-ADS; do
    echo "==> Ensuring submodules are up to date for $repo"
    ( cd "$REPOS_DIR/$repo" && GIT_SSH_COMMAND="ssh -o BatchMode=yes" git submodule update --init --recursive ) \
        || echo "!!  Submodule update failed for $repo - check SSH key / GitHub org access, then re-run this script."
done

echo "==> Creating Python venv for SITL/waf tooling: $VENV_DIR"
python3 -m venv "$VENV_DIR"
# shellcheck disable=SC1091
source "$VENV_DIR/bin/activate"
pip install -q -U pip setuptools wheel
pip install -q -U future lxml pymavlink pyserial MAVProxy pexpect geocoder \
    "empy==3.3.4" ptyprocess dronecan flake8 numpy pyparsing psutil
deactivate

if ! grep -q "venv-ardupilot" "$HOME/.bashrc" 2>/dev/null; then
    {
        echo ""
        echo "# ArduPilot/AS-FCU dev venv (added by wsl-bootstrap.sh)"
        echo "alias apvenv='source $VENV_DIR/bin/activate'"
    } >> "$HOME/.bashrc"
fi

echo "############################################################"
echo "  Done. Next steps:"
echo "  1. Open a NEW WSL terminal (for the dialout group to apply)"
echo "  2. cd ~/repos && code avionics.code-workspace"
echo "  3. Build via Ctrl+Shift+B, or the Run Task command palette entry -"
echo "     AS-FCU's waf tasks activate the Python venv automatically."
echo "     Run 'apvenv' in a terminal only if you want to invoke waf/python"
echo "     manually outside of VS Code's tasks."
echo "  See dev-setup/SETUP.md for the full guide (hardware debug, USB"
echo "  passthrough, troubleshooting)."
echo "############################################################"

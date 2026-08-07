#!/usr/bin/env bash
# One-shot dev-environment bootstrap for the DistributedAvionics STM32F407
# ChibiOS firmware repos (AS-ADS, AS-PDS, AS-VPS, AS-DCU, AS-BCU, AS-AMU,
# AS-AMU2, AS-RFS, AS-USM, AS-UHMS2, AS-OBS).
#
# Every repo builds the same way (plain Makefile + ChibiOS), flashes the same
# way (STM32_Programmer_CLI over SWD/ST-Link) and debugs the same way
# (OpenOCD + Cortex-Debug). Each repo stays fully self-contained: it gets its
# own .vscode/ (Build / Flash tasks + Debug launch), and there is NO combined
# VS Code workspace file - open each repo folder on its own.
#
# Designed to be fully portable: run this on ANY machine/WSL distro, with ANY
# GitHub account that has org access - it never depends on a pre-existing local
# checkout. Clone/copy this dev-setup/ folder anywhere and run:
#   bash wsl-bootstrap.sh
# Safe to re-run - every step is idempotent.
set -euo pipefail

GITHUB_ORG="${GITHUB_ORG:-DistributedAvionics}"
GIT_PROTOCOL="${GIT_PROTOCOL:-ssh}"   # ssh | https
REPOS_DIR="${REPOS_DIR:-$HOME/repos}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# All repos are the same STM32F407 ChibiOS/Makefile shape. The Makefile
# PROJECT / build output name is the repo name minus the "AS-" prefix
# (AS-PDS -> build/PDS.elf), which is how the .vscode templates are filled in.
REPOS=(
    AS-ADS
    AS-PDS
    AS-VPS
    AS-DCU
    AS-BCU
    AS-AMU
    AS-AMU2
    AS-RFS
    AS-USM
    AS-UHMS2
    AS-OBS
)

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
    build-essential ccache git \
    gcc-arm-none-eabi libnewlib-arm-none-eabi libstdc++-arm-none-eabi-newlib \
    gdb-multiarch openocd stlink-tools dfu-util usbutils bear \
    libusb-1.0-0 unzip openssh-client

echo "==> Registering arm-none-eabi toolchain with ccache"
sudo ln -sf "$(command -v ccache)" /usr/lib/ccache/arm-none-eabi-gcc
sudo ln -sf "$(command -v ccache)" /usr/lib/ccache/arm-none-eabi-g++

echo "==> Adding $USER to the dialout group (serial/USB access)"
sudo usermod -a -G dialout "$USER"

# ---------------------------------------------------------------------------
# STM32CubeProgrammer (provides STM32_Programmer_CLI, used by the Flash task)
# ---------------------------------------------------------------------------
install_stm32cubeprogrammer() {
    echo "############################################################"
    echo "  STM32CubeProgrammer is required for the 'Flash' task."
    echo ""
    echo "  Download the Linux package from:"
    echo "    https://www.st.com/content/st_com/en/stm32cubeprogrammer.html?tab=installer#st-get-software"
    echo ""
    echo "  Once installed, press Enter to continue..."
    echo "############################################################"
    read -r
}
install_stm32cubeprogrammer

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
    echo "  USB passthrough (ST-Link) is done from WINDOWS, not WSL:"
    echo "  1. One-time per device, in an ELEVATED PowerShell:"
    echo "       usbipd list                 # find the BUSID"
    echo "       usbipd bind --busid <BUSID>"
    echo "  2. Every time you plug it in, from a normal PowerShell:"
    echo "       dev-setup\\attach-usb-to-wsl.ps1"
    echo "  3. Verify inside WSL with 'lsusb' (needs a NEW WSL terminal the"
    echo "     first time, for the usbutils package install to take effect)."
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
        git clone --recurse-submodules ${branch:+--branch "$branch"} "$(repo_url "$name")" "$REPOS_DIR/$name" \
            || echo "!!  Clone of $name failed - check SSH key / GitHub org access, then re-run this script."
    fi
}

for repo in "${REPOS[@]}"; do
    
    # TEMPORARY FOR MIGRATION: if branch "feat/MST-2201-WSL-Build" exists, use it
    if git ls-remote --heads "$(repo_url "$repo")" feat/MST-2201-WSL-Build | grep -q 'refs/heads/feat/MST-2201-WSL-Build'; then
        clone_repo "$repo" "feat/MST-2201-WSL-Build"
    else
        clone_repo "$repo"
    fi
    
done

# ---------------------------------------------------------------------------
# Deploy per-repo VS Code config (Build / Flash tasks + Debug launch).
# Uniform by default (vscode-templates/_template), with a per-repo override:
# if vscode-templates/<REPO>/ exists it wins, so a repo can diverge without
# touching the shared template. __REPO__/__NAME__ are substituted in.
# These are NEVER committed to the firmware repos - they go in each repo's
# local .git/info/exclude so they never show up in `git status`.
# ---------------------------------------------------------------------------
echo "==> Deploying per-repo VS Code Build/Flash/Debug config"
for repo in "${REPOS[@]}"; do
    [ -d "$REPOS_DIR/$repo/.git" ] || continue
    name="${repo#AS-}"
    src="$SCRIPT_DIR/vscode-templates/$repo"
    [ -d "$src" ] || src="$SCRIPT_DIR/vscode-templates/_template"
    dest="$REPOS_DIR/$repo/.vscode"
    mkdir -p "$dest"
    for f in "$src"/*.json; do
        sed -e "s/__REPO__/$repo/g" -e "s/__NAME__/$name/g" "$f" > "$dest/$(basename "$f")"
    done
    grep -qxF '.vscode/' "$REPOS_DIR/$repo/.git/info/exclude" 2>/dev/null || \
        echo '.vscode/' >> "$REPOS_DIR/$repo/.git/info/exclude"
done

for repo in "${REPOS[@]}"; do
    [ -d "$REPOS_DIR/$repo/.git" ] || continue
    echo "==> Ensuring submodules are up to date for $repo"
    ( cd "$REPOS_DIR/$repo" && GIT_SSH_COMMAND="ssh -o BatchMode=yes" git submodule update --init --recursive ) \
        || echo "!!  Submodule update failed for $repo - check SSH key / GitHub org access, then re-run this script."
done

echo "############################################################"
echo "  Done. Next steps:"
echo "  1. Open a NEW WSL terminal (for the dialout group to apply)."
echo "  2. Open a repo, e.g.:  code ~/repos/AS-PDS"
echo "     (each repo is standalone - no combined workspace file)."
echo "  3. Per repo: Ctrl+Shift+B to Build, run the 'Flash' task to"
echo "     program over ST-Link, or F5 to Debug (flashes + attaches)."
echo "     Attach the ST-Link to WSL first (dev-setup/attach-usb-to-wsl.ps1)."
echo "  See dev-setup/SETUP.md for the full guide."
echo "############################################################"

# Dev Environment Setup — AS-FCU, AS-AMU2 & AS-ADS

Target workflow: **VS Code + WSL2 (Ubuntu)**, native Linux toolchains for all
repos, with optional live hardware debugging over USB passthrough.

- **AS-FCU** — ArduPilot-derived flight control firmware (waf build). Builds
  `sitl` (native executable, no hardware) or `CubeOrange` (STM32H743, ARM
  cross-compile).
- **AS-AMU2** — ChibiOS actuator-node firmware (plain Makefile, STM32F407,
  ARM cross-compile).
- **AS-ADS** — ChibiOS air-data-node firmware (plain Makefile, STM32F407,
  ARM cross-compile).

This whole `dev-setup/` folder is **self-contained and portable** — it never
assumes a pre-existing local checkout or a specific machine/username. Copy or
git-clone it onto any machine, with any GitHub account that has
`DistributedAvionics` org access, and run the one script below. See
[§4](#4-distributing-this-to-other-machines) for how to hand it out to a team.

## 1. One-time setup (fewest steps)

1. Install the **WSL** extension in VS Code (`ms-vscode-remote.remote-wsl`) if
   not already installed.
2. Get `dev-setup/` onto the target machine (see §4) and, from a terminal in
   your WSL Ubuntu distro, run:
   ```bash
   bash dev-setup/wsl-bootstrap.sh
   ```
   This single script (idempotent, re-runnable, no hardcoded paths/usernames):
   - Installs all required packages: `gcc-arm-none-eabi`, `openocd`,
     `gdb-multiarch`, `dfu-util`, `stlink-tools`, `usbutils`, `bear`, build
     tools (one sudo password prompt).
   - Checks for **usbipd-win** on the Windows host and installs it via
     `winget` if missing (a Windows admin/UAC prompt may appear the first
     time — accept it). This is the tool that lets WSL see USB devices at
     all; see [§3](#3-hardware-debugging-st-link-cubeorange-amu2-ads-via-usb-passthrough).
   - Checks Windows' `.wslconfig` for WSL2 **mirrored networking mode**
     (`networkingMode=mirrored`) and enables it if not already set — needed
     for reliable USB passthrough / probe connectivity. If this gets changed,
     you'll be prompted to run `wsl --shutdown` from a **Windows** terminal
     and reopen WSL for it to take effect.
   - Generates an SSH key **for this machine** if one doesn't already exist,
     and prints the public key to add at https://github.com/settings/keys
     under whichever GitHub account will be used (needed once per machine,
     to fetch the private repos/submodules).
   - `git clone`s AS-FCU, AS-AMU2 and AS-ADS straight from GitHub into
     `~/repos` (native Linux filesystem, for build performance — WSL builds
     against `/mnt/c/...` are much slower), then initialises submodules.
   - Deploys the `.vscode/` tasks/launch/IntelliSense config from
     `dev-setup/vscode-templates/` into each cloned repo. **These are not
     committed to AS-FCU/AS-AMU2/AS-ADS** — the script also adds `.vscode/`
     to each repo's local `.git/info/exclude` so it never shows up in
     `git status` or diffs, and there is nothing to commit or push. See §3.
   - Creates a Python venv at `~/repos/.venv-ardupilot` with all SITL/waf
     Python dependencies.
3. Open the workspace: from a WSL terminal, `cd ~/repos && code avionics.code-workspace`
   (this launches VS Code in Remote-WSL mode automatically).

That's it — from here on, everything is driven from **Terminal ▸ Run Task**
(`Ctrl+Shift+P` → "Run Task") or `Ctrl+Shift+B` for the default build, and
`F5` for debugging.

Optional environment variables (set before running the script) if your setup
differs from the defaults:
| Variable | Default | Purpose |
|---|---|---|
| `GITHUB_ORG` | `DistributedAvionics` | GitHub org/user the repos live under |
| `GIT_PROTOCOL` | `ssh` | `ssh` or `https` — use `https` if you prefer a GitHub PAT/credential-manager login over SSH keys |
| `REPOS_DIR` | `$HOME/repos` | Where repos are cloned to |

Note: the AS-FCU `.vscode/tasks.json` locates the venv relative to the repo
(`${workspaceFolder}/../.venv-ardupilot`), so a custom `REPOS_DIR` is picked
up automatically without editing any templates.

## 2. Day-to-day tasks

All `AS-FCU` waf tasks automatically activate the `~/repos/.venv-ardupilot`
venv before running (`source .venv-ardupilot/bin/activate && python3 waf ...`)
— you never need to activate it yourself just to build/configure from VS
Code's Run Task/`Ctrl+Shift+B`.

### AS-FCU (SITL — no hardware needed)
| Task | What it does |
|---|---|
| `AS-FCU: Configure SITL` | `python3 waf configure --board sitl --debug` (run once, or after `distclean`) |
| `AS-FCU: Build SITL (plane)` | Default build (`Ctrl+Shift+B`) |
| `AS-FCU: Run SITL` | Runs `build/sitl/bin/FCU` directly |
| `F5` → *AS-FCU: Debug SITL (FCU)* | Builds + launches under `gdb` |

### AS-FCU (CubeOrange hardware)
`AS-FCU: Configure CubeOrange` → `AS-FCU: Build CubeOrange (plane)` →
`F5` → *AS-FCU: Debug CubeOrange (OpenOCD)* (see USB passthrough below).
`AS-FCU: Upload to CubeOrange` flashes over USB/bootloader without a debugger.

### AS-AMU2
`AS-AMU2: Init submodules` (first time only) → `Ctrl+Shift+B` (`AS-AMU2: Build`)
→ `F5` → *AS-AMU2: Debug (OpenOCD + ST-Link)*, or `AS-AMU2: Flash (dfu-util)`
if you just want to program it without debugging.

IntelliSense for AS-AMU2 needs a `compile_commands.json`; run task
`AS-AMU2: Generate compile_commands.json (bear)` once (and again after adding
new source files) — it's not produced by the Makefile automatically the way
waf produces one for AS-FCU.

### AS-ADS
`AS-ADS: Init submodules` (first time only) → `Ctrl+Shift+B` (`AS-ADS: Build`)
→ `F5` → *AS-ADS: Debug (OpenOCD + ST-Link)*, or `AS-ADS: Flash (dfu-util)`
if you just want to program it without debugging.

IntelliSense for AS-ADS needs a `compile_commands.json`; run task
`AS-ADS: Generate compile_commands.json (bear)` once (and again after adding
new source files) — same caveat as AS-AMU2, it's not produced by the
Makefile automatically.

## 3. Hardware debugging (ST-Link / CubeOrange / AMU2 / ADS) via USB passthrough

WSL2 doesn't see USB devices by default, so the debug probe (or board, when
flashing directly over its USB/DFU bootloader) has to be attached from
Windows using **usbipd-win**:

1. **One-time, on Windows:** `wsl-bootstrap.sh` installs `usbipd-win`
   automatically via `winget` (accept the UAC prompt if one appears). To do
   it manually instead, run in PowerShell:
   ```powershell
   winget install --id dorssel.usbipd-win -e --accept-source-agreements --accept-package-agreements
   ```
2. **One-time per device**, plug in the probe/board, then in an **elevated**
   PowerShell:
   ```powershell
   usbipd list                 # find the BUSID of your ST-Link/CMSIS-DAP/board
   usbipd bind --busid <BUSID>
   ```
3. **Every time you plug it in / start a session** (no elevation needed), run
   the helper script from a normal PowerShell window:
   ```powershell
   dev-setup\attach-usb-to-wsl.ps1
   ```
   This lists devices, matches common probe/board names (ST-Link, CMSIS-DAP,
   Black Magic, or a plain USB serial/virtual COM port) and attaches them to
   your WSL distro (`usbipd attach --busid <BUSID> --wsl=<Distro>` — v5+
   syntax). Verify inside WSL with `lsusb` (open a **new** WSL terminal the
   first time, so the `usbutils` package install takes effect).
4. Press `F5` in VS Code (Remote-WSL window) and pick the matching Cortex-Debug
   configuration, or run the `Flash (dfu-util)` task. OpenOCD +
   `arm-none-eabi-gdb`/`gdb-multiarch`/`dfu-util` run entirely inside WSL.

If `usbipd attach` reports the device is busy, unplug/replug it — Windows may
have re-claimed it with its default driver.

**Flashing over dfu-util specifically** requires the board to actually be in
its STM32 DFU bootloader (hold `BOOT0` while pressing/releasing reset) — a
board enumerated as a normal USB-serial/virtual COM port (`dfu-util -l`
returns nothing) is not in bootloader mode yet and can't be flashed.

## 4. Distributing this to other machines

Everything needed lives in this `dev-setup/` folder — it doesn't reference
AS-FCU/AS-AMU2/AS-ADS checkouts, usernames, or machine-specific paths. To
roll this out to a team on different machines/GitHub accounts:

- **Easiest:** zip this folder (or put it in a shared drive/USB stick) and
  copy it onto each machine, then run `bash dev-setup/wsl-bootstrap.sh`.
- **Recommended for ongoing maintenance:** push `dev-setup/` as its own small
  git repo (e.g. `DistributedAvionics/dev-setup`), so updates to tasks/launch
  configs or the bootstrap script reach everyone with a `git pull`. This repo
  is independent of AS-FCU/AS-AMU2/AS-ADS and doesn't require push access to
  any of them.
- Each machine/account still needs its **own SSH key** added to whichever
  GitHub account is used there (the script generates one per machine — keys
  are never shared between machines).
- If a machine's GitHub account prefers HTTPS + a personal access token over
  SSH, run `GIT_PROTOCOL=https bash dev-setup/wsl-bootstrap.sh` instead — git
  will prompt for credentials on first clone (use a credential helper, e.g.
  `git config --global credential.helper store`, to avoid retyping it).

## 5. Optional: Dev Container

A `.devcontainer/` is included at the workspace root for a fully reproducible,
disposable environment (Docker-based). It covers **SITL builds and IntelliSense
only** — USB passthrough for live hardware debugging is not set up for it, so
prefer the plain WSL setup above whenever you need to debug CubeOrange or
AMU2 hardware. Use "Dev Containers: Reopen in Container" from the command
palette if you want it.

## 6. Troubleshooting

- **`pip install` fails / package has no wheel for your Python version:**
  the bootstrap script's venv uses whatever `python3` resolves to system-wide.
  If that's very new (e.g. 3.13+) and a package like `MAVProxy`/`pymavlink`
  fails to build, install an older interpreter and recreate the venv:
  ```bash
  sudo apt-get install python3.12 python3.12-venv
  python3.12 -m venv ~/repos/.venv-ardupilot --clear
  source ~/repos/.venv-ardupilot/bin/activate && pip install -U pip
  # then re-run the pip install line from wsl-bootstrap.sh
  ```
- **Submodule update fails with "Permission denied (publickey)":** the SSH
  key printed by the bootstrap script hasn't been added to GitHub yet (or
  belongs to a personal account without access to the DistributedAvionics
  private repos). Add it, then re-run `wsl-bootstrap.sh`.
- **`waf` says "Missing waf submodule":** happens if `modules/waf` wasn't
  copied/initialised; re-run the bootstrap script or
  `git submodule update --init modules/waf` inside `AS-FCU`.
- **Serial ports / dfu-util "Cannot open device" without sudo:** log out/in
  (or open a new WSL terminal) so your user's new `dialout` group membership
  takes effect.

# Dev Environment Setup — DistributedAvionics STM32F407 firmware

Target workflow: **VS Code + WSL2 (Ubuntu)**, native Linux ARM toolchain, with
live hardware flashing/debugging over USB passthrough.

All repos are the **same shape**: ChibiOS + a plain `Makefile`, targeting an
**STM32F407** (Cortex-M4). So every repo builds, flashes and debugs identically:

| Repo | Build output (`build/…`) |
|---|---|
| AS-ADS | `ADS.elf` |
| AS-PDS | `PDS.elf` |
| AS-VPS | `VPS.elf` |
| AS-DCU | `DCU.elf` |
| AS-BCU | `BCU.elf` |
| AS-AMU | `AMU.elf` |
| AS-AMU2 | `AMU2.elf` |
| AS-RFS | `RFS.elf` |
| AS-USM | `USM.elf` |
| AS-UHMS2 | `UHMS2.elf` |
| AS-OBS | `OBS.elf` |

The build output name is just the repo name minus the `AS-` prefix.

Each repo is **fully standalone** — there is deliberately **no combined
`.code-workspace`**. You open each repo folder on its own and it carries its
own `.vscode/` config (deployed by the bootstrap, never committed to the repo).

This whole `dev-setup/` folder is **self-contained and portable** — it never
assumes a pre-existing local checkout or a specific machine/username. Copy or
git-clone it onto any machine, with any GitHub account that has
`DistributedAvionics` org access, and run the one script below. See
[§5](#5-distributing-this-to-other-machines) for how to hand it out to a team.

## 1. One-time setup (fewest steps)

1. Install the **WSL** extension in VS Code (`ms-vscode-remote.remote-wsl`) if
   not already installed.
2. Get `dev-setup/` onto the target machine (see §5) and, from a terminal in
   your WSL Ubuntu distro, run:
   ```bash
   bash dev-setup/wsl-bootstrap.sh
   ```
   This single script (idempotent, re-runnable, no hardcoded paths/usernames):
   - Installs the ARM toolchain and tools: `gcc-arm-none-eabi`,
     `libnewlib-arm-none-eabi`, `libstdc++-arm-none-eabi-newlib`,
     `gdb-multiarch`, `openocd`, `stlink-tools`, `dfu-util`, `usbutils`,
     `bear`, build tools (one sudo password prompt).
   - Installs **STM32CubeProgrammer** (provides `STM32_Programmer_CLI`, used by
     the Flash task) if it can find the bundle — see
     [§4](#4-stm32cubeprogrammer-the-flash-task).
   - Checks for **usbipd-win** on the Windows host and installs it via
     `winget` if missing (a Windows admin/UAC prompt may appear the first
     time — accept it). This is what lets WSL see USB devices; see
     [§3](#3-hardware-flashdebug-st-link-via-usb-passthrough).
   - Checks Windows' `.wslconfig` for WSL2 **mirrored networking mode**
     (`networkingMode=mirrored`) and enables it if not set — needed for
     reliable USB passthrough / probe connectivity. If it changes this,
     you'll be prompted to run `wsl --shutdown` from a **Windows** terminal
     and reopen WSL for it to take effect.
   - Generates an SSH key **for this machine** if one doesn't already exist,
     and prints the public key to add at https://github.com/settings/keys
     under whichever GitHub account will be used (needed once per machine, to
     fetch the private repos/submodules).
   - `git clone`s all 11 repos straight from GitHub into `~/repos` (native
     Linux filesystem, for build performance — WSL builds against
     `/mnt/c/...` are much slower), then initialises submodules.
   - Deploys each repo's `.vscode/` (Build + Flash tasks, Debug launch,
     IntelliSense) from `dev-setup/vscode-templates/`. **These are not
     committed to the firmware repos** — the script also adds `.vscode/` to
     each repo's local `.git/info/exclude` so it never shows up in
     `git status` or diffs.
3. Open a repo: from a WSL terminal, e.g. `code ~/repos/AS-PDS` (this launches
   VS Code in Remote-WSL mode automatically). Repeat for whichever repo you're
   working on — one window per repo.

That's it — from here on, everything is driven from `Ctrl+Shift+B` (Build),
**Terminal ▸ Run Task ▸ `<repo>: Flash`**, and `F5` (Debug).

Optional environment variables (set before running the script) if your setup
differs from the defaults:
| Variable | Default | Purpose |
|---|---|---|
| `GITHUB_ORG` | `DistributedAvionics` | GitHub org/user the repos live under |
| `GIT_PROTOCOL` | `ssh` | `ssh` or `https` — use `https` for a GitHub PAT/credential-manager login |
| `REPOS_DIR` | `$HOME/repos` | Where repos are cloned to |
| `STM32CUBEPROG_URL` | *(unset)* | Direct/mirror URL to the STM32CubeProgrammer Linux `.zip` (auto-download) |
| `STM32CUBEPROG_INSTALLER` | *(unset)* | Path to an already-downloaded STM32CubeProgrammer `.zip` or `SetupSTM32CubeProgrammer*.linux` |

## 2. The three per-repo actions

Every repo exposes the same three things (all names are prefixed with the repo,
e.g. `AS-PDS: Build`):

| Action | How | What it does |
|---|---|---|
| **Build** | `Ctrl+Shift+B` (default build task) | `bear -- make -j$(nproc)` → generates `build/<NAME>.{elf,bin,hex,dfu,dmp,list,map}` and refreshes `compile_commands.json` for IntelliSense |
| **Flash** | Run Task → `<repo>: Flash` | Builds, then `STM32_Programmer_CLI -c port=SWD mode=UR -d build/<NAME>.elf -rst` — programs the board over SWD/ST-Link and resets it |
| **Debug** | `F5` | Builds, then OpenOCD + ST-Link loads (flashes) the ELF and Cortex-Debug halts at `main`, giving you **variables, core registers and a memory viewer** |

Flash and Debug both need the ST-Link attached to WSL first (see §3). The Flash
task uses STM32CubeProgrammer; Debug uses OpenOCD — only one can own the ST-Link
at a time, but Build / Flash / Debug are separate actions so that's fine.

## 3. Hardware flash/debug (ST-Link) via USB passthrough

WSL2 doesn't see USB devices by default, so the ST-Link has to be attached from
Windows using **usbipd-win**:

1. **One-time, on Windows:** `wsl-bootstrap.sh` installs `usbipd-win`
   automatically via `winget` (accept the UAC prompt if one appears). To do it
   manually instead, run in PowerShell:
   ```powershell
   winget install --id dorssel.usbipd-win -e --accept-source-agreements --accept-package-agreements
   ```
2. **One-time per device**, plug in the ST-Link, then in an **elevated**
   PowerShell:
   ```powershell
   usbipd list                 # find the BUSID of your ST-Link
   usbipd bind --busid <BUSID>
   ```
3. **Every time you plug it in / start a session** (no elevation needed), run
   the helper from a normal PowerShell window:
   ```powershell
   dev-setup\attach-usb-to-wsl.ps1
   ```
   This lists devices, matches common probe names (ST-Link, CMSIS-DAP, etc.)
   and attaches them to your WSL distro. Verify inside WSL with `lsusb` (open a
   **new** WSL terminal the first time, so the `usbutils` install takes
   effect).
4. Then run the `Flash` task, or press `F5` to Debug. STM32CubeProgrammer /
   OpenOCD / `gdb-multiarch` all run entirely inside WSL.

If `usbipd attach` reports the device is busy, unplug/replug it — Windows may
have re-claimed it with its default driver.

## 4. STM32CubeProgrammer (the Flash task)

The `Flash` task uses `STM32_Programmer_CLI`, from ST's **STM32CubeProgrammer**.
ST gate the download behind a login form, so there is no stable public URL the
script can just `curl`. The bootstrap installs it automatically as soon as it
can get hold of the bundle, checked in this order:

1. `STM32_Programmer_CLI` already on `PATH` → nothing to do.
2. `STM32CUBEPROG_URL` set → downloads that `.zip` and silent-installs it.
3. `STM32CUBEPROG_INSTALLER` set → uses that local `.zip` or
   `SetupSTM32CubeProgrammer*.linux`.
4. A bundle dropped into `dev-setup/installers/` → uses it.
5. None of the above → prints instructions and continues (Build and Debug still
   work; only Flash is unavailable until it's installed).

To install it, grab the **Linux** package (login required) from
<https://www.st.com/en/development-tools/stm32cubeprog.html>, then either drop
the `.zip` in `dev-setup/installers/` and re-run the bootstrap, or:
```bash
STM32CUBEPROG_INSTALLER=~/Downloads/en.stm32cubeprg-lin_vX.Y.Z.zip bash dev-setup/wsl-bootstrap.sh
```
The script runs the installer unattended (`-q`), drops it in
`~/STM32CubeProgrammer`, symlinks `STM32_Programmer_CLI` into `/usr/local/bin`,
and installs ST's udev rules for non-root ST-Link access.

## 5. Distributing this to other machines

Everything needed lives in this `dev-setup/` folder — it doesn't reference any
repo checkout, username, or machine-specific path. To roll it out to a team on
different machines/GitHub accounts:

- **Easiest:** zip this folder (or put it on a shared drive/USB stick), copy it
  onto each machine, then run `bash dev-setup/wsl-bootstrap.sh`.
- **Recommended for ongoing maintenance:** push `dev-setup/` as its own small
  git repo (e.g. `DistributedAvionics/dev-setup`), so updates to the tasks/
  launch configs or bootstrap reach everyone with a `git pull`. It's
  independent of the firmware repos and needs no push access to them.
- Each machine/account still needs its **own SSH key** added to whichever
  GitHub account is used there (the script generates one per machine — keys are
  never shared).
- For an account that prefers HTTPS + a personal access token over SSH, run
  `GIT_PROTOCOL=https bash dev-setup/wsl-bootstrap.sh` (use a credential
  helper, e.g. `git config --global credential.helper store`, to avoid
  retyping it).

### Per-repo config overrides
By default every repo's `.vscode/` is generated from
`dev-setup/vscode-templates/_template/` (with `__REPO__`/`__NAME__` substituted
in). If a repo ever needs to diverge (e.g. a different chip or a custom task),
create `dev-setup/vscode-templates/<REPO>/` with the same JSON files — the
bootstrap uses it instead of `_template` for that repo, and still substitutes
`__REPO__`/`__NAME__`.

## 6. Troubleshooting

- **`STM32_Programmer_CLI: command not found` when flashing:**
  STM32CubeProgrammer isn't installed yet — see §4.
- **Submodule update / clone fails with "Permission denied (publickey)":** the
  SSH key printed by the bootstrap hasn't been added to GitHub yet (or belongs
  to an account without `DistributedAvionics` access). Add it, then re-run
  `wsl-bootstrap.sh`.
- **`STM32_Programmer_CLI`/OpenOCD "No ST-Link detected":** the probe isn't
  attached to WSL — re-run `dev-setup\attach-usb-to-wsl.ps1` from Windows and
  check `lsusb` inside WSL. If it says "busy", unplug/replug.
- **Serial / ST-Link "cannot open device" without sudo:** log out/in (or open a
  new WSL terminal) so your new `dialout` group membership takes effect.
- **Build fails on a file-name/`#include` case mismatch:** Linux is
  case-sensitive where Windows wasn't — fix the offending path/filename in the
  repo, rebuild to confirm, then commit that fix on a branch.

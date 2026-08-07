# Dev Environment Setup — DistributedAvionics STM32F407 firmware

Target workflow: **VS Code + Windows, natively** — no WSL, no USB
passthrough, no mirrored networking. The ARM toolchain, `make`, OpenOCD and
STM32CubeProgrammer all run as native Windows binaries, and the ST-Link is
just a normal USB device to Windows.

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

1. From a PowerShell terminal, run:
   ```powershell
   powershell -ExecutionPolicy Bypass -File dev-setup\windows-bootstrap.ps1
   ```
   This single script (idempotent, re-runnable, no hardcoded paths/usernames):
   - Installs **Git for Windows** and **Python** via `winget` if either is
     missing (Python is only needed for `compiledb`, used by the
     IntelliSense-refresh task).
   - Installs `compiledb` (`pip install --user compiledb`) — the Windows
     equivalent of `bear`, used to generate `compile_commands.json`.
   - Downloads and unpacks the standalone **xPack** Windows binaries for
     `arm-none-eabi-gcc` (includes `gdb`), GNU **make** (`windows-build-tools`)
     and **OpenOCD** straight from their GitHub Releases — no MSYS2, no
     Node/`xpm` needed — into `%USERPROFILE%\dev-tools\`, and adds each to
     your **User PATH**.
   - Checks for **STM32CubeProgrammer** (provides `STM32_Programmer_CLI`, used
     by the Flash task) in its default install location and adds it to PATH —
     see [§4](#4-stm32cubeprogrammer-the-flash-task) if it's missing.
   - Generates an SSH key **for this machine** if one doesn't already exist
     (using Windows' built-in OpenSSH client), and prints the public key to
     add at https://github.com/settings/keys under whichever GitHub account
     will be used (needed once per machine, to fetch the private
     repos/submodules).
   - `git clone`s all 11 repos straight from GitHub into `%USERPROFILE%\repos`,
     then initialises submodules.
   - Deploys each repo's `.vscode/` (Build + Flash tasks, Debug launch,
     IntelliSense) from `dev-setup/vscode-templates/`, substituting in the
     tool paths it discovered. **These are not committed to the firmware
     repos** — the script also adds `.vscode/` to each repo's local
     `.git/info/exclude` so it never shows up in `git status` or diffs.
2. Open a repo, e.g. `code %USERPROFILE%\repos\AS-PDS`. Repeat for whichever
   repo you're working on — one window per repo. The Build/Flash/Debug tasks
   and IntelliSense config have the discovered tool paths baked in directly,
   so they work immediately — no need to reopen a terminal for the PATH
   change to propagate (that's only needed if you want to run `make`,
   `arm-none-eabi-gcc`, etc. by hand from an arbitrary shell).

That's it — from here on, everything is driven from `Ctrl+Shift+B` (Build),
**Terminal ▸ Run Task ▸ `<repo>: Flash`**, and `F5` (Debug).

Optional environment variables (set before running the script) if your setup
differs from the defaults:
| Variable | Default | Purpose |
|---|---|---|
| `GITHUB_ORG` | `DistributedAvionics` | GitHub org/user the repos live under |
| `GIT_PROTOCOL` | `ssh` | `ssh` or `https` — use `https` for a GitHub PAT/credential-manager login |
| `REPOS_DIR` | `%USERPROFILE%\repos` | Where repos are cloned to |
| `TOOLS_DIR` | `%USERPROFILE%\dev-tools` | Where the xPack ARM GCC/make/OpenOCD binaries are unpacked |

## 2. The three per-repo actions

Every repo exposes the same three things (all names are prefixed with the repo,
e.g. `AS-PDS: Build`):

| Action | How | What it does |
|---|---|---|
| **Build** | `Ctrl+Shift+B` (default build task) | `make -j<nproc>` → generates `build/<NAME>.{elf,bin,hex,dfu,dmp,list,map}` |
| **Flash** | Run Task → `<repo>: Flash` | Builds, then `STM32_Programmer_CLI -c port=SWD mode=UR -d build/<NAME>.elf -rst` — programs the board over SWD/ST-Link and resets it |
| **Debug** | `F5` | Builds, then OpenOCD + ST-Link loads (flashes) the ELF and Cortex-Debug halts at `main`, giving you **variables, core registers and a memory viewer** |

There's also a `<repo>: Generate compile_commands.json (compiledb)` task to
refresh IntelliSense after adding/removing source files. Flash and Debug just
need the ST-Link plugged into this PC — Windows sees it directly, no
passthrough step. The Flash task uses STM32CubeProgrammer; Debug uses OpenOCD
— only one can own the ST-Link at a time, but Build / Flash / Debug are
separate actions so that's fine.

## 3. Hardware flash/debug (ST-Link)

Nothing special — plug the ST-Link into this PC via USB and it's visible to
Windows immediately (Device Manager should show it, e.g. under "Universal
Serial Bus devices" or "STMicroelectronics STLink dongles"). Then run the
`Flash` task, or press `F5` to Debug. STM32CubeProgrammer / OpenOCD /
`arm-none-eabi-gdb` all run entirely natively on Windows.

If flashing/debugging reports "No ST-Link detected", check Device Manager for
a driver problem, or unplug/replug the probe.

## 4. STM32CubeProgrammer (the Flash task)

The `Flash` task uses `STM32_Programmer_CLI`, from ST's **STM32CubeProgrammer**.
ST gate the download behind a login form, so there is no stable public URL the
script can just download automatically. The bootstrap looks for it in its
default install location (`%ProgramFiles%\STMicroelectronics\STM32Cube\STM32CubeProgrammer`)
and adds it to PATH if found; otherwise it prints instructions and continues
(Build and Debug still work; only Flash is unavailable until it's installed).

To install it, grab the **Windows** package (login required) from
<https://www.st.com/en/development-tools/stm32cubeprog.html>, run the
installer, then re-run `windows-bootstrap.ps1` to pick it up automatically.

## 5. Distributing this to other machines

Everything needed lives in this `dev-setup/` folder — it doesn't reference any
repo checkout, username, or machine-specific path. To roll it out to a team on
different machines/GitHub accounts:

- **Easiest:** zip this folder (or put it on a shared drive/USB stick), copy it
  onto each machine, then run `powershell -ExecutionPolicy Bypass -File dev-setup\windows-bootstrap.ps1`.
- **Recommended for ongoing maintenance:** push `dev-setup/` as its own small
  git repo (e.g. `DistributedAvionics/dev-setup`), so updates to the tasks/
  launch configs or bootstrap reach everyone with a `git pull`. It's
  independent of the firmware repos and needs no push access to them.
- Each machine/account still needs its **own SSH key** added to whichever
  GitHub account is used there (the script generates one per machine — keys are
  never shared).
- For an account that prefers HTTPS + a personal access token over SSH, run
  ```powershell
  $env:GIT_PROTOCOL = "https"; powershell -ExecutionPolicy Bypass -File dev-setup\windows-bootstrap.ps1
  ```
  (use `git config --global credential.helper manager` to avoid retyping it).

### Per-repo config overrides
By default every repo's `.vscode/` is generated from
`dev-setup/vscode-templates/_template/` (with `__REPO__`/`__NAME__` and the
discovered tool paths substituted in). If a repo ever needs to diverge (e.g. a
different chip or a custom task), create `dev-setup/vscode-templates/<REPO>/`
with the same JSON files — the bootstrap uses it instead of `_template` for
that repo, and still substitutes everything in.

## 6. Troubleshooting

- **`make`/`arm-none-eabi-gcc`/`openocd`/`STM32_Programmer_CLI` not found
  when running a task:** the `.vscode/` in that repo was deployed before a
  tool was installed, or by an older version of the bootstrap. Re-run
  `windows-bootstrap.ps1` — it redeploys `.vscode/` with the current tool
  paths every time, even for already-cloned repos, then reopen the repo's VS
  Code window.
- **`STM32_Programmer_CLI: command not found` when flashing:**
  STM32CubeProgrammer isn't installed yet — see §4.
- **Submodule update / clone fails with "Permission denied (publickey)":** the
  SSH key printed by the bootstrap hasn't been added to GitHub yet (or belongs
  to an account without `DistributedAvionics` access). Add it, then re-run
  `windows-bootstrap.ps1`.
- **Debug can't find `interface/stlink.cfg` / `target/stm32f4x.cfg`:** re-run
  `windows-bootstrap.ps1` to redeploy `launch.json`/`settings.json` with the
  current `OPENOCD_SCRIPTS`/tool paths baked in.
- **`STM32_Programmer_CLI`/OpenOCD "No ST-Link detected":** check Device
  Manager for a driver issue, or unplug/replug the probe.

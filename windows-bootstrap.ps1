#!/usr/bin/env pwsh
<#
.SYNOPSIS
    One-shot dev-environment bootstrap for the DistributedAvionics STM32F407
    ChibiOS firmware repos (AS-ADS, AS-PDS, AS-VPS, AS-DCU, AS-BCU, AS-AMU,
    AS-AMU2, AS-RFS, AS-USM, AS-UHMS2, AS-OBS) - running NATIVELY on Windows.

    Every repo builds the same way (plain Makefile + ChibiOS), flashes the
    same way (STM32_Programmer_CLI over SWD/ST-Link) and debugs the same way
    (OpenOCD + Cortex-Debug). Each repo stays fully self-contained: it gets
    its own .vscode/ (Build / Flash tasks + Debug launch), and there is NO
    combined VS Code workspace file - open each repo folder on its own.

    No WSL, no usbipd, no mirrored networking: arm-none-eabi-gcc, make,
    OpenOCD and STM32CubeProgrammer all run as native Windows binaries and
    see the ST-Link over USB directly.

    Designed to be fully portable: run this on ANY Windows machine, with ANY
    GitHub account that has org access - it never depends on a pre-existing
    local checkout. Copy this dev-setup/ folder anywhere and run:
        powershell -ExecutionPolicy Bypass -File windows-bootstrap.ps1
    Safe to re-run - every step is idempotent.
#>

[CmdletBinding()]
param(
    [string]$GitHubOrg = $(if ($env:GITHUB_ORG) { $env:GITHUB_ORG } else { "DistributedAvionics" }),
    [ValidateSet("ssh", "https")]
    [string]$GitProtocol = $(if ($env:GIT_PROTOCOL) { $env:GIT_PROTOCOL } else { "ssh" }),
    [string]$ReposDir = $(if ($env:REPOS_DIR) { $env:REPOS_DIR } else { "$HOME\repos" }),
    [string]$ToolsDir = $(if ($env:TOOLS_DIR) { $env:TOOLS_DIR } else { "$HOME\dev-tools" })
)

$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

# All repos are the same STM32F407 ChibiOS/Makefile shape. The Makefile
# PROJECT / build output name is the repo name minus the "AS-" prefix
# (AS-PDS -> build/PDS.elf), which is how the .vscode templates are filled in.
$Repos = @(
    "AS-ADS", "AS-PDS", "AS-VPS", "AS-DCU", "AS-BCU", "AS-AMU",
    "AS-AMU2", "AS-RFS", "AS-USM", "AS-UHMS2", "AS-OBS"
)

function Repo-Url([string]$Name) {
    if ($GitProtocol -eq "https") { return "https://github.com/$GitHubOrg/$Name.git" }
    return "git@github.com:$GitHubOrg/$Name.git"
}

function Test-CommandExists([string]$Name) {
    return [bool](Get-Command $Name -ErrorAction SilentlyContinue)
}

function Refresh-Path {
    $machine = [Environment]::GetEnvironmentVariable("Path", "Machine")
    $user = [Environment]::GetEnvironmentVariable("Path", "User")
    $env:Path = "$machine;$user"
}

function Add-UserPath([string]$Dir) {
    if (-not $Dir) { return }
    $current = [Environment]::GetEnvironmentVariable("Path", "User")
    $parts = @()
    if ($current) { $parts = $current -split ";" }
    if ($parts -notcontains $Dir) {
        [Environment]::SetEnvironmentVariable("Path", "$current;$Dir", "User")
    }
    if (($env:Path -split ";") -notcontains $Dir) { $env:Path = "$env:Path;$Dir" }
}

function Set-UserEnv([string]$Name, [string]$Value) {
    if (-not $Value) { return }
    [Environment]::SetEnvironmentVariable($Name, $Value, "User")
    Set-Item -Path "Env:$Name" -Value $Value
}

function Json-Path([string]$Path) {
    if (-not $Path) { return "" }
    return ($Path -replace '\\', '/')
}

# ---------------------------------------------------------------------------
# Prerequisites: git, python (for compiledb), winget for anything missing
# ---------------------------------------------------------------------------
Write-Host "==> Checking prerequisites (git, python)"
$hasWinget = Test-CommandExists "winget"

if (-not (Test-CommandExists "git")) {
    if ($hasWinget) {
        Write-Host "==> Installing Git for Windows"
        winget install --id Git.Git -e --accept-source-agreements --accept-package-agreements
        Refresh-Path
    } else {
        Write-Warning "git not found and winget is unavailable - install it manually: https://git-scm.com/download/win"
    }
}

if (-not (Test-CommandExists "python") -and -not (Test-CommandExists "py")) {
    if ($hasWinget) {
        Write-Host "==> Installing Python (needed for compiledb, used by the IntelliSense-refresh task)"
        winget install --id Python.Python.3.12 -e --accept-source-agreements --accept-package-agreements
        Refresh-Path
    } else {
        Write-Warning "python not found and winget is unavailable - install it manually: https://www.python.org/downloads/"
    }
}

$pyScriptsBin = $null
if (Test-CommandExists "python" -or (Test-CommandExists "py")) {
    Write-Host "==> Installing compiledb (make -> compile_commands.json for IntelliSense)"
    $pyExe = if (Test-CommandExists "python") { "python" } else { "py" }
    & $pyExe -m pip install --user --upgrade compiledb --quiet
    try {
        $userBase = (& $pyExe -m site --user-base).Trim()
        $pyScriptsBin = Join-Path $userBase "Scripts"
        Add-UserPath $pyScriptsBin
    } catch {
        Write-Warning "Could not determine Python user Scripts dir - add it to PATH manually if 'compiledb' isn't found."
    }
} else {
    Write-Warning "compiledb could not be installed (no python) - the 'Generate compile_commands.json' task will fail."
}

# ---------------------------------------------------------------------------
# ARM toolchain, make and OpenOCD: standalone xPack binaries straight from
# GitHub Releases (no MSYS2, no Node/xpm - just download + unzip).
# ---------------------------------------------------------------------------
function Install-XPackRelease {
    param(
        [string]$RepoSlug,
        [string]$Name,
        [string]$VerifyExe
    )

    Write-Host "==> Checking $Name"
    $destDir = Join-Path $ToolsDir $Name
    $versionFile = Join-Path $destDir ".xpack-release"

    try {
        $release = Invoke-RestMethod -Uri "https://api.github.com/repos/$RepoSlug/releases/latest" -Headers @{ "User-Agent" = "windows-bootstrap" }
    } catch {
        Write-Warning "Could not reach GitHub to check $Name releases - $_"
        $exe = if (Test-Path $destDir) { Get-ChildItem -Path $destDir -Filter $VerifyExe -Recurse | Select-Object -First 1 } else { $null }
        return $(if ($exe) { $exe.DirectoryName } else { $null })
    }

    $tag = $release.tag_name
    $asset = $release.assets | Where-Object { $_.name -like "*-win32-x64.zip" -and $_.name -notlike "*.sha" } | Select-Object -First 1
    if (-not $asset) {
        Write-Warning "No win32-x64 release asset found for $RepoSlug - install $Name manually."
        return $null
    }

    $upToDate = (Test-Path $versionFile) -and ((Get-Content $versionFile -Raw).Trim() -eq $tag)
    if ($upToDate) {
        Write-Host "    $Name $tag already installed"
    } else {
        Write-Host "    downloading $($asset.name) ($tag)"
        $zipPath = Join-Path $env:TEMP $asset.name
        Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $zipPath
        if (Test-Path $destDir) { Remove-Item $destDir -Recurse -Force }
        New-Item -ItemType Directory -Path $destDir -Force | Out-Null
        Expand-Archive -Path $zipPath -DestinationPath $destDir -Force
        Remove-Item $zipPath -Force
        Set-Content -Path $versionFile -Value $tag
    }

    $exe = Get-ChildItem -Path $destDir -Filter $VerifyExe -Recurse | Select-Object -First 1
    if (-not $exe) {
        Write-Warning "$VerifyExe not found after extracting $Name - check $destDir"
        return $null
    }
    return $exe.DirectoryName
}

$armGccBin = Install-XPackRelease -RepoSlug "xpack-dev-tools/arm-none-eabi-gcc-xpack" -Name "arm-none-eabi-gcc" -VerifyExe "arm-none-eabi-gcc.exe"
$makeBin = Install-XPackRelease -RepoSlug "xpack-dev-tools/windows-build-tools-xpack" -Name "windows-build-tools" -VerifyExe "make.exe"
$openocdBin = Install-XPackRelease -RepoSlug "xpack-dev-tools/openocd-xpack" -Name "openocd" -VerifyExe "openocd.exe"

Add-UserPath $armGccBin
Add-UserPath $makeBin
Add-UserPath $openocdBin

# OpenOCD needs its bundled scripts/ dir (interface/stlink.cfg, target/stm32f4x.cfg)
# - find it next to whatever bin/ the zip actually unpacked into rather than
# assuming a fixed layout, and expose it as OPENOCD_SCRIPTS.
$openocdScripts = $null
if ($openocdBin) {
    $openocdRoot = Split-Path $openocdBin -Parent
    $stlinkCfg = Get-ChildItem -Path $openocdRoot -Filter "stlink.cfg" -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($stlinkCfg) {
        $openocdScripts = Split-Path (Split-Path $stlinkCfg.FullName -Parent) -Parent
    } else {
        Write-Warning "Could not locate OpenOCD's scripts/ folder under $openocdRoot - Debug may fail to find interface/target configs."
    }
}

if ($armGccBin) { Set-UserEnv -Name "ARM_GCC_BIN" -Value $armGccBin }
if ($openocdBin) { Set-UserEnv -Name "OPENOCD_BIN" -Value $openocdBin }
if ($openocdScripts) { Set-UserEnv -Name "OPENOCD_SCRIPTS" -Value $openocdScripts }

# ---------------------------------------------------------------------------
# STM32CubeProgrammer (provides STM32_Programmer_CLI, used by the Flash task).
# ST gates the Windows installer behind a login form too, so this can only
# detect an existing install and prompt if it's missing - same as before.
# ---------------------------------------------------------------------------
function Find-STM32ProgrammerBin {
    $candidates = @(
        "$env:ProgramFiles\STMicroelectronics\STM32Cube\STM32CubeProgrammer\bin",
        "${env:ProgramFiles(x86)}\STMicroelectronics\STM32Cube\STM32CubeProgrammer\bin"
    )
    foreach ($c in $candidates) {
        if (Test-Path (Join-Path $c "STM32_Programmer_CLI.exe")) { return $c }
    }
    $roots = @($env:ProgramFiles, "${env:ProgramFiles(x86)}") | Where-Object { $_ }
    $found = Get-ChildItem -Path $roots -Filter "STM32_Programmer_CLI.exe" -Recurse -Depth 6 -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($found) { return $found.DirectoryName }
    return $null
}

Write-Host "==> Checking for STM32CubeProgrammer"
$stm32ProgBin = Find-STM32ProgrammerBin
if ($stm32ProgBin) {
    Write-Host "    found: $stm32ProgBin"
    Add-UserPath $stm32ProgBin
} else {
    Write-Host "############################################################"
    Write-Host "  STM32CubeProgrammer is required for the 'Flash' task."
    Write-Host ""
    Write-Host "  Download the Windows installer (login required) from:"
    Write-Host "    https://www.st.com/en/development-tools/stm32cubeprog.html"
    Write-Host ""
    Write-Host "  Once installed, re-run this script to pick it up (Build and"
    Write-Host "  Debug work fine in the meantime; only Flash is unavailable)."
    Write-Host "############################################################"
}

# ---------------------------------------------------------------------------
# SSH key for GitHub access (Windows ships an OpenSSH client by default).
# ---------------------------------------------------------------------------
if (-not (Test-CommandExists "ssh-keygen")) {
    Write-Warning "ssh-keygen not found. Enable it via Settings > Optional Features > OpenSSH Client, then re-run this script."
} else {
    Write-Host "==> Ensuring an SSH key exists for GitHub access"
    $sshDir = Join-Path $HOME ".ssh"
    $keyPath = Join-Path $sshDir "id_ed25519"
    if (-not (Test-Path $keyPath)) {
        New-Item -ItemType Directory -Path $sshDir -Force | Out-Null
        ssh-keygen -t ed25519 -N '""' -f $keyPath -C "$env:USERNAME@$env:COMPUTERNAME"
        Write-Host "############################################################"
        Write-Host "  New SSH key generated on THIS machine. Add this PUBLIC key"
        Write-Host "  to the GitHub account that has $GitHubOrg org access:"
        Write-Host "  https://github.com/settings/keys"
        Write-Host "############################################################"
        Get-Content "$keyPath.pub"
        Write-Host "############################################################"
        Read-Host "Press Enter once the key has been added to GitHub"
    }
    $knownHosts = Join-Path $sshDir "known_hosts"
    if (-not (Test-Path $knownHosts)) { New-Item -ItemType File -Path $knownHosts -Force | Out-Null }
    if (Test-CommandExists "ssh-keyscan") {
        ssh-keyscan -H github.com 2>$null | Add-Content -Path $knownHosts
    }
}

New-Item -ItemType Directory -Path $ReposDir -Force | Out-Null

function Clone-Repo {
    param([string]$Name, [string]$Branch)
    $dest = Join-Path $ReposDir $Name
    if (Test-Path (Join-Path $dest ".git")) {
        Write-Host "==> $Name already present in $ReposDir, skipping clone"
        return
    }
    Write-Host "==> Cloning $Name from GitHub ($GitProtocol)$(if ($Branch) { " [branch: $Branch]" })"
    $args = @("clone", "--recurse-submodules")
    if ($Branch) { $args += @("--branch", $Branch) }
    $args += @((Repo-Url $Name), $dest)
    git @args
    if ($LASTEXITCODE -ne 0) {
        Write-Warning "Clone of $Name failed - check SSH key / GitHub org access, then re-run this script."
    }
}

foreach ($repo in $Repos) {
    # TEMPORARY FOR MIGRATION: if branch "feat/MST-2201-WSL-Build" exists, use it
    $branchRef = git ls-remote --heads (Repo-Url $repo) feat/MST-2201-WSL-Build 2>$null
    if ($branchRef -match "refs/heads/feat/MST-2201-WSL-Build") {
        Clone-Repo -Name $repo -Branch "feat/MST-2201-WSL-Build"
    } else {
        Clone-Repo -Name $repo
    }
}

# ---------------------------------------------------------------------------
# Deploy per-repo VS Code config (Build / Flash tasks + Debug launch).
# Uniform by default (vscode-templates/_template), with a per-repo override:
# if vscode-templates/<REPO>/ exists it wins, so a repo can diverge without
# touching the shared template. __REPO__/__NAME__ and the discovered tool
# paths are substituted in. These are NEVER committed to the firmware repos -
# they go in each repo's local .git/info/exclude so they never show up in
# `git status`.
# ---------------------------------------------------------------------------
Write-Host "==> Deploying per-repo VS Code Build/Flash/Debug config"
foreach ($repo in $Repos) {
    $repoDir = Join-Path $ReposDir $repo
    if (-not (Test-Path (Join-Path $repoDir ".git"))) { continue }

    $name = $repo -replace "^AS-", ""
    $srcDir = Join-Path $ScriptDir "vscode-templates\$repo"
    if (-not (Test-Path $srcDir)) { $srcDir = Join-Path $ScriptDir "vscode-templates\_template" }
    $destDir = Join-Path $repoDir ".vscode"
    New-Item -ItemType Directory -Path $destDir -Force | Out-Null

    Get-ChildItem -Path $srcDir -Filter "*.json" | ForEach-Object {
        (Get-Content $_.FullName -Raw) `
            -replace "__REPO__", $repo `
            -replace "__NAME__", $name `
            -replace "__ARM_GCC_BIN__", (Json-Path $armGccBin) `
            -replace "__MAKE_BIN__", (Json-Path $makeBin) `
            -replace "__OPENOCD_BIN__", (Json-Path $openocdBin) `
            -replace "__OPENOCD_SCRIPTS__", (Json-Path $openocdScripts) `
            -replace "__STM32PROG_BIN__", (Json-Path $stm32ProgBin) `
            -replace "__PY_SCRIPTS__", (Json-Path $pyScriptsBin) |
            Set-Content -Path (Join-Path $destDir $_.Name) -Encoding UTF8
    }

    $excludeFile = Join-Path $repoDir ".git\info\exclude"
    if (-not (Select-String -Path $excludeFile -Pattern "^\.vscode/$" -Quiet -ErrorAction SilentlyContinue)) {
        Add-Content -Path $excludeFile -Value ".vscode/"
    }
}

foreach ($repo in $Repos) {
    $repoDir = Join-Path $ReposDir $repo
    if (-not (Test-Path (Join-Path $repoDir ".git"))) { continue }
    Write-Host "==> Ensuring submodules are up to date for $repo"
    Push-Location $repoDir
    git submodule update --init --recursive
    if ($LASTEXITCODE -ne 0) {
        Write-Warning "Submodule update failed for $repo - check SSH key / GitHub org access, then re-run this script."
    }
    Pop-Location
}

Write-Host "############################################################"
Write-Host "  Done. Next steps:"
Write-Host "  1. Open a NEW terminal/VS Code window (so the updated PATH"
Write-Host "     and environment variables take effect)."
Write-Host "  2. Open a repo, e.g.:  code $ReposDir\AS-PDS"
Write-Host "     (each repo is standalone - no combined workspace file)."
Write-Host "  3. Per repo: Ctrl+Shift+B to Build, run the 'Flash' task to"
Write-Host "     program over ST-Link, or F5 to Debug (flashes + attaches)."
Write-Host "     Just plug the ST-Link into this PC - no USB passthrough"
Write-Host "     step needed."
Write-Host "  See dev-setup/SETUP.md for the full guide."
Write-Host "############################################################"

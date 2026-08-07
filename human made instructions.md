open a folder and copy/clone this repo
open a PowerShell terminal, `powershell -ExecutionPolicy Bypass -File dev-setup\windows-bootstrap.ps1`
let it cook (installs git/python via winget if missing, downloads the ARM
toolchain/make/OpenOCD as standalone xPack binaries, no admin needed for those)
copy ssh key into github settings > ssh and GPG keys
hit enter, let it cook

for flashing u can use dfuse, this setup uses stmcubeprogrammer to flash .elf for debugging
https://www.st.com/content/st_com/en/stm32cubeprogrammer.html?tab=installer#st-get-software
grab the Windows installer (login required), run it, then re-run
windows-bootstrap.ps1 so it finds STM32_Programmer_CLI and adds it to PATH


no WSL, no usbipd, no USB binding needed anymore - the ST-Link is just a
normal USB device to Windows. Plug it in and it's ready.


open a new vscode window in the repo youre working with 
it should be setup for 
    building with ctrl+shift+B or terminal > run task > build
    flashing with terminal > run task > flash (can set a keybind if u want one)
    debugging with f5


trouble shooting
you might need to change the submodule links to ssh
if a build fails on an #include / filename case mismatch, fix it in the repo,
rebuild, then commit on new branch "feat/MST2201-WSL-Build"
    the setup will pull this branch if it exists, or it will pull main if not.
    this is left over from the WSL transition and still supported
when flashing use device manager to ensure the device is in bootloader mode
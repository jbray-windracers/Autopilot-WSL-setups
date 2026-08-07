install wsl
>< connect with distro
+ new distro
Ubuntu 26.04
create login (remember password)
    its useful to map a network drive to wsl for file access on windows side
open a folder and copy/cone this repo
new terminal, `bash dev-setup/wsl-bootstrap.sh`
type password
let it cook
copy ssh key into github settings > ssh and GPG keys
hit enter, let it cook

for flashing u can use dfuse, this setup uses stmcubeprogrammer to flash .elf for debugging
https://www.st.com/content/st_com/en/stm32cubeprogrammer.html?tab=installer#st-get-software
drop the STM32CubeProgrammer linux .zip in dev-setup/installer

open a new vscode window in the repo youre working with 
it should be setup for 
    building with ctrl+shift+B or terminal > run task > build
    flashing with terminal > run task > build (can set a keybind if u want one)
    debugging with f5


trouble shooting
you might need to change the submodule links to ssh
Linux is case-sensitive: if a build fails on an #include / filename case
mismatch, fix it in the repo, rebuild, then commit on new branch "feat/MST2201-WSL-Build"
    the setup will pull this branch if it exists, or it will pull main if not.
    this is to support transistion to wsl and VS code
when flashing use device manager to ensure the device is in bootloader mode
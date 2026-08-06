install wsl
>< connect with distro
+ new distro
Ubuntu 26.04
create login (remember password)
open a folder and copy dev-setup
new terminal, `bash dev-setup/wsl-bootstrap.sh`
type password
let it cook
copy ssh key into GitHub settings > ssh and GPG keys
hit enter, let it cook
(for flashing: drop the STM32CubeProgrammer linux .zip in dev-setup/installers/
 first, or set STM32CUBEPROG_INSTALLER=/path/to/zip - see SETUP.md §4)

per repo (one VS Code window each):
`code ~/repos/AS-PDS`   (or AS-ADS, AS-VPS, AS-DCU, AS-BCU, AS-AMU, AS-AMU2,
                         AS-RFS, AS-USM, AS-UHMS2, AS-OBS)
Ctrl+Shift+B            -> build
Run Task > <repo>: Flash -> flash over ST-Link
F5                     -> debug (variables, registers, memory)

attach the ST-Link to WSL first, from Windows PowerShell:
`dev-setup\attach-usb-to-wsl.ps1`

trouble shooting
you might need to change the submodule links to ssh
Linux is case-sensitive: if a build fails on an #include / filename case
mismatch, fix it in the repo, rebuild, then commit on a branch

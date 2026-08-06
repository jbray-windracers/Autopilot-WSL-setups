# STM32CubeProgrammer installer drop-in

`wsl-bootstrap.sh` needs `STM32_Programmer_CLI` (from ST's STM32CubeProgrammer)
for the per-repo **Flash** task. ST gate the download behind a login form, so it
can't be fetched automatically without a URL.

To have the bootstrap install it for you, download the **Linux** package from
<https://www.st.com/en/development-tools/stm32cubeprog.html> and drop the `.zip`
here (e.g. `en.stm32cubeprg-lin_vX.Y.Z.zip`), then re-run
`bash dev-setup/wsl-bootstrap.sh`.

Alternatives (see SETUP.md §4):
- `STM32CUBEPROG_INSTALLER=/path/to/en.stm32cubeprg-lin*.zip bash dev-setup/wsl-bootstrap.sh`
- `STM32CUBEPROG_URL=<direct-or-mirror-url> bash dev-setup/wsl-bootstrap.sh`

Do **not** commit the ST bundle to git — it's large and licensed by ST.

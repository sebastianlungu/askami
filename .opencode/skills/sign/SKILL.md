---
name: sign
description: Build, stable-sign, install, and relaunch Askami. Use when the user says /sign, rebuild app, sign the app, build and sign, reinstall Askami, or after changing macOS app code.
---

# Sign Askami

Never ad-hoc sign an installed Askami build. Use the stable `Askami Dev` identity so macOS TCC permissions survive rebuilds.

## Workflow

1. Run from the repository root:

   ```bash
   bash scripts/install.sh
   ```

2. Launch the installed build:

   ```bash
    open /Applications/askami.app
   ```

3. Verify `codesign -dv --verbose=4 /Applications/askami.app` reports `Authority=Askami Dev`, then confirm the menu-bar status reaches `listening`.

4. Report build, installation, signature, and runtime status. If the installer reports an identity migration, tell the user to approve Microphone and Screen & System Audio Recording once and relaunch the app.

Do not reset TCC manually when the installed app already uses the expected identity. `scripts/install.sh` detects that condition.

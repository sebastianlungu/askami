---
name: sign
description: Build, stable-sign, install, and relaunch JustASec. Use when the user says /sign, rebuild app, sign the app, build and sign, reinstall JustASec, or after changing macOS app code.
---

# Sign JustASec

Never ad-hoc sign an installed JustASec build. Use the stable `JustASec Dev` identity so macOS TCC permissions survive rebuilds.

## Workflow

1. Run from the repository root:

   ```bash
   bash scripts/install.sh
   ```

2. Launch the installed build:

   ```bash
   open /Applications/justasec.app
   ```

3. Verify `codesign -dv --verbose=4 /Applications/justasec.app` reports `Authority=JustASec Dev`, then confirm the menu-bar status reaches `listening`.

4. Report build, installation, signature, and runtime status. If the installer reports an identity migration, tell the user to approve Microphone and Screen & System Audio Recording once and relaunch the app.

Do not reset TCC manually when the installed app already uses the expected identity. `scripts/install.sh` detects that condition.

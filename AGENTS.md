# AGENTS.md — dlwatch requirements log

## Initial requirements
- Swift app compilable with `swiftc` only (no SPM, no Xcode)
- `build.sh` at repo root: compile + pack as `.app` bundle, bundle ID `dev.abdus.dlwatch`
- Menu bar app (LSUIElement, hides from Dock)
- Runs aria2c in daemon mode, communicates via JSON-RPC
- Shows active and completed downloads in menu
- Actions: add, pause/resume, restart downloads
- Folder icon next to finished downloads; click reveals file in Finder
- Binary also works as a CLI: same flags as aria2c (usable subset), easy migration
- Do not assume port 6800; pick a random free port per-instance and save to config
- Failed downloads show "Show Error" (errorCode + errorMessage) and "Show Log" buttons
- Commit as you go using conventional commit style

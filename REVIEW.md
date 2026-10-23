# Review guide

ZeroType is a Windows-only voice input tool. The maintainer uses it all day.
A bug here means lost words, words pasted into the wrong window, or a leaked API key.

## What failure looks like

Report these as **Important**:

- **Lost or wrong text.** Audio trimming that cuts the first word. Paste that lands in
  the wrong window or loses focus to a menu (Alt in the hotkey opens menus in Chrome).
  A transcript that is changed after the dictionary step without a reason.
- **Leaked secrets.** API keys live in SharedPreferences. They must never reach logs,
  `LatencyLog`, the history file, error messages, or `print`.
- **Broken saved settings.** Renaming a SharedPreferences key (for example `HotkeyKind.prefsKey`)
  resets the user's settings to defaults. Require a migration or keep the old key.
- **Stuck state.** The recording state machine, the local STT endpoint status, or the overlay
  window that stops updating or never returns to idle.
- **Machine-specific code.** Hard-coded user paths, drive letters, or the maintainer's
  install locations. Detection must work on any Windows machine.
- **Silent hotkey failure.** `hotkey_manager_windows` reports success even when the hotkey is
  taken. Code that trusts that result without a probe is a bug.
- **Native runner mismatch.** A `MethodChannel` name or method that changes on one side only
  (`lib/` vs `windows/runner/*.cpp`).
- **Cost display.** Cost must come from the amount OpenRouter reports, not a hard-coded price.

## Do not report

- macOS or Linux support. The `macos/` folder was removed on purpose.
- Existing `flutter analyze` warnings. About 136 warnings and infos are the baseline.
- Style, naming, or formatting nits. Report at most two **Nit** findings per review.
- UI text in Traditional Chinese. That is intended.

## Skip these paths

- `build/`, `.dart_tool/`, `windows/flutter/ephemeral/`
- `pubspec.lock`
- `architecture.html`, `architecture-layers.svg`, `architecture.md` (diagrams; review only for wrong facts)

## Evidence

Every finding needs a file and line, and a concrete input that triggers it.
A finding without a trigger is a question. Label it as one.
A comment that starts with `notes:` is a recorded trade-off. Do not report it as a bug
unless the code it guards has changed.

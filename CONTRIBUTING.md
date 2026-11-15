# Contributing to MicnKey Deck

Thanks for helping! The whole app is three readable files in `app/`:

| File | What it is |
|---|---|
| `MicnKey.ps1` | The pad: window, keys, mic logic, hotkeys |
| `Settings.ps1` | The point-and-click settings window (English + Vietnamese) |
| `config.default.json` | The keys a new user starts with |

Run it without installing: double-click `app/Start-MicnKey.cmd`. Everything the pad does is written to `micnkey.log` next to it.

## 1. Add mic-button names for another language (most wanted)

The pad finds the AI app's dictation button by its accessibility **name**. In English those are `Dictate`, `Finish dictation`, `Stop dictation`. Other languages use other names.

1. Switch Claude / ChatGPT / Gemini to your language.
2. Press the pad's MIC key. If it can't find the button, `micnkey.log` lists every button name it saw, e.g.
   `mic: no start button in Claude (57 buttons). Names: ... | <your-language name> | ...`
3. Add a regular expression for that name to `"patterns"` of the MIC key in `config.default.json`:
   - start buttons, e.g. `"^dictate$"`
   - stop buttons must start like `"^(stop|finish|end|done) dictation"` — add your language's words to that group or add a new pattern **and** extend the stop check in `Invoke-Mic` (`$isStop`).
4. Open a pull request with the app, its language and the exact names.

Users can always teach the pad themselves (right-click MIC); learned buttons are stored in `mic-learned.json`.

## 2. Support another AI app

Add a key with `"action": "open"` to `config.default.json` and, for the mic, add the app's process/window name to `"apps"` and `"micProcess"` of the MIC key. Include the app's button names from the log in your PR.

## 3. Translate the Settings window

Every visible string in `Settings.ps1` is written as `(T 'English' 'Vietnamese')`. To add a language, extend the `T` function and the language list in the General section.

> `Settings.ps1` is saved as **UTF-8 with BOM** (needed for non-English text in Windows PowerShell 5.1). Keep `MicnKey.ps1` ASCII-only.

## config.json reference

```jsonc
{
  "language": "en",          // en | vi  (Settings window language)
  "keySize": 80,             // key size in pixels at 100% scaling
  "columns": 3,
  "opacity": 0.92,           // 0.5 - 1.0
  "autostart": false,        // start with Windows
  "layerToggle": "Insert",   // key that turns the number pad into pad keys; "off" to disable
  "showHotkey": "Ctrl+Alt+P", // brings the pad back on screen; "off" to disable
  "keys": [
    {
      "label": "Documents",
      "glyph": "E8B7",       // Segoe Fluent Icons / MDL2 code point
      "icon": "icons\\x.png",// optional image instead of a glyph
      "color": "#0F7FD8",    // app/folder keys: colour when that window is active
      "wide": false,         // full-width key
      "hotkey": "Ctrl+Alt+D",// or a single F1-F24 / Pause key
      "numpad": "NumPad1",   // key used in AI-keys mode
      "action": "folder",    // folder | run | text | keys | open | mic | desktop
      "path": "%DOCUMENTS%"  // %DOCUMENTS% %DESKTOP% %DOWNLOADS% %PICTURES% or any path
    }
  ]
}
```

Action fields: `folder`/`run` → `path` (file, app, URL) · `text` → `text` · `keys` → `keys` (SendKeys syntax, e.g. `{ENTER}`, `+{ENTER}`, `^c`) · `open` → `match` (process/window regex), `launch` (installed-app name, exe or URL), optional `web` fallback URL.

## Pull requests

- Keep changes small and focused; describe how you tested (Windows version, app versions, language).
- No new dependencies — the app must keep running on a stock Windows 10/11.

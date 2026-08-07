# Zinc

A native macOS menu bar app for saving text selections with context. Double-tap **Shift** to save, then **Option+Shift+V** to browse, search, and copy your saved clips.

## Features

- **Double-tap Shift** — captures the current text selection from any app
- **Rich content capture** — reads HTML, RTF, and images from the pasteboard and converts them to Markdown
- **Markdown vault** — each capture is saved as a `.md` file under `~/Zinc/YYYY-MM/DD/App/timestamp.md`
- **Context capture** — saves the source app name; for Safari, Chrome, Arc, and Edge also captures page URL and title
- **Option+Shift+V** — opens a Spotlight-style floating panel to browse saved clips
- **Search** — filter clips by text, app name, or URL
- **Multi-select** — Space to toggle selection, copy multiple clips as newline-joined plain text
- **Persistent storage** — clips saved to `~/Library/Application Support/Zinc/clips.json`

## Requirements

- macOS 14.0 or later
- Swift 6.x (Command Line Tools or Xcode)

## Build & Run

```bash
./scripts/bundle.sh
open Zinc.app
```

If the local `.build` directory gets corrupted, use a clean build path:

```bash
BUILD_PATH=/tmp/zinc-build ./scripts/bundle.sh
open Zinc.app
```

## Permissions

Zinc needs two macOS permissions to work fully:

### Accessibility (required)

Required for the double-Shift shortcut and selection capture.

1. Launch Zinc
2. When prompted, click **Open System Settings**
3. Enable **Zinc** under Privacy & Security → Accessibility

You can also open this from the menu bar icon → **Open Accessibility Settings**.

### Automation (optional, for browser URLs)

The first time you save a selection from Safari, Chrome, Arc, or Edge, macOS will ask for Automation permission so Zinc can read the current page URL and title.

## Usage

| Action | Shortcut |
|--------|----------|
| Save selection | Double-tap Shift |
| Open clip panel | Option+Shift+V |
| Navigate list | ↑ / ↓ |
| Toggle selection | Space |
| Copy | Return or Cmd+C |
| Delete | Delete |
| Close panel | Esc |

## Menu Bar

Click the clipboard icon in the menu bar for:

- Show Saved Clips
- Settings…
- Open Zinc Folder
- Choose Zinc Folder…
- Reindex from Vault…
- Clear All Clips
- Open Accessibility Settings
- Quit Zinc

### Double-Shift Settings

Open **Settings…** to tune false-positive filters without disabling Zinc in design apps:

- **Ignore Shift while a mouse button is held** — skips Shift+drag resize/scale
- **Require short Shift taps** — longer holds (e.g. constrain proportions) do not arm capture
- **Excluded Apps** — disable double-Shift per app; Option+Shift+V still works

## Markdown Vault

Each capture is exported in the background to a Markdown file with YAML front matter:

```
~/Zinc/
  2026-08/
    02/
      Safari/
        2026-08-02_23-42-07.md
        2026-08-02_23-42-07-assets/
          image-1.png
```

The vault location defaults to `~/Zinc` and can be changed from the menu bar. Images from rich selections are saved as sidecar files and linked relatively in the Markdown.

## Known Limitations

- Double-Shift detection requires Accessibility permission
- Browser URL capture requires per-browser Automation approval
- Selection capture synthesizes Cmd+C; your clipboard is restored after each save
- Remote image downloads use a short timeout and fall back to the original URL on failure

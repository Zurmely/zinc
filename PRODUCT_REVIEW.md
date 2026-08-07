# Zinc — Product & Code Review

Review date: 2026-08-07 · Commit reviewed: `6177aef` · Reviewed surface: all of `Sources/Zinc`, `Resources`, `scripts`, `README.md`

**GitHub issues:** Each item is filed on GitHub as [issues #2–#50](https://github.com/Zurmely/zinc/issues) (`ZINC-NNN` → issue `#NNN+1`, e.g. ZINC-001 → [#2](https://github.com/Zurmely/zinc/issues/2)).

## How to use this file

Every finding below is a self-contained work item with a stable ID (`ZINC-NNN`), so an agent can be handed one ID
and implement it without re-reading the whole review. Each item follows the same shape:

- **Area / Type / Severity / Effort** — triage metadata.
- **Files** — where the work lands.
- **Problem** — what is wrong, in user-visible terms where possible.
- **Evidence** — the specific code that causes it.
- **Proposed fix** — the intended direction (not a mandate; deviate if you find something better).
- **Acceptance criteria** — checkboxes that must all be true before the item is done.

Conventions:

- **Severity**: `P0` (data loss, security, or broken in shipped builds) · `P1` (materially degrades the core loop)
  · `P2` (quality, polish, ergonomics, maintainability).
- **Effort**: `S` (single file, contained) · `M` (a few files, some design) · `L` (cross-cutting, needs a plan).
- **Depends on** is listed when order matters. Do not start a dependent item before its dependency lands.
- Items marked **Needs product decision** contain a choice that shouldn't be made unilaterally by an agent.

Not verified by execution: this review is static. The repository is a macOS-only AppKit/SwiftUI app and was read on a
Linux machine with no Swift toolchain, so nothing here was confirmed by building or running Zinc. Treat reproduction
steps as expectations to verify first, not as observed behaviour.

---

## Index

| ID | Severity | Area | Title |
|----|----------|------|-------|
| [ZINC-001](#zinc-001) | P0 | Build / Release | Signed release builds cannot read browser URLs — missing Apple Events entitlement |
| [ZINC-002](#zinc-002) | P0 | Storage | A corrupt `clips.json` silently erases the entire clip history |
| [ZINC-003](#zinc-003) | P0 | Capture | Duplicate captures leave orphaned vault files behind a "Saved" confirmation |
| [ZINC-004](#zinc-004) | P0 | Vault | Changing the vault folder orphans existing clips and permanently breaks their deletion |
| [ZINC-005](#zinc-005) | P0 | Vault | Vault containment check uses string prefix matching and can trash files outside the vault |
| [ZINC-006](#zinc-006) | P0 | Reliability | Every failure path is silent — the user is told "Saved to Zinc" when nothing was saved |
| [ZINC-007](#zinc-007) | P0 | Privacy | Passwords and other concealed clipboard content are written to disk in plaintext |
| [ZINC-008](#zinc-008) | P1 | Capture | Capture blocks the main thread for up to a second on every double-Shift |
| [ZINC-009](#zinc-009) | P1 | Capture | The first browser capture always loses the page URL, and the result is read across a data race |
| [ZINC-010](#zinc-010) | P1 | Capture | Pasteboard save/restore is lossy and pollutes other clipboard managers |
| [ZINC-011](#zinc-011) | P1 | Capture | Double-Shift fires inside Zinc's own windows |
| [ZINC-012](#zinc-012) | P1 | Performance | Debug logging does synchronous file I/O on the main thread on every Shift tap, forever |
| [ZINC-013](#zinc-013) | P1 | Capture | Browser support is a hardcoded list missing most Chromium browsers |
| [ZINC-014](#zinc-014) | P1 | Shortcuts | Hotkey registration failure is silent and neither shortcut is configurable |
| [ZINC-015](#zinc-015) | P1 | Markdown | Pasteboard images are written to disk but never referenced in the Markdown |
| [ZINC-016](#zinc-016) | P1 | Markdown | The same image is saved twice with a mislabeled file extension |
| [ZINC-017](#zinc-017) | P1 | Markdown | Image path rewriting uses global string replacement and corrupts links |
| [ZINC-018](#zinc-018) | P1 | Markdown / Privacy | Remote image downloads are serial, blocking, and happen without consent |
| [ZINC-019](#zinc-019) | P1 | Markdown | Front matter can be emitted as invalid YAML, breaking Obsidian imports |
| [ZINC-020](#zinc-020) | P1 | Markdown | HTML→Markdown loses nested lists, task lists, and over-escapes inline text |
| [ZINC-021](#zinc-021) | P2 | Markdown | Front matter round-trip strips quotes; non-browser clips have no title |
| [ZINC-022](#zinc-022) | P1 | Performance | App icons and image thumbnails are re-resolved from disk on every row render |
| [ZINC-023](#zinc-023) | P1 | Performance | Search rescans every clip's full text on every keystroke, several times per frame |
| [ZINC-024](#zinc-024) | P1 | Correctness | The preview store mutates published state during SwiftUI body evaluation |
| [ZINC-025](#zinc-025) | P1 | Storage | The whole index is re-encoded and rewritten on every mutation; no size cap or retention |
| [ZINC-026](#zinc-026) | P2 | Performance | Accessibility permission is polled once a second for the life of the process |
| [ZINC-027](#zinc-027) | P2 | Performance | Parsed preview documents accumulate in memory without bound |
| [ZINC-028](#zinc-028) | P1 | Product | No "Launch at login" — a menu bar utility that must be started by hand every boot |
| [ZINC-029](#zinc-029) | P1 | Product | Copy returns the plain-text index snapshot, so image clips paste the literal text `[Image]` |
| [ZINC-030](#zinc-030) | P1 | Shortcuts | The documented Delete shortcut does nothing, and Cmd+C detection is layout-dependent |
| [ZINC-031](#zinc-031) | P2 | Product | The panel is not resizable and forgets its size and position |
| [ZINC-032](#zinc-032) | P2 | Product | No undo for delete or Clear All Clips |
| [ZINC-033](#zinc-033) | P1 | Product | A missing Accessibility grant is invisible — Zinc looks healthy but does nothing |
| [ZINC-034](#zinc-034) | P2 | Product | No way to organize clips: no pins, tags, notes, editing, or filters |
| [ZINC-035](#zinc-035) | P2 | Product | The save HUD is not configurable and its Cmd+Click action is undiscoverable |
| [ZINC-036](#zinc-036) | P2 | Product | "About Zinc" is a dead menu item |
| [ZINC-037](#zinc-037) | P2 | Product | No automation surface: no App Intents, URL scheme, or Spotlight indexing |
| [ZINC-038](#zinc-038) | P2 | Product | Arrow-key navigation wraps around, which breaks Shift-range selection |
| [ZINC-039](#zinc-039) | P2 | Product | No vault reindex, export, or import |
| [ZINC-040](#zinc-040) | P2 | Accessibility | The clip panel is effectively unusable with VoiceOver |
| [ZINC-041](#zinc-041) | P2 | i18n | No localization, and text size and motion preferences are ignored |
| [ZINC-042](#zinc-042) | P1 | Testing | There is no test target — the trickiest logic in the app is untested |
| [ZINC-043](#zinc-043) | P2 | Architecture | Singletons throughout leave no seams for testing |
| ZINC-044 | P2 | Architecture | Duplicated helpers and dead parameters |
| ZINC-045 | P2 | Tooling | Swift language mode drift and deprecated API usage |
| ZINC-046 | P2 | Tooling | No CI, linter, or formatter |
| ZINC-047 | P2 | Repo hygiene | No LICENSE, CONTRIBUTING, or changelog |
| ZINC-048 | P2 | Build / Release | No notarized, distributable artifact and no update mechanism |
| ZINC-049 | P2 | Docs | README documents behaviour the code does not implement |

---

## What Zinc gets right

Worth preserving through any refactor, because these are the parts that are genuinely well done:

- **The vault format is the right product bet.** Plain Markdown with YAML front matter in a dated folder tree means the
  user's data outlives the app and drops straight into Obsidian. Most clipboard managers trap data in a proprietary store.
- **The double-Shift false-positive work is thoughtful.** `ShiftShiftMonitor` handles modifier contamination, mouse-button
  suppression, hold-duration limits, and per-app exclusion. That is the hard-won detail that separates a demo from a tool
  people leave running.
- **`HTMLToMarkdown` avoids a real trap.** The comment at the top explaining why it parses from a Unicode string rather
  than UTF-8 `Data` (to avoid double-decoding `<meta charset>` documents into mojibake) reflects a bug that was clearly
  found the hard way, and the fix is correct.
- **CF_HTML clipboard header stripping** is handled, including the `StartFragment`/`EndFragment` offsets, which many
  implementations get wrong.
- **Deleting a clip trashes its assets folder and prunes newly-empty date directories**, so the vault doesn't rot.
- **The codesigning comment in `bundle.sh`** correctly identifies that ad-hoc signing rotates the CDHash and silently
  invalidates the Accessibility grant on every rebuild. That is a subtle macOS behaviour to have already diagnosed.

---

## P0 — Data loss, security, and broken-in-shipped-builds

### ZINC-001

**Signed release builds cannot read browser URLs — missing Apple Events entitlement**

- **Area:** Build / Release · **Type:** Bug · **Severity:** P0 · **Effort:** S
- **Files:** `scripts/bundle.sh`, new `Resources/Zinc.entitlements`

**Problem**
Capturing the page URL and title from Safari, Chrome, Arc, and Edge is a headline feature, and it silently does not work
in any properly signed build. `bundle.sh` signs with `--options runtime`, which enables the hardened runtime. Under the
hardened runtime, an app cannot send Apple events at all unless it is signed with the
`com.apple.security.automation.apple-events` entitlement — and there is no entitlements file anywhere in the repo. The
`NSAppleEventsUsageDescription` string in `Info.plist` is necessary but not sufficient; the entitlement must be applied
by `codesign`, not declared in `Info.plist`. The failure mode is the worst kind: no permission prompt, no error dialog,
`NSAppleScript` just returns an error that `ContextResolver` swallows, and every browser clip is saved with no URL.

This most likely went unnoticed because the ad-hoc fallback path (`codesign -s -` with no `--options runtime`) does not
enable the hardened runtime, so local development builds work while real signed builds do not.

**Evidence**

```bash
# scripts/bundle.sh
codesign -s "$IDENTITY" --force --deep --options runtime "$APP"   # hardened runtime, no --entitlements
```

```swift
// Sources/Zinc/ContextResolver.swift
let output = script.executeAndReturnError(&error)
if error != nil { return }   // errAEEventNotPermitted is swallowed here
```

**Proposed fix**
Add `Resources/Zinc.entitlements` containing `com.apple.security.automation.apple-events` set to `<true/>` (boolean, not
the string `YES` — the string form is rejected as an invalid entitlement), and pass `--entitlements` to both `codesign`
invocations in `bundle.sh`. While in there, drop `--deep` (deprecated by Apple; sign nested code explicitly, of which
Zinc currently has none) and log the AppleScript error instead of discarding it so this class of failure is visible next
time.

**Acceptance criteria**

- [ ] An entitlements plist exists in the repo and is passed to every `codesign` call in `bundle.sh`.
- [ ] `codesign -d --entitlements - Zinc.app` shows `com.apple.security.automation.apple-events` on a release build.
- [ ] Copying a selection from Safari in a signed, hardened build produces a clip whose `url` front matter is populated.
- [ ] AppleScript errors are logged with their error code rather than silently discarded.
- [ ] `--deep` is no longer used.

---

### ZINC-002

**A corrupt `clips.json` silently erases the entire clip history**

- **Area:** Storage · **Type:** Bug (data loss) · **Severity:** P0 · **Effort:** M

**Problem**
If `clips.json` fails to decode for any reason — a partial write from a crash or forced quit, a disk error, or a schema
change in a future version of Zinc — `ClipStore.load()` logs a line and resets `clips` to empty. The next capture then
calls `save()`, which overwrites the damaged-but-possibly-recoverable file with a one-element array. The user's entire
history is gone with no warning, no backup, and no way back. Because the vault Markdown files still exist on disk, the
data is technically recoverable, but Zinc has no mechanism to rebuild the index from them (see ZINC-039).

Compounding this: `Clip` has no schema version field, so there is no way to detect old-format data and migrate it rather
than discard it, and `save()` deletes the live file before moving the temp file into place, leaving a window in which
neither exists.

**Evidence**

```swift
// Sources/Zinc/ClipStore.swift
} catch {
    NSLog("Zinc: failed to load clips: \(error)")
    clips = []                       // history discarded
}
```

```swift
// Sources/Zinc/ClipStore.swift — the delete/move window
if FileManager.default.fileExists(atPath: fileURL.path) {
    try FileManager.default.removeItem(at: fileURL)
}
try FileManager.default.moveItem(at: tempURL, to: fileURL)
```

**Proposed fix**
Wrap the index in a versioned envelope (`{ "version": 1, "clips": [...] }`) with a decoder that tolerates the current
bare-array format for backward compatibility. On decode failure, move the bad file aside to
`clips.corrupt-<timestamp>.json` before starting empty, and surface a user-visible alert offering to reindex from the
vault. Replace the delete-then-move dance with `FileManager.replaceItemAt(_:withItemAt:)`, which is atomic. Keep one
rolling backup of the last good index.

**Acceptance criteria**

- [ ] The on-disk index carries a schema version; the legacy bare-array format still loads.
- [ ] A deliberately truncated `clips.json` is preserved as `clips.corrupt-<timestamp>.json` and never overwritten.
- [ ] The user is told when the index could not be read, and offered recovery.
- [ ] Index writes are atomic — no point in time exists where the index file is absent or partial.
- [ ] Unit tests cover: valid load, legacy-format load, corrupt load, and atomic replace.

---

### ZINC-003

**Duplicate captures leave orphaned vault files behind a "Saved" confirmation**

- **Area:** Capture · **Type:** Bug · **Severity:** P0 · **Effort:** S

**Problem**
`ClipStore.add` drops a clip whose text matches the most recent clip, but the caller doesn't know that and carries on
regardless: it exports a Markdown file to the vault and shows the "Saved to Zinc" HUD. So capturing the same selection
twice writes a second `.md` file (plus an assets folder) that no clip references. `setMarkdownPath` can't find a matching
clip so the path is never recorded, which means the file will never be trashed when the clip is deleted and will never be
shown in the panel. The vault accumulates invisible garbage, and the user is told the capture succeeded while the panel
shows nothing new.

The dedupe rule itself is also weak: it only compares against `clips.first`, so re-capturing something from five clips
ago creates a genuine duplicate.

**Evidence**

```swift
// Sources/Zinc/ClipStore.swift
func add(_ clip: Clip) {
    if let first = clips.first, first.text == clip.text { return }   // silent drop
```

```swift
// Sources/Zinc/ShiftShiftMonitor.swift — proceeds unconditionally
ClipStore.shared.add(clip)
MarkdownExporter.shared.export(selection: selection, clip: clip)
SaveHUD.show(text: clip.preview, source: clip.contextLabel, clipID: clip.id)
```

**Proposed fix**
Make `add` return an enum describing what happened (`.added`, `.deduplicated(existingID)`) and have the caller skip the
export on dedupe. Move the existing clip to the top of the list and refresh its `savedAt` so a re-capture behaves the way
users expect, and show a distinct HUD ("Already saved") so the feedback is honest. Broaden the dedupe check to a content
hash over recent clips rather than only the newest one. **Needs product decision:** whether a re-capture should bump the
existing clip's timestamp or leave it untouched.

**Acceptance criteria**

- [ ] A duplicate capture writes no new file into the vault.
- [ ] A duplicate capture shows feedback distinct from a successful save.
- [ ] Re-capturing text saved earlier than the most recent clip is also recognized as a duplicate.
- [ ] Every `.md` file in the vault is referenced by exactly one clip after a duplicate-capture sequence.

---

### ZINC-004

**Changing the vault folder orphans existing clips and permanently breaks their deletion**

- **Area:** Vault · **Type:** Bug · **Severity:** P0 · **Effort:** M · **Depends on:** ZINC-005

**Problem**
"Choose Zinc Folder…" only writes a new path into `UserDefaults`. Existing clips keep absolute `markdownPath` values
pointing into the old folder, so: their previews still load (fine, by luck), but deleting them silently does nothing to
the files, because `VaultFileManager.trash` refuses any path that isn't under the *current* vault root. The user deletes
a clip, the entry disappears from the panel, and the Markdown file with its contents stays on disk forever with nothing
in the UI referencing it. For anything sensitive that the user is deliberately deleting, that is a privacy failure, not
just untidiness.

**Evidence**

```swift
// Sources/Zinc/AppDelegate.swift
if panel.runModal() == .OK, let url = panel.url {
    VaultSettings.setVaultURL(url)   // nothing migrates, nothing re-points
    openVaultFolder()
}
```

```swift
// Sources/Zinc/VaultFileManager.swift
guard markdownURL.path.hasPrefix(vaultRoot.path) else {
    NSLog("Zinc: refusing to trash path outside vault: \(path)")
    continue
}
```

**Proposed fix**
On vault change, offer to move the existing vault contents to the new location and rewrite every clip's `markdownPath`
accordingly; if the user declines the move, still rewrite the paths so old files remain manageable, or store paths
relative to the vault root and resolve them at read time (cleaner, and it makes the vault portable). Deletion must
succeed for any file Zinc actually wrote, tracked independently of the current root setting.

**Acceptance criteria**

- [ ] After changing the vault folder, deleting a pre-existing clip trashes its `.md` file and assets folder.
- [ ] The user is asked whether to migrate existing captures, and migration works.
- [ ] Previews and thumbnails still resolve for clips captured before the change.
- [ ] Nothing in the codebase assumes `markdownPath` is under the current vault root except a deliberate safety check.

---

### ZINC-005

**Vault containment check uses string prefix matching and can trash files outside the vault**

- **Area:** Vault · **Type:** Bug (security) · **Severity:** P0 · **Effort:** S

**Problem**
The safety check that stops Zinc from trashing arbitrary files is `markdownURL.path.hasPrefix(vaultRoot.path)`. String
prefixes are not path containment: with a vault at `/Users/me/Zinc`, the path `/Users/me/Zinc-backup/notes.md` passes the
check and gets moved to the Trash along with a sibling `notes-assets` directory. `pruneEmptyDirectories` uses the same
comparison and will then walk *upward* deleting directories it believes are inside the vault. A guard that exists
specifically to prevent destructive mistakes does not hold.

**Evidence**

```swift
// Sources/Zinc/VaultFileManager.swift
guard markdownURL.path.hasPrefix(vaultRoot.path) else { ... }
...
while current.path.hasPrefix(root.path), current != root {
    try fileManager.removeItem(at: current)
```

Note also that `pruneEmptyDirectories` uses `removeItem` rather than `trashItem`, so an incorrectly matched directory is
deleted outright rather than being recoverable from the Trash.

**Proposed fix**
Compare resolved path components (`standardizedFileURL.resolvingSymlinksInPath().pathComponents`) and require that the
vault's components are a true prefix of the file's components. Add tests for the adversarial cases: sibling directory
with a shared name prefix, symlinked vault, relative path components, and the vault root itself. Use `trashItem` for
directory pruning too.

**Acceptance criteria**

- [ ] `~/Zinc-backup/x.md` is rejected when the vault is `~/Zinc`.
- [ ] Symlinked vault paths are handled correctly, both directions.
- [ ] Directory pruning never escapes the vault root and never removes the root itself.
- [ ] Pruning uses the Trash rather than unrecoverable deletion.
- [ ] Unit tests cover each of the above.

---

### ZINC-006

**Every failure path is silent — the user is told "Saved to Zinc" when nothing was saved**

- **Area:** Reliability · **Type:** Bug · **Severity:** P0 · **Effort:** M

**Problem**
There is no error surfacing anywhere in Zinc. Failures to create the vault directory, create the export directory, write
the Markdown file, write an image, save the index, or trash a deleted file all end in `NSLog` and nothing else. Meanwhile
`SaveHUD.show` is called before the export even starts, so the confirmation is unconditional. If the vault lives on an
unmounted external drive, a full disk, or a directory Zinc lacks permission to write, the user gets an unbroken stream of
"Saved to Zinc" while nothing is written. They will only discover this later, when they go looking for their notes.

**Evidence**

```swift
// Sources/Zinc/MarkdownExporter.swift
guard VaultSettings.ensureVaultExists() else { return }        // no user feedback
...
} catch {
    NSLog("Zinc: failed to write markdown: \(error)")          // no user feedback
}
```

```swift
// Sources/Zinc/ShiftShiftMonitor.swift — HUD shown before export can fail
MarkdownExporter.shared.export(selection: selection, clip: clip)
SaveHUD.show(text: clip.preview, ...)
```

**Proposed fix**
Introduce a small error-reporting path: a typed error enum, a reporter that both logs and presents user-visible feedback,
and a failure state on the HUD ("Couldn't save — vault unavailable") that links to the relevant setting. Verify vault
writability when it is chosen and when the app launches, and reflect a broken vault in the menu bar (see ZINC-033).

**Acceptance criteria**

- [ ] A write failure produces a visible, actionable error instead of a success HUD.
- [ ] An unwritable or missing vault is detected at launch and at selection time, and reported.
- [ ] Index save failures are surfaced, not just logged.
- [ ] No `catch` block in the export or storage paths ends in a bare `NSLog`.

---

### ZINC-007

**Passwords and other concealed clipboard content are written to disk in plaintext**

- **Area:** Privacy · **Type:** Bug (security) · **Severity:** P0 · **Effort:** S

**Problem**
Zinc reads whatever is on the pasteboard and writes it, unencrypted, to both `clips.json` and a Markdown file in the
vault. It does not check the `org.nspasteboard.ConcealedType` marker that password managers (1Password, Keychain Access,
Bitwarden, and others) set precisely so that clipboard tools skip their content. A double-Shift in a password field, or a
double-Shift shortly after copying a credential, persists that secret to disk in cleartext where it will sit indefinitely
and get synced to any cloud-backed folder the user chose as their vault. It is also invisible to the user, since the
panel preview would just look like a random string.

The same applies to the transient/auto-generated markers (`org.nspasteboard.TransientType`,
`org.nspasteboard.AutoGeneratedType`), which exist to signal "do not record this".

**Evidence**
`RichSelection.read(from:)` inspects only `.string`, `.html`, `.rtf`, `.rtfd`, `.png`, `.tiff`, and `public.image`. No
pasteboard type is treated as a reason to refuse capture, and there is no allow/deny list of applications for capture
(the exclusion list in `ShiftFilterSettings` only suppresses the double-Shift trigger, and only for apps the user has
manually added).

**Proposed fix**
Refuse to capture when `org.nspasteboard.ConcealedType` is present, honour the transient and auto-generated markers, and
ship a default exclusion list covering well-known password managers so the trigger doesn't fire there in the first place.
Consider a "never capture from these apps" list that is enforced at save time rather than only at trigger time. Document
the behaviour in the README so users know the guarantee exists. **Needs product decision:** whether to also add
"exclude secure text fields" detection via the Accessibility API, which is more invasive but catches the in-field case.

**Acceptance criteria**

- [ ] Content marked `org.nspasteboard.ConcealedType` is never written to `clips.json` or the vault.
- [ ] Transient and auto-generated pasteboard markers are respected.
- [ ] A default set of password-manager bundle IDs ships in the exclusion list.
- [ ] The README states what Zinc refuses to capture.
- [ ] A unit test asserts that a concealed pasteboard item yields no clip.

---

## P1 — Capture pipeline

### ZINC-008

**Capture blocks the main thread for up to a second on every double-Shift**

- **Area:** Capture · **Type:** Performance · **Severity:** P1 · **Effort:** M

**Problem**
The capture path runs entirely on the main thread and blocks it in two places. `waitForNewPasteboardContent` busy-waits
in a `usleep` loop for up to 500 ms polling `changeCount`, then sleeps another 25 ms as a fudge factor for apps that
write their flavors in stages. Then `ContextResolver.runAppleScript` dispatches work to a background queue and
immediately blocks the *calling* (main) thread on a semaphore for up to another 500 ms. Add the deliberate 120 ms delay
before capture starts and a single double-Shift can freeze the main thread for over a second — during which the menu bar
is unresponsive, the HUD can't animate, and any Zinc window is frozen. The 25 ms fudge is also just a guess, which makes
capture of slower apps intermittently incomplete.

**Evidence**

```swift
// Sources/Zinc/SelectionCapture.swift
let deadline = Date().addingTimeInterval(0.5)
while Date() < deadline {
    if pasteboard.changeCount != originalChangeCount {
        usleep(25_000)                     // hope the app finished writing
        return RichSelection.read(from: pasteboard)
    }
    usleep(10_000)                         // main thread is asleep here
}
```

```swift
// Sources/Zinc/ContextResolver.swift
_ = semaphore.wait(timeout: .now() + 0.5)  // called from the main thread
```

**Proposed fix**
Make the capture pipeline asynchronous: convert it to `async`/`await`, poll the pasteboard with a repeating timer or
`Task.sleep` so the run loop keeps turning, and resolve browser context concurrently with the pasteboard wait rather than
after it. Replace the fixed 25 ms settle with a short stability check (read, wait, read again, accept when the flavor set
stops changing). Keep the whole pipeline off the main thread except for the final UI update.

**Acceptance criteria**

- [ ] The main thread is never blocked for more than one frame during capture.
- [ ] Menu bar and HUD stay responsive throughout a capture.
- [ ] Browser context resolution overlaps the pasteboard wait rather than following it.
- [ ] Capturing from a slow app either succeeds with complete content or reports failure — never silently partial.

---

### ZINC-009

**The first browser capture always loses the page URL, and the result is read across a data race**

- **Area:** Capture · **Type:** Bug · **Severity:** P1 · **Effort:** S · **Depends on:** ZINC-001

**Problem**
The first time Zinc sends an Apple event to a browser, macOS shows an Automation consent prompt, and the script does not
return until the user answers it. `runAppleScript` gives up after 500 ms, so that first capture — the exact moment when
the feature is being introduced to the user — always saves a clip with no URL and no title, even after they click Allow.
Worse, the closure keeps running on the background queue and writes `result` after the main thread has already timed out
and read it: an unsynchronized write and read of the same variable from two threads, which is undefined behaviour and
would be a hard error under Swift 6 strict concurrency.

**Evidence**

```swift
// Sources/Zinc/ContextResolver.swift
var result: (url: String, title: String)?
DispatchQueue.global(qos: .userInitiated).async {
    ...
    result = (url: url, title: title)      // written after the timeout below returns
}
_ = semaphore.wait(timeout: .now() + 0.5)
return result                              // read on the main thread
```

**Proposed fix**
Fold this into the async capture pipeline from ZINC-008 so there is no shared mutable variable and no semaphore. Detect
the not-yet-authorized state explicitly with `AEDeterminePermissionToAutomateTarget` before scripting, and if consent is
pending, either wait for the answer without a deadline or write the clip first and fill in the URL when the answer
arrives. Handle the "user denied" case by remembering the denial and not re-prompting on every capture.

**Acceptance criteria**

- [ ] Granting Automation permission on first use results in a clip that has the URL and title.
- [ ] No variable is written on one queue and read on another without synchronization.
- [ ] A denied Automation permission is remembered and does not cause a prompt or a stall on later captures.
- [ ] `errAEEventNotPermitted` and consent-pending are distinguished from "no windows open" in logs.

---

### ZINC-010

**Pasteboard save/restore is lossy and pollutes other clipboard managers**

- **Area:** Capture · **Type:** Bug · **Severity:** P1 · **Effort:** M

**Problem**
Capture works by clobbering the user's clipboard with a synthetic Cmd+C and restoring a snapshot afterwards. The snapshot
is not faithful: it materializes only the flavors already declared on each item, which silently drops lazily-provided
data and file promises (large images from Photoshop, drag-promise types from Finder). The restore also unconditionally
calls `clearContents()` and rewrites the pasteboard even when capture failed and nothing needed restoring, which bumps
`changeCount` twice and makes every other clipboard manager on the system record a spurious new entry. Users running
Raycast, Maccy, or Paste will see their history filled with duplicates every time they use Zinc.

**Evidence**

```swift
// Sources/Zinc/SelectionCapture.swift
for type in item.types {
    if let data = item.data(forType: type) { entry[type] = data }   // forces lazy providers; promises lost
}
...
func restore(to pasteboard: NSPasteboard) {
    pasteboard.clearContents()          // happens even when nothing was captured
```

**Proposed fix**
Skip the restore entirely when `changeCount` never moved. Preserve the original item ordering and skip known promise
types rather than materializing them. Mark Zinc's own restore write with `org.nspasteboard.TransientType` and
`org.nspasteboard.AutoGeneratedType` so well-behaved clipboard managers ignore it. Longer term, investigate reading the
selection through the Accessibility API (`AXSelectedText`) first and only falling back to the Cmd+C trick, which removes
the clipboard round-trip for most apps entirely — that is the single biggest robustness win available in this file.

**Acceptance criteria**

- [ ] A failed capture leaves `changeCount` unchanged and the clipboard untouched.
- [ ] Copying a large image in another app, then capturing, then pasting yields the original image.
- [ ] Zinc's restore write is marked transient/auto-generated.
- [ ] `AXSelectedText` is attempted before synthesizing Cmd+C, with a documented fallback path.

---

### ZINC-011

**Double-Shift fires inside Zinc's own windows**

- **Area:** Capture · **Type:** Bug · **Severity:** P1 · **Effort:** S

**Problem**
The only frontmost-app check is against the user's manually curated exclusion list, and `SettingsView.addApplication`
explicitly refuses to add Zinc itself. So double-tapping Shift while the clip panel or Settings window is focused
triggers a capture: Zinc synthesizes Cmd+C into its own window, clobbers and restores the clipboard, and saves a clip of
its own UI text. Typing a capital letter in the search field twice in quick succession is enough to set this off.

**Evidence**

```swift
// Sources/Zinc/SettingsView.swift
if bundleID == Bundle.main.bundleIdentifier { continue }   // can never be excluded
```

```swift
// Sources/Zinc/ShiftFilterSettings.swift — only consults the user's list
func isFrontmostAppExcluded() -> Bool {
    isExcluded(bundleID: NSWorkspace.shared.frontmostApplication?.bundleIdentifier)
}
```

**Proposed fix**
Always suppress the double-Shift trigger when Zinc is the frontmost application, independently of the user list. Keep the
Settings-side guard so the list stays clean, and note the behaviour in the tooltip text.

**Acceptance criteria**

- [ ] Double-Shift in the clip panel's search field never creates a clip.
- [ ] Double-Shift in Settings never creates a clip.
- [ ] The suppression does not depend on the user's exclusion list.
- [ ] A unit test covers the frontmost-is-Zinc case in the trigger's decision logic.

---

### ZINC-012

**Debug logging does synchronous file I/O on the main thread on every Shift tap, forever**

- **Area:** Performance · **Type:** Bug · **Severity:** P1 · **Effort:** S

**Problem**
`ZincLog.write` is called from inside `handleFlagsChanged`, which runs on the main thread for every single Shift press and
release the user makes anywhere on the system. Each call formats an ISO-8601 date (allocating a fresh
`ISO8601DateFormatter` every time), calls `NSLog`, opens a file handle, seeks to the end, writes, and closes. That is
synchronous disk I/O on the main thread on the keyboard event path, in an app that runs all day — a measurable battery
and latency cost for a diagnostic nobody is reading. The log is never rotated or capped, so `debug.log` grows
monotonically for the life of the install, and there is no way for a user to turn it off. There are also two independent
copies of this logging code, in `ShiftShiftMonitor.swift` and `Permissions.swift`.

**Evidence**

```swift
// Sources/Zinc/ShiftShiftMonitor.swift
static func write(_ message: String) {
    let line = "\(ISO8601DateFormatter().string(from: Date()))  \(message)\n"
    NSLog("Zinc: %@", message)
    ... FileHandle(forWritingTo: url) ... handle.seekToEnd() ... handle.write(...)
}
```
Called from the arm, cancel, ignore, and recognize branches of the Shift state machine — i.e. on ordinary typing.

**Proposed fix**
Replace both copies with one logger built on `os.Logger` and a private subsystem, so the system handles buffering,
levels, and privacy redaction. If a file sink is still wanted for user-submitted diagnostics, put it behind a debug
setting, write it on a serial background queue, and cap it with rotation. Drop logging from the hot per-keystroke path
entirely, or gate it behind a verbose flag that is off by default.

**Acceptance criteria**

- [ ] No file I/O happens on the main thread during key event handling.
- [ ] One logging implementation exists, not two.
- [ ] File logging is off by default, or capped and rotated when on.
- [ ] Ordinary typing produces no log writes at the default setting.

---

### ZINC-013

**Browser support is a hardcoded list missing most Chromium browsers**

- **Area:** Capture · **Type:** Enhancement · **Severity:** P1 · **Effort:** S

**Problem**
`ContextResolver.browserBundleIDs` covers Safari, Chrome, Chrome Canary, Arc, and Edge. Every other Chromium browser
speaks the same AppleScript dictionary (`active tab of front window`) and would work with no new code, but is silently
treated as a generic app: Brave, Vivaldi, Opera, Chromium, Dia, Chrome Beta/Dev, Safari Technology Preview, Orion.
Users of those browsers get clips with no URL and no title and no indication why. The bundle-ID-to-AppleScript-app-name
mapping is also duplicated as a nested `switch` inside a `switch`, which is exactly the shape that makes people reluctant
to add the next browser.

**Evidence**

```swift
// Sources/Zinc/ContextResolver.swift
private static let browserBundleIDs: Set<String> = [
    "com.apple.Safari", "com.google.Chrome", "com.google.Chrome.canary",
    "company.thebrowser.Browser", "com.microsoft.edgemac",
]
```

**Proposed fix**
Replace the sets and nested switches with one table of `(bundleID, applicationName, dialect)` rows, where dialect is
`safari` or `chromium`, and drive both the membership test and the script generation from it. Add the browsers listed
above. Firefox has no scriptable tab API and should be documented as unsupported rather than left ambiguous.

**Acceptance criteria**

- [ ] Brave, Vivaldi, Opera, Chromium, Chrome Beta/Dev, and Safari Technology Preview capture URL and title.
- [ ] Adding a browser is a one-line table entry.
- [ ] The README lists supported browsers and names Firefox as unsupported, with the reason.

---

### ZINC-014

**Hotkey registration failure is silent and neither shortcut is configurable**

- **Area:** Shortcuts · **Type:** Bug + Enhancement · **Severity:** P1 · **Effort:** M

**Problem**
`HotKeyCenter.register()` discards the `OSStatus` from both `InstallEventHandler` and `RegisterEventHotKey`. Option+Shift+V
is not an unusual combination, and if another app already owns it, registration fails, Zinc says nothing, and the panel
is only reachable through the menu bar — with the user reasonably concluding the app is broken. There is no way to pick a
different shortcut, no way to change the double-Shift trigger to another key, and no way to disable the double-Shift
trigger at all short of excluding apps one at a time. The double-tap window is a hardcoded 0.55 s even though the closely
related hold-duration threshold *is* exposed in Settings, which is an odd asymmetry.

**Evidence**

```swift
// Sources/Zinc/HotKeyCenter.swift
RegisterEventHotKey(UInt32(kVK_ANSI_V), UInt32(optionKey | shiftKey), hotKeyID,
                    GetApplicationEventTarget(), 0, &hotKeyRef)   // OSStatus discarded
```

```swift
// Sources/Zinc/ShiftShiftMonitor.swift
private let doubleTapWindow: TimeInterval = 0.55   // not configurable
```

**Proposed fix**
Check both status codes, and on failure show a clear message pointing at the shortcut setting. Add a shortcut recorder to
Settings for the panel hotkey, a master on/off switch for the double-Shift trigger, an alternative trigger key
(double-Command and double-Control are the common alternatives), and expose the double-tap window alongside the existing
hold-duration control. **Needs product decision:** whether to take on a dependency such as KeyboardShortcuts for the
recorder UI or hand-roll it.

**Acceptance criteria**

- [ ] A conflicting hotkey produces a visible, actionable message.
- [ ] The panel shortcut is user-configurable and persists across launches.
- [ ] The double-Shift trigger can be disabled outright.
- [ ] The double-tap window is exposed in Settings with the same clamping treatment as hold duration.

---

## P1 — Markdown fidelity

### ZINC-015

**Pasteboard images are written to disk but never referenced in the Markdown**

- **Area:** Markdown · **Type:** Bug · **Severity:** P1 · **Effort:** S

**Problem**
`processImages` writes every pasteboard image into the assets folder, but only inserts a Markdown reference to it when the
document body is empty. So the common case — selecting a block of text that includes an image, or copying an image with a
caption — writes the image file to disk and then never links it. The user's note silently loses the image, and the vault
gains an orphaned file that nothing references and that deletion will not clean up beyond the assets folder. When there
are multiple pasteboard images, the same condition means at most the first one can ever be referenced, because the body
is no longer empty after the first insertion.

**Evidence**

```swift
// Sources/Zinc/MarkdownExporter.swift
let relativePath = "\(assetsFolderName)/\(fileName)"
if result.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
    result = "![image](\(relativePath))"        // only when there is no text at all
}
imageIndex += 1
```

**Proposed fix**
Always emit a reference for every pasteboard image written. When the HTML conversion already produced `img` references
that correspond to the same images, deduplicate rather than double-linking; otherwise append the images to the end of the
body. Never write a file into the assets folder that the document does not reference.

**Acceptance criteria**

- [ ] Capturing text plus one image yields Markdown containing both the text and an image reference.
- [ ] Capturing several images yields a reference for each one.
- [ ] No file exists in an assets folder that is not referenced by its sibling `.md` file.
- [ ] A unit test asserts the invariant "every written asset is referenced".

---

### ZINC-016

**The same image is saved twice with a mislabeled file extension**

- **Area:** Markdown · **Type:** Bug · **Severity:** P1 · **Effort:** S

**Problem**
`readImages` iterates `.png`, `.tiff`, and `public.image` and appends each one whose bytes differ from what it already
collected. A single copied image is normally offered on the pasteboard in several flavors, and PNG bytes and TIFF bytes of
the same picture are not equal — so Zinc collects the same picture twice and writes two files. The extension logic is
also wrong: anything that isn't `.png` is labeled `tiff`, including `public.image` payloads that may be JPEG or HEIC.
`normalizedExtension` then renames `tiff` to `png`, and `normalizedImageData` only actually transcodes if `NSImage` can
decode the data — so a decode failure produces a file named `.png` containing JPEG or TIFF bytes, which some Markdown
renderers will refuse to display.

**Evidence**

```swift
// Sources/Zinc/RichSelection.swift
let ext = type == .png ? "png" : "tiff"
if !images.contains(where: { $0.data == data }) {      // byte equality across flavors: never equal
    images.append(PasteboardImage(data: data, fileExtension: ext))
}
```

```swift
// Sources/Zinc/MarkdownExporter.swift
private func normalizedExtension(_ ext: String) -> String { ext == "tiff" ? "png" : ext }
```

**Proposed fix**
Read one image per pasteboard *item*, choosing the best available flavor in priority order rather than accumulating all
of them. Detect the real format from the data (`CGImageSource`/`UTType`) instead of inferring it from the pasteboard type,
and make the written extension always match the actual bytes — transcode or keep the original format, but never both
disagree.

**Acceptance criteria**

- [ ] Copying one image produces exactly one file in the assets folder.
- [ ] Every written image file's extension matches its actual encoded format.
- [ ] JPEG and HEIC pasteboard payloads are handled without being renamed to `.png`.
- [ ] A unit test covers the multi-flavor single-image case.

---

### ZINC-017

**Image path rewriting uses global string replacement and corrupts links**

- **Area:** Markdown · **Type:** Bug · **Severity:** P1 · **Effort:** S

**Problem**
After downloading a remote image, the exporter swaps the URL for a local path using
`result.replacingOccurrences(of: reference.markdownSource, with: localPath)` across the whole document. That replaces the
URL everywhere it appears, not just in the image reference — so a hyperlink whose `href` is the same URL (extremely
common: an image wrapped in a link to itself) has its `href` rewritten to a local relative path and stops working. If the
same image appears twice in the selection, the first replacement rewrites both occurrences, the second download writes
another file that nothing references, and `imageIndex` drifts out of step with the files actually linked.

**Evidence**

```swift
// Sources/Zinc/MarkdownExporter.swift
if let localPath = fetchRemoteImage(from: source, ...) {
    result = result.replacingOccurrences(of: reference.markdownSource, with: localPath)
```

**Proposed fix**
Stop round-tripping through strings. Have `HTMLToMarkdown` emit stable placeholder tokens for image sources and have the
exporter substitute those tokens, so a replacement can only ever affect the intended image reference. Deduplicate
identical sources so each unique image is downloaded and written once and all its references point at the same file.

**Acceptance criteria**

- [ ] An image wrapped in a link to its own URL keeps a working `href` after export.
- [ ] The same image appearing twice produces one file and two references to it.
- [ ] Asset numbering has no gaps and matches the files on disk.
- [ ] Unit tests cover the self-linked-image and repeated-image cases.

---

### ZINC-018

**Remote image downloads are serial, blocking, and happen without consent**

- **Area:** Markdown / Privacy · **Type:** Bug · **Severity:** P1 · **Effort:** M

**Problem**
Two distinct problems in one function. Performance: `fetchRemoteImage` blocks its queue on a semaphore for up to 6 s per
image, sequentially. A clipping from an image-heavy page can occupy the export queue for minutes, and because exports are
serialized on one queue, every capture made in the meantime is stuck behind it — the panel keeps showing plain-text
fallbacks with no indication that anything is pending. Privacy: capturing a selection silently issues HTTP requests to
whatever third-party hosts the page referenced, revealing the user's IP and the fact that they clipped that content, with
no setting to turn it off and no mention in the README. For a local-first note-taking tool, an undisclosed network egress
on every capture is a meaningful surprise.

**Evidence**

```swift
// Sources/Zinc/MarkdownExporter.swift
task.resume()
_ = semaphore.wait(timeout: .now() + 6)    // per image, serial
```

**Proposed fix**
Convert to concurrent `async` downloads with a bounded task group and one overall budget for the whole export rather than
a per-image timeout. Add a Settings toggle for "Download remote images" (**Needs product decision:** default on or off —
off is the privacy-respecting default, on is the better-notes default) and state the behaviour in the README. Show pending
export state in the panel so a slow export is visible rather than mysterious.

**Acceptance criteria**

- [ ] Image downloads run concurrently under one total time budget.
- [ ] A slow or hanging host cannot delay unrelated captures.
- [ ] Remote fetching is user-controllable and its default is documented.
- [ ] The panel indicates when a clip's export is still in progress.

---

### ZINC-019

**Front matter can be emitted as invalid YAML, breaking Obsidian imports**

- **Area:** Markdown · **Type:** Bug · **Severity:** P1 · **Effort:** S

**Problem**
`yamlEscape` wraps a value in quotes when it contains `:`, `#`, `"`, or a newline, and escapes embedded quotes — but it
does not escape the newline itself. A page title containing a line break therefore produces a quoted scalar broken across
two physical lines, which is invalid YAML and makes the whole front matter block fail to parse. Several other YAML
indicator characters are unhandled: a value starting with `-`, `?`, `&`, `*`, `!`, `|`, `>`, `[`, `{`, or `@`, a value
that looks like a number or boolean, and values with leading or trailing whitespace all need quoting and don't get it.
Since the entire promise of the vault is that these files work in other tools, malformed front matter is a
correctness bug, not a cosmetic one.

**Evidence**

```swift
// Sources/Zinc/MarkdownExporter.swift
private func yamlEscape(_ value: String) -> String {
    if value.contains(":") || value.contains("#") || value.contains("\"") || value.contains("\n") {
        return "\"\(value.replacingOccurrences(of: "\"", with: "\\\""))\""   // newline still literal
    }
    return value
}
```

**Proposed fix**
Write a correct double-quoted-scalar emitter: escape `\`, `"`, and control characters including `\n`, `\r`, and `\t`, and
quote whenever the value begins with a YAML indicator, is empty, has surrounding whitespace, or would otherwise be parsed
as a non-string scalar. Table-drive the tests. Consider emitting all front matter values quoted, which is boring and
always correct.

**Acceptance criteria**

- [ ] A title containing a newline produces valid, single-line YAML.
- [ ] Values starting with YAML indicator characters are quoted.
- [ ] Emitted front matter parses cleanly in a real YAML parser and in Obsidian.
- [ ] Unit tests cover newline, quote, colon, indicator-prefix, numeric-looking, and empty values.

---

### ZINC-020

**HTML→Markdown loses nested lists, task lists, and over-escapes inline text**

- **Area:** Markdown · **Type:** Bug · **Severity:** P1 · **Effort:** M

**Problem**
The converter handles flat documents well but degrades on structure that is common in the sources Zinc targets
(documentation sites, Notion, Google Docs, GitHub):

- **Nested lists.** A `ul` inside an `li` is converted by `convertChildren`, and `block()` wraps every block construct in
  `\n\n`, so the nested list arrives as a blank-line-separated chunk inside a list item. The mitigation — replacing `\n`
  with `\n  ` — indents by two spaces uniformly and cannot reconstruct the nesting depth, so multi-level lists collapse.
- **Task lists.** `<input type="checkbox">` is dropped by the default branch, so `- [ ]` / `- [x]` become plain bullets
  and the checked state is lost.
- **Over-escaping.** `escapeText` escapes `*`, `_`, `#`, `[`, `]`, and backtick in every text node, including inside
  headings and link text where several of them are harmless. Round-tripping through `MarkdownDocument.parse` and
  `AttributedString(markdown:)` can then surface stray backslashes in the preview.
- **Under-escaping in links.** A URL containing spaces or parentheses is emitted bare inside `](...)`, producing a broken
  link; link *text* containing `]` is not escaped either.
- **Tables.** `colspan` and `rowspan` are ignored, so merged cells shift columns; a table with no header row still gets
  its first data row promoted to a header.
- **Performance.** `collapseBlankLines` repeatedly rescans and rewrites the entire string until no triple newline remains,
  which is quadratic on large documents.

**Evidence**

```swift
// Sources/Zinc/HTMLToMarkdown.swift
let content = convertChildren(of: item, ...)
    .replacingOccurrences(of: "\n", with: "\n  ")     // depth-blind indentation
...
private static func block(_ text: String) -> String { "\n\n\(text)\n\n" }
...
while result.contains("\n\n\n") {                     // quadratic
    result = result.replacingOccurrences(of: "\n\n\n", with: "\n\n")
}
```

**Proposed fix**
Thread a rendering context (list depth, whether we are inside a list item or a table cell, whether inline escaping is
needed) through the conversion instead of relying on post-hoc string surgery. Emit nested lists with depth-correct
indentation, support checkbox inputs, escape link destinations properly, escape only what needs escaping in each context,
and collapse blank lines in a single pass. This is the right moment to add the test suite from ZINC-042, since this
converter is pure and highly testable.

**Acceptance criteria**

- [ ] A three-level nested list round-trips with correct indentation.
- [ ] Task lists preserve their checked state.
- [ ] URLs containing spaces or parentheses produce working links.
- [ ] Headings and link text are not littered with unnecessary backslashes.
- [ ] Blank-line collapsing is single-pass.
- [ ] Snapshot tests exist for real captured HTML from at least Notion, Google Docs, GitHub, and a Chromium CF_HTML payload.

---

### ZINC-021

**Front matter round-trip strips quotes; non-browser clips have no title**

- **Area:** Markdown · **Type:** Bug · **Severity:** P2 · **Effort:** S

**Problem**
`splitFrontMatter` finishes each value with `trimmingCharacters(in: CharacterSet(charactersIn: "\""))`, which removes
*every* leading and trailing quote character rather than one pair of enclosing delimiters. A title that legitimately
starts or ends with a quotation mark — `"Hello," she said` — loses it, and the escaped `\"` sequences written by
`yamlEscape` are never unescaped, so they display literally. Separately, only browser clips get a `title:`, so in Obsidian
every clip captured from a non-browser app shows up as a bare timestamp filename with no human-readable name.

**Evidence**

```swift
// Sources/Zinc/MarkdownDocument.swift
frontMatter[key] = value.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
```

**Proposed fix**
Parse quoted scalars properly: strip exactly one enclosing pair and unescape the contents, matching the emitter from
ZINC-019 as an inverse. Derive a `title:` for every clip from the first heading or first line of content when no page
title exists.

**Acceptance criteria**

- [ ] A title with leading and trailing quotes survives an export/parse round-trip unchanged.
- [ ] `\"` sequences are unescaped on read.
- [ ] Every exported clip has a `title:` in its front matter.
- [ ] A round-trip property test asserts emit-then-parse equals the original for a table of awkward values.

---

## P1 — Performance and correctness under load

### ZINC-022

**App icons and image thumbnails are re-resolved from disk on every row render**

- **Area:** Performance · **Type:** Performance · **Severity:** P1 · **Effort:** S

**Problem**
`ClipRowView.appIcon(for:)` calls `NSWorkspace.urlForApplication(withBundleIdentifier:)` followed by `icon(forFile:)`, and
it is called twice per row (once for the thumbnail fallback, once for the metadata line). `loadThumbnail` constructs an
`NSImage` from a file on disk. Both run inside `body`, which SwiftUI re-evaluates on every keystroke in the search field,
every focus change, and every 60-second tick of the `SavedAtText` timeline. So scrolling or typing repeatedly hits
LaunchServices and decodes images from disk on the main thread. The same uncached `appIcon` helper is duplicated in
`ClipDetailView` and `ShiftFilterSettings`.

**Evidence**

```swift
// Sources/Zinc/ClipListView.swift — inside body, uncached
private func appIcon(for bundleID: String) -> NSImage {
    if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
        return NSWorkspace.shared.icon(forFile: appURL.path)
    }
```

**Proposed fix**
Add one shared, size-aware icon cache keyed by bundle ID, and a thumbnail cache keyed by asset path and modification
date, both returning immediately from memory after first load and decoding off the main thread on a miss. Replace all
three duplicated `appIcon` implementations with it.

**Acceptance criteria**

- [ ] Typing in the search field triggers no LaunchServices lookups and no image decodes.
- [ ] Icon and thumbnail loading happens off the main thread on cache miss.
- [ ] One icon-cache implementation is used by the list, the detail view, and Settings.
- [ ] Scrolling a list of 1,000 clips holds 60 fps.

---

### ZINC-023

**Search rescans every clip's full text on every keystroke, several times per frame**

- **Area:** Performance · **Type:** Performance · **Severity:** P1 · **Effort:** M

**Problem**
`filteredClips` is a computed property that lowercases the query and then lowercases and substring-scans the full text,
app name, page title, and page URL of every clip. It is not memoized, and `ClipListView` reads it from `body`,
`focusedClip`, `handleRowTap`, and each of the row callbacks — so a single body pass runs the whole scan several times
over. `ClipPanelViewModel.handleKeyEvent` recomputes it again on every key press, as does `deleteSelected`. There is no
debounce, so every character typed triggers the whole thing. Since `Clip.text` is unbounded (see ZINC-025), a history of a
few thousand clips containing long selections means megabytes of string lowercasing per keystroke, on the main thread.

**Evidence**

```swift
// Sources/Zinc/ClipPanel.swift
return clips.filter { clip in
    clip.text.lowercased().contains(query)              // allocates a lowercased copy per clip per call
        || clip.appName.lowercased().contains(query) ...
}
```

**Proposed fix**
Compute the filtered list once per change and publish it, rather than deriving it on demand in several places. Precompute
a lowercased, normalized search key per clip at insert time (and at load) so filtering never allocates. Debounce the query
by ~120 ms and run the filter off the main thread for large histories. Use `localizedStandardContains` for
diacritic- and case-insensitive matching that behaves correctly in non-English text.

**Acceptance criteria**

- [ ] The filter runs at most once per query change, not once per view read.
- [ ] Search over 5,000 clips keeps typing latency imperceptible.
- [ ] Matching is diacritic-insensitive and locale-correct.
- [ ] No `lowercased()` allocation happens inside the per-keystroke path.

---

### ZINC-024

**The preview store mutates published state during SwiftUI body evaluation**

- **Area:** Correctness · **Type:** Bug · **Severity:** P1 · **Effort:** S

**Problem**
`MarkdownPreviewStore.document(for:)` writes to `documents`, which is `@Published`, and it is called directly from
`ClipListView.body` (via `previewStore.document(for: clip)` when constructing each row) and from `ClipDetailView.document`.
Mutating observed state while SwiftUI is evaluating a body is unsupported: it produces the "Publishing changes from within
view updates is not allowed" runtime warning and can cause dropped updates, redundant render passes, or inconsistent
frames. It also kicks off a background load from inside body evaluation, so scrolling schedules file reads as a side
effect of drawing.

**Evidence**

```swift
// Sources/Zinc/MarkdownPreviewStore.swift
func document(for clip: Clip) -> MarkdownDocument {
    ...
    let fallback = MarkdownDocument.fallback(from: clip.text)
    documents[clip.id] = fallback        // @Published mutation
    loadIfNeeded(for: clip)              // side effect
    return fallback
}
```

**Proposed fix**
Split reading from loading. Make `document(for:)` a pure lookup that returns an optional or a computed fallback without
touching state, and drive loading from `onAppear`/`task` and from explicit list-change events instead of from body. Mark
the store `@MainActor` so the threading contract is enforced by the compiler rather than by convention.

**Acceptance criteria**

- [ ] No "Publishing changes from within view updates" warning appears while scrolling or searching.
- [ ] Reading a preview document has no side effects.
- [ ] Loads are triggered by lifecycle events, not by body evaluation.
- [ ] The store is `@MainActor` and its background work is explicitly hopped.

---

### ZINC-025

**The whole index is re-encoded and rewritten on every mutation; no size cap or retention**

- **Area:** Storage · **Type:** Performance · **Severity:** P1 · **Effort:** M · **Depends on:** ZINC-002

**Problem**
Every `add`, `remove`, `clear`, and `setMarkdownPath` re-encodes the entire clip array — pretty-printed with sorted keys —
and writes the whole file synchronously on the main thread. Cost grows linearly with history size, and since
`setMarkdownPath` fires once per export, each capture pays it twice. There is no cap on how much text a single clip can
hold, so selecting a very large document embeds all of it in `clips.json` and then re-serializes it on every subsequent
capture forever. There is no retention policy, no maximum clip count, and no way to trim old history, so this only gets
worse with use — an app designed to run for years has an unbounded, ever-slowing write path.

Storing the full text in the index is also redundant, since the vault already holds the content.

**Evidence**

```swift
// Sources/Zinc/ClipStore.swift
encoder.outputFormatting = [.prettyPrinted, .sortedKeys]   // largest possible encoding
...
private func save() {
    let data = try encoder.encode(clips)                   // entire history, main thread, every mutation
```

**Proposed fix**
Stop treating the index as a single blob. Either move to SQLite (via GRDB or the built-in C API) for incremental writes
and indexed search, or keep JSON but debounce and coalesce writes onto a background queue and store only a bounded
preview per clip rather than the full text, reading full content from the vault on demand. Add a retention setting (max
count and/or max age) and a per-clip size cap with explicit truncation reflected in the UI. **Needs product decision:**
SQLite is the better long-term answer but is a larger change and adds a dependency; a bounded-JSON approach is cheaper
and may be enough.

**Acceptance criteria**

- [ ] Capture latency does not grow measurably with history size (verified at 10, 1,000, and 10,000 clips).
- [ ] Index writes never block the main thread.
- [ ] A single very large selection does not inflate every subsequent write.
- [ ] Retention limits exist and are configurable.
- [ ] Full clip text is read from the vault rather than duplicated in the index, or is explicitly bounded.

---

### ZINC-026

**Accessibility permission is polled once a second for the life of the process**

- **Area:** Performance · **Type:** Enhancement · **Severity:** P2 · **Effort:** S

**Problem**
`startAccessibilityPolling` schedules a 1 Hz timer that never stops, calling `AXIsProcessTrusted()` forever. Permission
changes at most a handful of times in an app's entire lifetime, so this is 86,400 pointless wakeups a day in a background
utility, preventing App Nap from doing its job and costing battery for nothing.

**Evidence**

```swift
// Sources/Zinc/ShiftShiftMonitor.swift
accessibilityPollTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { ... }
```

**Proposed fix**
Poll at 1 Hz only while the permission alert is up and the app is waiting for a grant, then stop. Re-check on the events
that can plausibly correlate with a change — app activation, `NSWorkspace.didActivateApplicationNotification`, wake from
sleep — and fall back to a slow (30 s+) poll if a cheap notification-based approach proves unreliable.

**Acceptance criteria**

- [ ] No repeating timer runs once permission has been granted.
- [ ] Granting permission while Zinc is running is still detected promptly and still shows the confirmation HUD.
- [ ] Revoking permission is detected within a reasonable window.
- [ ] Idle CPU wakeups measurably drop.

---

### ZINC-027

**Parsed preview documents accumulate in memory without bound**

- **Area:** Performance · **Type:** Bug · **Severity:** P2 · **Effort:** S

**Problem**
`MarkdownPreviewStore` keeps two stores with different lifetimes: an `NSCache` correctly capped at 100 entries, and a
plain `documents` dictionary with no cap that is only ever cleared by `invalidate` or `clear`. Every clip the user scrolls
past is parsed into `Block` values and retained in that dictionary for the rest of the session, so browsing a large
history grows memory monotonically. `loadGeneration` has the same problem, accumulating an entry per clip ever loaded.

**Evidence**

```swift
// Sources/Zinc/MarkdownPreviewStore.swift
private let cache = NSCache<NSString, MarkdownDocumentBox>()   // capped at 100
@Published private(set) var documents: [UUID: MarkdownDocument] = [:]   // never capped
private var loadGeneration: [UUID: Int] = [:]                  // never pruned
```

**Proposed fix**
Keep one store. Publish a bounded LRU keyed by clip ID and let eviction be the only removal path, or drop `documents`
entirely and expose the `NSCache` through a published revision counter. Prune `loadGeneration` alongside eviction.

**Acceptance criteria**

- [ ] Scrolling through 5,000 clips does not grow resident memory without bound.
- [ ] There is a single source of truth for cached preview documents.
- [ ] Generation tracking is bounded.

---

## P2 — Product gaps and UX

### ZINC-028

**No "Launch at login" — a menu bar utility that must be started by hand every boot**

- **Area:** Product · **Type:** Enhancement · **Severity:** P1 · **Effort:** S

**Problem**
Zinc's value comes entirely from always being there to catch a selection. There is no login-item support anywhere in the
codebase, so after every restart the user has to remember to launch it — and the failure is silent, because double-Shift
simply does nothing. This is the single highest-value-per-line item in the review: a menu bar capture tool that isn't
running at login is a capture tool that misses captures.

**Evidence**
No reference to `SMAppService`, `LSSharedFileList`, or a login-item helper exists in `Sources/Zinc`.

**Proposed fix**
Use `SMAppService.mainApp` (macOS 13+, and Zinc already requires 14) with a toggle in Settings that reflects the real
registration status, including the case where the user has disabled the item in System Settings. Consider enabling it on
first launch after the Accessibility grant succeeds, with an explicit prompt rather than silently.

**Acceptance criteria**

- [ ] A "Launch at login" toggle exists in Settings and survives relaunch.
- [ ] The toggle reflects the true system state, including external changes.
- [ ] Zinc starts automatically after a reboot when enabled.
- [ ] Registration failures are surfaced rather than silently ignored.

---

### ZINC-029

**Copy returns the plain-text index snapshot, so image clips paste the literal text `[Image]`**

- **Area:** Product · **Type:** Bug · **Severity:** P1 · **Effort:** M

**Problem**
Everything the panel copies comes from `clip.text`, which is the plain-text index snapshot taken at capture time. For a
selection that was image-only or rich-content-only, `RichSelection.clipText` stores the placeholder strings
`"[Image]"` and `"[Rich content]"` — so pressing Return on such a clip puts the literal five- or fifteen-character string
on the clipboard. The user sees a rendered image in the preview, presses Return, and pastes the word `[Image]`.

Even for ordinary text clips this is a missed opportunity: the whole point of the app is that it produced a nicely
converted Markdown file, and there is no way to copy that. Multi-select joins with a single `\n`, which runs Markdown
blocks together. There is no "Copy as Markdown", no "Copy as rich text", and no way to get the image itself back onto the
clipboard.

**Evidence**

```swift
// Sources/Zinc/RichSelection.swift
if html != nil { return "[Rich content]" }
if !images.isEmpty { return "[Image]" }
```

```swift
// Sources/Zinc/ClipPanel.swift
NSPasteboard.general.setString(texts.joined(separator: "\n"), forType: .string)
```

**Proposed fix**
Copy from the exported Markdown file when it exists, falling back to the index text only when it does not. Write multiple
flavors to the pasteboard — Markdown as plain text plus the image data for image clips, and optionally HTML/RTF for
paste-into-rich-editor cases. Add explicit "Copy as Markdown" and "Copy as Plain Text" commands with distinct shortcuts,
and join multi-selections with a blank line. Never put a placeholder string on the clipboard.

**Acceptance criteria**

- [ ] Copying an image-only clip puts the image on the clipboard, not the text `[Image]`.
- [ ] Copying a rich clip yields its Markdown, not `[Rich content]`.
- [ ] Distinct commands exist for Markdown and plain text, both discoverable in the shortcuts footer.
- [ ] Multi-clip copies are separated by a blank line so Markdown blocks stay distinct.

---

### ZINC-030

**The documented Delete shortcut does nothing, and Cmd+C detection is layout-dependent**

- **Area:** Shortcuts · **Type:** Bug · **Severity:** P1 · **Effort:** S

**Problem**
Three related keyboard problems in `handleKeyEvent`:

- The README's shortcut table says `Delete` deletes a clip, but the handler requires Cmd+Delete and passes a plain Delete
  through to the search field. The in-app footer hint correctly shows `⌘⌫`, so the app contradicts its own documentation.
  (The code's choice matches macOS convention and is the right one — the README is what should change.)
- Cmd+C is matched with `event.keyCode == 8`, the physical position of `C` on ANSI QWERTY. On Dvorak, AZERTY, Colemak, or
  any non-QWERTY layout, that key is not `C`, so Cmd+C stops copying and some unrelated key starts copying instead.
- Every key is a bare magic number (`125`, `126`, `36`, `76`, `53`, `48`, `49`, `51`, `117`, `8`) with only inline
  comments, in a method that is already the app's densest branch.

**Evidence**

```swift
// Sources/Zinc/ClipPanel.swift
case 8: // C
    if mods.contains(.command) { ... }
```

**Proposed fix**
Match character-based shortcuts on `charactersIgnoringModifiers` and reserve key codes for physical keys that have no
character (arrows, Escape, Tab, Return, Delete). Replace the magic numbers with named constants or a `KeyCode` enum. Fix
the README table to match the implementation.

**Acceptance criteria**

- [ ] Cmd+C copies on Dvorak and AZERTY layouts.
- [ ] The README shortcut table matches actual behaviour, including Cmd+Delete.
- [ ] No bare numeric key codes remain in `handleKeyEvent`.
- [ ] Unit tests cover the key-handling decision table.

---

### ZINC-031

**The panel is not resizable and forgets its size and position**

- **Area:** Product · **Type:** Enhancement · **Severity:** P2 · **Effort:** S

**Problem**
The panel is hardcoded to 900×560 with a 320 pt list column, and its style mask omits `.resizable`, so a user on a 13"
laptop gets a window that dominates the screen while a user on a 32" display gets a small box with a cramped preview of
long clips. `isMovableByWindowBackground` is enabled, inviting the user to drag the panel — but `openPanel` recenters it
on every open, so moving it accomplishes nothing. The 900×560 size is also duplicated in three places (the panel rect,
the hosting view frame, and Settings' own frame), so changing it means changing several literals.

**Evidence**

```swift
// Sources/Zinc/ClipPanel.swift
contentRect: NSRect(x: 0, y: 0, width: 900, height: 560),
styleMask: [.titled, .fullSizeContentView, .closable],   // no .resizable
...
panel.setFrame(NSRect(origin: origin, size: panelSize), display: true)   // recenters every open
```

**Proposed fix**
Make the panel resizable with sensible minimum and maximum sizes, persist its frame with `setFrameAutosaveName` or in
`UserDefaults`, and make the list/detail divider draggable and persistent. Open on the screen containing the mouse rather
than `NSScreen.main`, which is more predictable on multi-display setups. Define the default size once.

**Acceptance criteria**

- [ ] The panel can be resized and the size persists across launches.
- [ ] A moved panel reopens where the user left it.
- [ ] The list/detail split is adjustable and remembered.
- [ ] The panel opens on the display the user is working on.

---

### ZINC-032

**No undo for delete or Clear All Clips**

- **Area:** Product · **Type:** Enhancement · **Severity:** P2 · **Effort:** M

**Problem**
Cmd+Delete removes clips immediately with no undo and no confirmation. The Markdown files go to the Trash and are
recoverable from there, but the index entries are gone permanently, so recovering means manually re-importing files Zinc
has no import path for (see ZINC-039). "Clear All Clips" at least confirms, but it sits in the same menu group as the
innocuous "Open Accessibility Settings", making a destructive, irreversible action one slip away from a routine one.

**Evidence**

```swift
// Sources/Zinc/ClipStore.swift
func remove(ids: Set<UUID>) {
    ...
    clips.removeAll { ids.contains($0.id) }   // no undo record
```

```swift
// Sources/Zinc/AppDelegate.swift
menu.addItem(withTitle: "Clear All Clips", ...)
menu.addItem(withTitle: "Open Accessibility Settings", ...)   // same group
```

**Proposed fix**
Register deletions with an `UndoManager` (or keep a small in-memory undo stack) so Cmd+Z restores the index entries and
pulls the files back from the Trash. Show a transient "Deleted — Undo" affordance in the panel. Move "Clear All Clips"
into its own group away from navigation items, and require typed confirmation or an explicit checkbox for it.

**Acceptance criteria**

- [ ] Cmd+Z after a delete restores both the index entries and the vault files.
- [ ] The panel offers a visible undo affordance after a delete.
- [ ] "Clear All Clips" is visually separated from non-destructive menu items.
- [ ] Clearing everything requires a deliberate confirmation.

---

### ZINC-033

**A missing Accessibility grant is invisible — Zinc looks healthy but does nothing**

- **Area:** Product · **Type:** Enhancement · **Severity:** P1 · **Effort:** S

**Problem**
Without Accessibility permission, `installMonitorsIfPossible` returns early and double-Shift never fires. The only signal
the user gets is a one-time alert at launch, which is easy to dismiss and impossible to get back — after that, the menu
bar icon looks identical, the tooltip still reports a clip count, the menu shows no status, and the panel's empty state
cheerfully says "Double-tap Shift to save a selection" while double-Shift is inert. A new user who dismisses that alert
has no path to discovering why the app does nothing.

**Evidence**

```swift
// Sources/Zinc/ShiftShiftMonitor.swift
guard Permissions.isAccessibilityTrusted else {
    isMonitoring = false
    ZincLog.write("Accessibility not trusted — Shift monitor deferred")   // only visible in a log file
    return
}
```

```swift
// Sources/Zinc/ClipListView.swift
Text("Double-tap Shift to save a selection")   // shown even when the trigger cannot fire
```

**Proposed fix**
Reflect monitoring state in the UI: a badged or dimmed menu bar icon, a non-clickable status line at the top of the menu
("Double-Shift inactive — Accessibility permission needed") above a prominent fix action, and an empty-state that explains
the missing permission with a button instead of instructions that cannot work. Publish the monitor's state so the views
can observe it rather than inferring it.

**Acceptance criteria**

- [ ] The menu bar icon visibly differs when double-Shift cannot fire.
- [ ] The menu states the permission problem and offers the fix.
- [ ] The panel's empty state explains the missing permission instead of giving unusable instructions.
- [ ] The state updates live when permission is granted or revoked.

---

### ZINC-034

**No way to organize clips: no pins, tags, notes, editing, or filters**

- **Area:** Product · **Type:** Enhancement · **Severity:** P2 · **Effort:** L · **Needs product decision**

**Problem**
Zinc is currently write-only: clips arrive, and the only operations are search, copy, and delete. A `Clip` has no
favorite, pin, tag, or note field; there is no way to correct a bad capture or annotate why something was saved; and the
panel offers no filtering beyond free-text search — no filter by source app, no filter by content type (even though
`contentTypeLabel` already computes one and shows it on every row), no date grouping, and no sort options. For a tool
whose stated aim is a personal knowledge vault, the retrieval side is much thinner than the capture side, and it is what
will determine whether people keep using it after the first week.

**Evidence**
`Clip` has exactly `id`, `text`, `savedAt`, `appName`, `bundleID`, `pageURL`, `pageTitle`, `markdownPath`.
`ClipPanelViewModel.filteredClips` supports only substring search.

**Proposed fix**
Scope this deliberately rather than building all of it. The highest-value increments, roughly in order: (1) pin/favorite
with pinned clips sorted first; (2) filter chips for source app and content type, driven by data already present;
(3) date section headers in the list; (4) tags, written into the front matter's `tags:` field so Obsidian sees them too;
(5) inline note or title editing that writes back to the Markdown file. Each needs a schema migration story (ZINC-002)
and a decision about the Markdown file being the source of truth versus the index.

**Acceptance criteria**

- [ ] A prioritized, sliced plan exists before implementation begins.
- [ ] Pinned clips sort above others and survive relaunch.
- [ ] Filtering by source app and content type is possible without typing a query.
- [ ] Any new field is written into the vault Markdown, not only the index.

---

### ZINC-035

**The save HUD is not configurable and its Cmd+Click action is undiscoverable**

- **Area:** Product · **Type:** Enhancement · **Severity:** P2 · **Effort:** S

**Problem**
Every capture plays a Tink sound and animates a pill at the bottom-centre of the main screen for 2.4 s. None of it is
configurable: no way to mute the sound, move or reposition the HUD, shorten the display, or turn it off for users who
find a per-capture animation intrusive. The HUD hides a genuinely nice feature — Cmd+Click on the pill opens that clip in
the panel — but nothing in the HUD, the menu, or the README mentions it, so effectively nobody will find it. The
expand animation also runs regardless of the user's Reduce Motion setting, and each HUD installs a global mouse monitor
for its lifetime.

**Evidence**

```swift
// Sources/Zinc/SaveHUD.swift
if playSound { NSSound(named: "Tink")?.play() }        // unconditional
let hold: TimeInterval = shouldExpand ? 2.4 : 1.5      // hardcoded
/// Pill stays click-through (`ignoresMouseEvents`); Cmd+Click is detected globally.
```

**Proposed fix**
Add Settings controls for sound, HUD enable/disable, screen corner, and duration. Show a small hint glyph in the pill for
the Cmd+Click action and document it in the README. Respect `NSWorkspace.shared.accessibilityDisplayShouldReduceMotion`
by cross-fading instead of animating width.

**Acceptance criteria**

- [ ] Sound and HUD can each be disabled independently.
- [ ] HUD position and duration are configurable.
- [ ] The Cmd+Click action is discoverable in the UI and documented.
- [ ] Reduce Motion suppresses the expand animation.

---

### ZINC-036

**"About Zinc" is a dead menu item**

- **Area:** Product · **Type:** Bug · **Severity:** P2 · **Effort:** S

**Problem**
The app menu's "About Zinc" item is created with `action: nil`, so AppKit renders it permanently disabled. There is also
no version anywhere in the UI, which makes bug reports harder than they need to be — `CFBundleShortVersionString` is
hardcoded to `1.0.0` in `Info.plist` and never surfaced or bumped.

**Evidence**

```swift
// Sources/Zinc/AppDelegate.swift
appMenu.addItem(withTitle: "About Zinc", action: nil, keyEquivalent: "")
```

**Proposed fix**
Wire it to `NSApplication.orderFrontStandardAboutPanel(_:)` and populate the panel with version, build, and a link to the
repository. Derive the version from the bundle rather than hardcoding it in a second place.

**Acceptance criteria**

- [ ] "About Zinc" is enabled and opens a panel showing version and build.
- [ ] The version shown comes from the bundle.
- [ ] The menu item is reachable from the status item menu as well as the app menu.

---

### ZINC-037

**No automation surface: no App Intents, URL scheme, or Spotlight indexing**

- **Area:** Product · **Type:** Enhancement · **Severity:** P2 · **Effort:** M

**Problem**
Zinc is a closed box. There is no App Intents / Shortcuts support, so a capture can't be triggered from an automation or
a Stream Deck and clips can't feed another workflow; no URL scheme, so nothing can link to a specific clip; and no
CoreSpotlight indexing, so the vault is invisible to system-wide search even though its content is plain Markdown sitting
in the user's home folder. For a keyboard-driven utility aimed at power users, these are the integrations that make it
part of someone's setup rather than another window to visit.

**Evidence**
No `AppIntent`, `CSSearchableItem`, or `CFBundleURLTypes` reference exists in the repo.

**Proposed fix**
Add App Intents for "Save Selection", "Search Clips", and "Get Latest Clip" so Shortcuts and Spotlight can drive Zinc.
Register a `zinc://clip/<uuid>` URL scheme and use it for deep links. Index clips with CoreSpotlight so system search
surfaces them, taking care to honour whatever exclusions ZINC-007 establishes.

**Acceptance criteria**

- [ ] Save, search, and fetch-latest are available as Shortcuts actions.
- [ ] `zinc://clip/<uuid>` opens the panel with that clip selected.
- [ ] Clips appear in Spotlight results and open in Zinc.
- [ ] Concealed or excluded content is never indexed.

---

### ZINC-038

**Arrow-key navigation wraps around, which breaks Shift-range selection**

- **Area:** Product · **Type:** Bug · **Severity:** P2 · **Effort:** S

**Problem**
`moveFocus` advances the index modulo the list count, so Down on the last row jumps to the first and Up on the first jumps
to the last. No macOS list behaves this way, and it interacts badly with range selection: Shift+Down at the bottom wraps
the focus to index 0 and `selectRange` then selects the entire list, which is a surprising way to lose your selection —
and a dangerous one given that delete has no undo (ZINC-032).

**Evidence**

```swift
// Sources/Zinc/ClipPanel.swift
focusedIndex = (focusedIndex + delta + clips.count) % clips.count
```

**Proposed fix**
Clamp instead of wrapping, and treat Home/End (or Cmd+Up/Cmd+Down) as the jump-to-edge gesture.

**Acceptance criteria**

- [ ] Down on the last row keeps focus on the last row.
- [ ] Shift+Down at the bottom does not select the whole list.
- [ ] Cmd+Up and Cmd+Down jump to first and last.

---

### ZINC-039

**No vault reindex, export, or import**

- **Area:** Product · **Type:** Enhancement · **Severity:** P2 · **Effort:** M · **Depends on:** ZINC-002

**Problem**
The vault and the index can diverge, and nothing can reconcile them. Markdown files carry an `id` in their front matter
and everything needed to reconstruct a `Clip`, but there is no code path that reads the vault to rebuild the index — so
a lost or corrupted `clips.json` (ZINC-002), a restored backup, a vault moved by hand, or a file edited in Obsidian all
leave Zinc's view permanently out of step with the truth on disk. There is also no bulk export and no import, which
makes migrating between machines a manual copy plus a permanent loss of history.

**Evidence**
`MarkdownExporter.buildDocument` writes `id`, `app`, `bundle`, `url`, `title`, `saved` — everything `Clip` needs. Nothing
reads it back: `MarkdownDocument.parse` is only used for previews and its `frontMatter` dictionary is never consulted for
reconstruction.

**Proposed fix**
Add "Reindex from Vault…", which walks the vault, parses front matter, and rebuilds the index — merging with the existing
one by `id` rather than replacing it. Offer it automatically after a corrupt-index recovery. Add export (zip of the vault
plus index) and import. Consider watching the vault with `FSEvents` so external edits are picked up live.

**Acceptance criteria**

- [ ] Deleting `clips.json` and reindexing restores the full history with correct metadata.
- [ ] Reindexing merges rather than clobbers, and is idempotent.
- [ ] Export produces an archive that import restores faithfully.
- [ ] Files edited externally are reflected in the panel, or the limitation is documented.

---

## P2 — Accessibility and internationalization

### ZINC-040

**The clip panel is effectively unusable with VoiceOver**

- **Area:** Accessibility · **Type:** Bug · **Severity:** P2 · **Effort:** M

**Problem**
The panel is built from `HStack`/`VStack` with `onTapGesture` rather than from accessible controls, so VoiceOver has
almost nothing to work with. Rows aren't buttons and expose no label, value, or selected state; the keyboard-focused row
is styled with a background colour but carries no accessibility focus, so VoiceOver's cursor and Zinc's focus are
unrelated; `KeyCap` renders bare glyphs like `⌘` and `⌫` with no spoken equivalent; the checkmark that indicates
selection has no label; and neither the search field nor the empty state announces the result count when filtering. A
keyboard-first utility being inaccessible to keyboard-dependent users is a particularly unfortunate combination.

**Evidence**

```swift
// Sources/Zinc/ClipListView.swift
ClipRowView(...)
    .contentShape(Rectangle())
    .onTapGesture(count: 2) { ... }
    .onTapGesture(count: 1) { ... }   // no accessibility element, label, traits, or selected state
```

**Proposed fix**
Make each row a single accessibility element with a composed label (content preview, source, relative time), the
`isSelected` trait, and a custom action for copy and delete. Keep VoiceOver focus in sync with `focusedIndex`. Give
`KeyCap` an `accessibilityLabel` spelling out the key. Announce filtered result counts. Audit the whole panel with
VoiceOver and Accessibility Inspector.

**Acceptance criteria**

- [ ] Every row is one focusable element with a meaningful spoken label and selection state.
- [ ] Keyboard focus and VoiceOver focus stay in sync.
- [ ] Modifier glyphs are announced as words.
- [ ] Search result counts are announced.
- [ ] Accessibility Inspector reports no errors for the panel or Settings.

---

### ZINC-041

**No localization, and text size and motion preferences are ignored**

- **Area:** i18n · **Type:** Enhancement · **Severity:** P2 · **Effort:** M

**Problem**
Every user-facing string in the app is a hardcoded English literal — menu titles, HUD text, the permission alert with its
numbered instructions, Settings labels and help text, empty states, and shortcut hints. There is no string catalog and no
localizable resource of any kind, so Zinc cannot be translated without touching every file. `SavedAtFormat` is a near
miss: it correctly uses `RelativeDateTimeFormatter` for the relative parts, then hardcodes `"now"` in English. Font sizes
are given as fixed point values (`.system(size: 16)`, `size: 13`, `size: 11`) rather than text styles, so they don't
respond to accessibility text-size settings, and the HUD animates regardless of Reduce Motion.

**Evidence**

```swift
// Sources/Zinc/SavedAtFormat.swift
if elapsed < minute { return "now" }         // untranslated
```

```swift
// Sources/Zinc/ClipListView.swift
.font(.system(size: 16))                     // fixed, ignores text-size preference
```

**Proposed fix**
Move all user-facing strings into a String Catalog and reference them through `LocalizedStringResource` /
`LocalizedStringKey`. Replace fixed sizes with relative or text-style-based fonts. Respect Reduce Motion. Localizing to a
second language isn't the immediate goal — being *able* to is, and the mechanical work only gets more expensive as the
app grows.

**Acceptance criteria**

- [ ] No user-facing English literal remains outside the string catalog.
- [ ] `"now"` and every other date string is localized.
- [ ] The UI remains usable at the largest accessibility text size.
- [ ] Reduce Motion is honoured.

---

## P2 — Architecture, testing, and tooling

### ZINC-042

**There is no test target — the trickiest logic in the app is untested**

- **Area:** Testing · **Type:** Enhancement · **Severity:** P1 · **Effort:** M

**Problem**
`Package.swift` declares a single executable target and nothing else. There are no tests of any kind. That matters more
than usual here, because the app's hardest logic is also its most testable and its most bug-prone: the double-Shift state
machine in `ShiftShiftMonitor` (a hand-rolled state machine over `armedUntil`, `secondPressStarted`, `contaminated`,
`previousShiftDown`, and hold duration, with at least eight interacting branches), `HTMLToMarkdown`, `MarkdownDocument`,
`SavedAtFormat`, the YAML emitter, and the vault path-containment check that ZINC-005 shows is currently wrong. Most of
those are pure functions on plain values. The absence of tests is why several bugs in this review could sit undetected,
and it makes every fix below riskier than it needs to be.

**Evidence**

```swift
// Package.swift
targets: [
    .executableTarget(name: "Zinc", path: "Sources/Zinc"),
]   // no .testTarget
```

**Proposed fix**
Split the pure logic into a `ZincCore` library target that the executable depends on, and add a `ZincCoreTests` target
using swift-testing. Cover, in priority order: the Shift state machine (as a pure reducer over synthetic events, which
requires extracting it from `NSEvent`), `HTMLToMarkdown` with snapshot fixtures of real captured HTML, YAML
emit/parse round-tripping, vault path containment including the adversarial cases, `MarkdownDocument.parse`,
`SavedAtFormat` across locales, and the key-handling decision table. Make `swift test` the gate in CI (ZINC-046).

**Acceptance criteria**

- [ ] A library target holds the pure logic and a test target exercises it.
- [ ] The Shift state machine is testable without `NSEvent` and has tests for arm, cancel, contamination, hold-too-long,
      mouse-down, exclusion, and successful double-tap.
- [ ] Every bug fixed elsewhere in this review has a regression test.
- [ ] `swift test` passes locally and in CI.

---

### ZINC-043

**Singletons throughout leave no seams for testing**

- **Area:** Architecture · **Type:** Refactor · **Severity:** P2 · **Effort:** L · **Depends on:** ZINC-042

**Problem**
`ClipStore.shared`, `MarkdownPreviewStore.shared`, `MarkdownExporter.shared`, `ShiftFilterSettings.shared`,
`ClipPanelController.shared`, `SettingsWindowController.shared`, plus `SaveHUD`, `Permissions`, `VaultSettings`, and
`VaultFileManager` as namespaces of static state and static mutable vars. Collaborators are reached through globals rather
than passed in, so nothing can be constructed in isolation: `ClipPanelViewModel.handleKeyEvent` reaches for
`ClipStore.shared` even though a store is passed to the methods it calls, `MarkdownExporter` writes back into `ClipStore`
which calls into `MarkdownPreviewStore` (a cycle), and `MarkdownPreviewStore.loadIfNeeded` reads `ClipStore.shared` to
re-look-up the clip it was handed. Beyond testability, the static mutable state in `SaveHUD` and `Permissions` is exactly
what Swift 6 strict concurrency rejects, so this blocks ZINC-045 too.

**Evidence**

```swift
// Sources/Zinc/MarkdownPreviewStore.swift
let latest = ClipStore.shared.clips.first(where: { $0.id == clipID }) ?? clip   // reaches around its own parameter
```

```swift
// Sources/Zinc/SaveHUD.swift
private static var hudWindow: NSWindow?          // static mutable state
private static var dismissWorkItem: DispatchWorkItem?
```

**Proposed fix**
Do this incrementally, behind the tests from ZINC-042. Define protocols for the store, exporter, and settings; inject
them through initializers; keep one composition root in `AppDelegate` that wires the graph and holds the only long-lived
references. Break the store/exporter cycle by having the exporter report completion through a callback or async return
rather than calling back into the store. Convert `SaveHUD` into an instance owned by that root. Do not attempt this as one
change.

**Acceptance criteria**

- [ ] The clip store, exporter, and settings are reachable through protocols and injected.
- [ ] No type reads a `.shared` singleton that it could have been given.
- [ ] The exporter no longer calls back into the store directly.
- [ ] `SaveHUD` holds no static mutable state.
- [ ] Tests construct the full graph with in-memory doubles.

---

### ZINC-044

**Duplicated helpers and dead parameters**

- **Area:** Architecture · **Type:** Refactor · **Severity:** P2 · **Effort:** S

**Problem**
Small things that add friction out of proportion to their size:

- `appIcon(for:)` is implemented three times, identically, in `ClipListView`, `ClipDetailView`, and `ShiftFilterSettings`
  (see ZINC-022, which needs one cached implementation anyway).
- The debug-log writer is implemented twice, in `ShiftShiftMonitor.ZincLog` and `Permissions.log` (see ZINC-012).
- `attributedInline(_:)` is duplicated in `ClipListView` and `MarkdownPreviewView`.
- `ClipPanelViewModel.copySelectedAndClose(from store: ClipStore, clips:)` never uses `store`.
- `SaveHUD.show(text:source:clipID:)` takes `source` as `_` and discards it, so `contextLabel` is computed at every call
  site for nothing.
- In `ClipStore.remove`, `let removed = clips.count` is taken *before* removal, so the name means the opposite of what it
  says and the guard below reads as a contradiction.
- The 900×560 panel size is repeated in three literals (ZINC-031).

**Proposed fix**
Extract the shared helpers, delete the unused parameters, rename `removed` to `previousCount`. Mechanical, low-risk, and
best done as one small pass — ideally before the larger refactors so they start from a smaller surface.

**Acceptance criteria**

- [ ] One implementation each of icon lookup, logging, and inline-markdown attribution.
- [ ] No unused parameters remain in the panel view model or the HUD.
- [ ] Misleading local names are corrected.
- [ ] No behaviour changes.

---

### ZINC-045

**Swift language mode drift and deprecated API usage**

- **Area:** Tooling · **Type:** Refactor · **Severity:** P2 · **Effort:** M · **Depends on:** ZINC-043

**Problem**
`Package.swift` declares `swift-tools-version: 5.9` while the README tells contributors they need Swift 6.x, so the
package builds in Swift 5 language mode with concurrency checking effectively off. That is why the data race in
`ContextResolver` (ZINC-009), the static mutable state in `SaveHUD` and `Permissions`, and the cross-thread
`@Published` mutations elsewhere all compile without complaint. There are no upcoming-feature flags, no
`-warnings-as-errors`, and no `@MainActor` annotations on the UI-owning types, which are all main-thread-only by
convention and unenforced. `MarkdownPreviewStore` also calls `String(contentsOfFile:encoding:)`, deprecated in the
macOS 15 SDK.

**Evidence**

```swift
// Package.swift
// swift-tools-version: 5.9      // README says Swift 6.x
```

```swift
// Sources/Zinc/MarkdownPreviewStore.swift
let contents = try? String(contentsOfFile: path, encoding: .utf8)   // deprecated
```

**Proposed fix**
Move to tools version 6.x with `swiftLanguageMode(.v6)`, then fix the concurrency diagnostics it produces — which is
mostly annotating the UI and store types `@MainActor` and removing the static mutable state (ZINC-043). Turn on
`-warnings-as-errors` in CI once the tree is clean. Replace deprecated APIs. Expect this to surface real bugs rather than
just noise.

**Acceptance criteria**

- [ ] The package builds cleanly in Swift 6 language mode.
- [ ] No `@unchecked Sendable` or concurrency suppression is used to paper over a real race.
- [ ] The README's stated toolchain matches `Package.swift`.
- [ ] No deprecated API warnings remain.

---

### ZINC-046

**No CI, linter, or formatter**

- **Area:** Tooling · **Type:** Enhancement · **Severity:** P2 · **Effort:** S · **Depends on:** ZINC-042

**Problem**
There is no `.github/` directory, so nothing builds or checks anything on a push, and any regression reaches `main`
unnoticed. There is no SwiftLint or swift-format configuration either, so style is maintained by hand — the existing code
is consistent, which is worth locking in mechanically before more hands touch it.

**Proposed fix**
Add a GitHub Actions workflow on `macos-latest` that runs `swift build`, `swift test`, and a lint step, and make it
required. Add `.swiftformat`/`.swiftlint.yml` matching current conventions. Optionally have CI run `scripts/bundle.sh` to
verify the app bundle still assembles.

**Acceptance criteria**

- [ ] Every push and PR builds and tests on macOS.
- [ ] Lint and format checks run in CI and pass on the current tree.
- [ ] The bundling script is exercised by CI.
- [ ] A failing test fails the build.

---

### ZINC-047

**No LICENSE, CONTRIBUTING, or changelog**

- **Area:** Repo hygiene · **Type:** Enhancement · **Severity:** P2 · **Effort:** S

**Problem**
The repository has no LICENSE file, which legally means all rights reserved and leaves anyone who finds the project unable
to use, fork, or contribute to it with confidence. There is no CONTRIBUTING guide, no issue or PR templates, no
CHANGELOG, and no release tags — `CFBundleShortVersionString` is a hardcoded `1.0.0` and `CFBundleVersion` a hardcoded
`1`, neither of which has moved across the two commits in the history.

**Proposed fix**
Add a LICENSE (**Needs product decision:** MIT is the conventional choice for a tool like this, but that is the owner's
call), a short CONTRIBUTING covering build, test, and signing setup, and a CHANGELOG. Derive the marketing version from a
single source and the build number from CI, and tag releases.

**Acceptance criteria**

- [ ] A LICENSE file exists and the README states the license.
- [ ] CONTRIBUTING explains how to build, test, and sign locally.
- [ ] A CHANGELOG exists and version numbers are not hardcoded in two places.

---

### ZINC-048

**No notarized, distributable artifact and no update mechanism**

- **Area:** Build / Release · **Type:** Enhancement · **Severity:** P2 · **Effort:** M · **Depends on:** ZINC-001

**Problem**
`bundle.sh` produces `Zinc.app` in the repository root and stops there. There is no notarization step, no stapling, and
no DMG or zip, so anyone but the author gets a Gatekeeper block and has to right-click-open — for an app that then asks
for Accessibility permission, which is a lot of trust to ask on the back of a security warning. There is no auto-update
mechanism, so shipped copies stay on whatever version they were installed at, and the ad-hoc signing fallback rotates the
CDHash on every rebuild and quietly invalidates the Accessibility grant (the script's own comment acknowledges this, but
the failure is left for the user to discover).

**Evidence**

```bash
# scripts/bundle.sh — ends here
echo "Built $APP"
echo "Run: open $APP"
```

**Proposed fix**
Extend the release path to sign with a Developer ID, notarize with `notarytool`, staple, and package a DMG or zip. Add
Sparkle (or an equivalent) for updates, with an appcast published from CI on tag. Make the ad-hoc fallback print a loud,
specific warning that Accessibility permission will need re-granting after each rebuild. Build the app into a build
directory rather than the repo root.

**Acceptance criteria**

- [ ] A tagged release produces a signed, notarized, stapled artifact that opens without a Gatekeeper warning.
- [ ] `spctl --assess` passes on the produced artifact.
- [ ] Updates can be delivered to installed copies.
- [ ] The ad-hoc fallback warns explicitly about the TCC consequence.
- [ ] Build output does not land in the repository root.

---

### ZINC-049

**README documents behaviour the code does not implement**

- **Area:** Docs · **Type:** Bug · **Severity:** P2 · **Effort:** S

**Problem**
Concrete inaccuracies, each of which will cost a user time:

- The shortcut table lists `Delete` for delete; the code requires Cmd+Delete (ZINC-030).
- "Requirements" says Swift 6.x; `Package.swift` says tools version 5.9 (ZINC-045).
- Cmd+Click on the save HUD to open that clip is not mentioned anywhere (ZINC-035).
- Tab to expand the detail view, Shift+arrow range selection, and Cmd+Click multi-select are all implemented and all
  undocumented.
- "Known Limitations" doesn't mention that remote images are fetched over the network on capture (ZINC-018), that
  Automation permission is silently unavailable in hardened builds (ZINC-001), or which browsers are actually supported
  (ZINC-013).
- Nothing states what Zinc refuses to capture, because currently it refuses nothing (ZINC-007).
- There is no troubleshooting section, though `~/Library/Application Support/Zinc/debug.log` exists and would be the
  first thing to ask a bug reporter for.

**Proposed fix**
Correct the shortcut table and requirements, document the undocumented interactions, add a troubleshooting section
pointing at the log, and expand Known Limitations. Best done last, once the behaviour changes above have landed, so it is
written against the real thing.

**Acceptance criteria**

- [ ] Every shortcut in the README matches the implementation and the in-app footer hints.
- [ ] The stated toolchain matches `Package.swift`.
- [ ] Network behaviour, capture exclusions, and supported browsers are documented.
- [ ] A troubleshooting section exists and names the log file location.

---

## Suggested sequencing

Ordering matters here because several items are prerequisites for doing others safely.

1. **Stop the bleeding.** ZINC-001 (browser URLs are broken in every signed build), ZINC-007 (secrets on disk), ZINC-005
   and ZINC-002 (destructive path handling and silent history loss). These are the items where a shipped build is
   actively harming the user.
2. **Build the safety net.** ZINC-042 (test target) and ZINC-044 (the mechanical cleanup). Everything after this is
   easier and less risky with tests in place, and the Markdown and Shift-monitor work is nearly impossible to do
   confidently without them.
3. **Make failures visible.** ZINC-006 and ZINC-033. Until the app can tell the user something went wrong, every other
   bug looks the same from the outside: nothing happened.
4. **Fix the core loop.** ZINC-003, ZINC-008, ZINC-009, ZINC-010, ZINC-011, and the Markdown fidelity set
   (ZINC-015 through ZINC-020). This is where the app's actual quality lives.
5. **Make it fast and make it stay fast.** ZINC-022, ZINC-023, ZINC-024, ZINC-025, ZINC-012.
6. **Then the product gaps.** ZINC-028 first — it is small and it is the difference between a tool that is always there
   and one that isn't — then ZINC-029, ZINC-030, ZINC-014, and onwards.
7. **Then the long-horizon work.** ZINC-043, ZINC-045, ZINC-034, ZINC-037.

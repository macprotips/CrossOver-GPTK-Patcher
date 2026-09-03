# CrossOver GPTK Patcher

A small macOS utility that puts Apple's Game Porting Toolkit (GPTK) into CrossOver, either as a
patched duplicate or by patching the installed app, and sets up DLSS → MetalFX.

## Using it

1. Drop `CrossOver.app` and the toolkit `.dmg` onto the two tiles. Either tile takes either file,
   and files can also be dropped on the app icon, pasted with ⌘V, or picked with a file chooser.
   The full `Game_Porting_Toolkit_x.dmg` download works directly; the evaluation-environment image
   nested inside it is found automatically.
2. Choose **Duplicate CrossOver** (default) or **Patch Existing**.
3. Click **Patch CrossOver**.

Every toolkit you add is kept in `~/Library/Application Support/GPTKPatcher/Toolkits/<version>/`,
so several versions can be imported and chosen from the menu on the toolkit tile.

Patched apps appear in the **Patched** list. *Reveal in Finder* shows the app; the gear opens its
options, where a D3DMetal frame rate cap, the Metal Performance HUD, and Metal 4 can be set for all
bottles that app launches or for one bottle, and written with *Apply*. Applying to all bottles also
clears those three keys from every bottle's own config, since a bottle's line would otherwise win.

Metal 4 is a three-way choice because of how D3DMetal reads it: the variable is parsed once per
process with `atoi`, and an absent line means the OS default, which is on with GPTK 4 on macOS 27.
*Off* therefore writes `"D3DM_MTL4" = "0"`; *Default* removes the line. If the bottle is still
running, or still has programs left over from a session, the popover says so and offers *Quit
Bottle*, since those programs keep the environment they launched with. Quit Bottle stops the
bottle's wineserver the way CrossOver's own Quit does, then ends anything that survived it,
identified by the files it holds inside the bottle. `--cli --quit-bottle <name>` does the same
from a terminal.

## What patching does

- **Duplicate:** copies CrossOver with an APFS clone (instant, shares storage) and saves it as
  `CrossOver (GPTK x).app` in `/Applications`, or `~/Applications` if that isn't writable. A taken
  name gets a counter; nothing is ever replaced.
- **Patch Existing:** modifies the selected app. It refuses while that CrossOver is running and
  renames the app to `CrossOver (GPTK x).app` afterwards unless that name is taken, and moves it
  into Applications if it was patched somewhere like Downloads. Bottle sessions that app had
  running are ended first, because after the rename they would point at a path that no longer
  exists and every bottle query would hang.
- Replaces the bundled `apple_gptk` folder with the toolkit's, keeping the original as
  `apple_gptk.stock`. A second patch replaces only the previous patch; the stock backup is never
  overwritten. If any step fails, the folder is put back and an unfinished duplicate is deleted.
- Creates `nvngx.dll` and `nvngx.so` copies of the toolkit's `nvngx-on-metalfx` shim. CrossOver's
  loader redirects a game's `nvngx.dll` to that file, so without it DLSS games get no MetalFX.
- Writes `D3DM_ENABLE_METALFX=1` and `DXMT_ENABLE_NVEXT=1` to the app's
  `Contents/SharedSupport/CrossOver/etc/CrossOver.conf`. CrossOver applies that file's
  `[EnvironmentVariables]` to every bottle it launches; a bottle's own `cxbottle.conf` overrides it.
- Makes sure the app being patched has been opened once. macOS verifies a downloaded app the first
  time it opens and a patched bundle can't pass that check, so a never-opened download would be
  reported as "damaged" afterwards (re-signing doesn't help). If needed, the patcher opens the app
  for real, lets it run until it has settled (CrossOver may offer to move itself to Applications;
  that is fine), quits it, and only then patches it. In Duplicate mode this happens to the
  unmodified duplicate, so the patched app is always one macOS has approved. The download record
  is then removed from the bundle: while it remains, macOS runs the app from a hidden translocated
  copy and CrossOver offers to move itself to Applications on every launch.
- Leaves `gptkpatcher-receipt.json` in the app's SharedSupport folder.

## Compatibility

- CrossOver 25/26 (`lib64/apple_gptk`) and CrossOver Preview 27 (`lib/apple_gptk`). The Preview
  also carries `lib/apple_gptk3`, used only by bottles with `CX_GRAPHICS_BACKEND_VERSION=3`; it is
  left alone. The toolkit only serves Intel (x86_64) bottles; the Preview's ARM64 bottles are
  unaffected.
- GPTK evaluation environments 2.1 through 4.0.

## Undo

Delete `apple_gptk` inside the app and rename `apple_gptk.stock` back, or trash the duplicate.
Config edits keep a `.gptkpatcher.bak` next to the file they changed.

## Building

```bash
scripts/build-app.sh && open build/GPTKPatcher.app
```

The SwiftUI macros need a full Xcode toolchain; the script borrows `/Applications/Xcode*.app`
automatically when `xcode-select` points at the bare Command Line Tools. Opening `Package.swift`
in Xcode also works. The bundle is signed ad hoc; distribution outside this Mac needs a Developer
ID signature and notarization, and the app has no custom icon yet.

Headless mode, for scripting and tests:

```bash
build/GPTKPatcher.app/Contents/MacOS/GPTKPatcher --cli /Applications/CrossOver.app \
    ~/Downloads/Game_Porting_Toolkit_4.0.dmg "/Applications/CrossOver (GPTK 4.0).app" \
    [--in-place] [--replace] [--fps 60] [--hud] [--no-copy-env] [--bottle Steam]
```

The toolkit argument may be a `.dmg` (imported into the library first) or an imported version
such as `4.0b2`. With `--in-place` the destination argument is omitted.

Environment variables `GPTKPATCHER_CROSSOVER`, `GPTKPATCHER_DMG`, `GPTKPATCHER_OUTPUT`,
`GPTKPATCHER_PASTE`, `GPTKPATCHER_AUTOPATCH`, `GPTKPATCHER_OPEN_SETTINGS` and
`GPTKPATCHER_SKIP_NOTICE` pre-fill or drive the window for screenshots; they are never persisted.

## Support

A patched CrossOver is not supported by CodeWeavers. The app says so on every launch, and asks
that problems be reproduced with an unmodified CrossOver before contacting their support.

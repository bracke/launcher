# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

`launcher` is a small, keyboard-driven Linux application launcher for Ada 2022: fuzzy-filter installed XDG `.desktop` apps, arrow keys to move, Enter to launch, Escape to quit (`bin/launcher --list` prints discovered apps headlessly). It is the **second consumer** of the sibling `../guikit` toolkit — its reason for existing is partly to keep guikit honest by being a real, different app built on it. See `README.md` for the module tour.

## Build, test, verify

Built with Alire (`alr`).

- `alr build` — compile the app (`bin/launcher`). Style is checked at compile time.
- `alr test` — the AUnit suite in `tests/` (its own crate; compiles the launcher sources minus the GUI main so it can exercise the domain directly). This is pure logic — no GPU.
- `bin/launcher --smoke` — the render gate (needs Vulkan + a display): renders a few frames and confirms via `Guikit.Vulkan` framebuffer readback that the window, search box, results and icon gutter drew, exiting non-zero otherwise. Use this to verify rendering changes, since the AUnit suite can't.
- `tools/bin/release_check` — release-readiness checks (a `tools/` sub-crate built on `project_tools`); run `alr build` inside `tools/` first.

## Reuse guikit first

Most UI capability lives in `../guikit`, not here. Before adding rendering/input/layout code, check whether guikit already provides it: `Guikit.Palette` (fuzzy search), `Guikit.Layout` (palette geometry + hit-testing), `Guikit.Widgets` (panel/input field/palette row), `Guikit.Text` (fonts + glyph atlas), `Guikit.Vulkan` (window hints, event pump, `Ensure_Ready`/`Present_Frame`), `Guikit.Utf8`. This crate should only hold app-specific logic: `Launcher.Applications` (XDG `.desktop` scan + spawn), `Launcher.Icons` (XDG icon-name resolution + PNG/SVG decode via gdk_pixbuf), `Launcher.Model` (state; filtering delegated to `Guikit.Palette`), `Launcher.Fonts`, `Launcher.Render` (frame builder), `Launcher.Main` (GLFW window subclass + input callbacks + main loop).

If something is missing from guikit and is generic to GUI apps, **extract it into guikit** rather than implementing it here.

## Launcher gaps are unimplemented, not intentional

Where the launcher does less than `../files`, treat it as a feature **not yet built**, not a design decision to keep it simpler. Do not use "the launcher does it more simply" to justify leaving shared logic un-extracted or guikit thinner — bring the launcher **up** to files' behavior and share the logic through guikit. (Genuinely bespoke, app-specific overlays are the exception; "files has X, launcher doesn't" is not by itself evidence that X is bespoke.)

## Dependencies

`alire.toml` pins `guikit` → `../guikit` and `textrender` → `../textrender` (relative paths, not published crates); `df_vulkan` / `openglada_glfw` / `utilada` resolve from the Alire index. Builds fail unless those sibling checkouts exist. The linker (`launcher.gpr`, and the test crate) also needs the system `gdk-pixbuf-2.0` / `gobject-2.0` / `glib-2.0` libraries for icon decoding. Locale support (via `i18n`) is planned but not yet added.

## Code style (enforced by the compiler)

Ada 2022 (`-gnat2022`, `-gnatX`), 120-character max line (`-gnatyM120`), UTF-8 source (`-gnatW8`), unused-entity warnings (`-gnatwU`). Match the existing code: **3-space indentation** and **GNATdoc `@param`/`@return` before every new public declaration**. `config/` is Alire-generated — do not hand-edit it.

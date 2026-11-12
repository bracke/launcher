# launcher

A minimal, keyboard-driven application launcher for Linux, built on the
[`guikit`](../guikit) toolkit. Type to fuzzy-filter your installed applications,
arrow keys (or the mouse wheel) to move the selection, **Home**/**End** to jump,
**Enter** to launch, **Escape** to quit. Each result shows the application's icon,
and the applications you launch most float to the top.

It exists mainly as a *second consumer* of guikit — proof that the reusable
pieces extracted from the `files` file manager (fuzzy search, palette layout,
list/input widgets, the Vulkan backend) actually compose into a different app
without re-implementing any of them.

## What it reuses from guikit

- **`Guikit.Command_Palette`** — the whole overlay: fuzzy search and ranking,
  the query field, the result rows with icons, scrolling, and click and wheel
  hit-testing.
- **`Guikit.Text`** — font loading and the glyph atlas (over `Textrender`).
- **`Guikit.Vulkan`** — window surface, swapchain, submission + present.
- **`Guikit.Layout`** / **`Guikit.Utf8`** — text metrics and UTF-8 encoding.

The app itself (this crate) supplies only the domain: scanning XDG `.desktop`
applications (`Launcher.Applications`), resolving + decoding their icons
(`Launcher.Icons`, via gdk_pixbuf), the model + state (`Launcher.Model`),
launch counts that float your most-used applications up (`Launcher.Usage`),
font discovery (`Launcher.Fonts`), the message catalogue (`Launcher.Messages`),
and the window + main loop (`Launcher.Main`).

## Build & run

This repository must be built and validated with Alire GNAT 15. The root, tests,
tools, and release manifests pin `gnat_native = "=15.2.1"`. Confirm with:

```sh
alr exec -- gnatls --version
```

Do not run plain system `gnat*`, `gnatmake`, `gnatls`, `gnatprove`, or
`gprbuild` in this workspace. Use `alr exec -- ...` for compiler and builder
commands so PATH cannot select a different GNAT installation.

```sh
alr build
alr test
alr exec -- gprbuild -P tools/launcher_check.gpr
tools/bin/release_check
bin/launcher              # open the launcher window
bin/launcher --list       # print the discovered applications + icon status, then exit
bin/launcher --smoke      # render a few frames, verify via framebuffer readback, then exit
```

`--smoke` is a headless render gate (needs Vulkan + a display): it renders the app
list, reads back the framebuffer, and confirms the window, search box, results and
the icon gutter each hold ink, exiting non-zero if not.

Requires sibling checkouts of `../guikit` and `../textrender`, a Vulkan driver and
a display, plus the system `gdk-pixbuf-2.0` library (icon loading) — files links
the same library.

## License

MIT OR Apache-2.0 WITH LLVM-exception.

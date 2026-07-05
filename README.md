# launcher

A minimal, keyboard-driven application launcher for Linux, built on the
[`guikit`](../guikit) toolkit. Type to fuzzy-filter your installed applications,
arrow keys to move the selection, **Enter** to launch, **Escape** to quit.

It exists mainly as a *second consumer* of guikit — proof that the reusable
pieces extracted from the `files` file manager (fuzzy search, palette layout,
list/input widgets, the Vulkan backend) actually compose into a different app
without re-implementing any of them.

## What it reuses from guikit

- **`Guikit.Palette`** — the fuzzy search + ranking over the app list.
- **`Guikit.Layout`** — `Calculate_Palette_Layout` / `Calculate_Palette_Result_Rows`
  / `Palette_Result_At` for the overlay geometry and click hit-testing.
- **`Guikit.Widgets`** — `Draw_Menu_Panel`, `Draw_Input_Field`, `Draw_Palette_Row`.
- **`Guikit.Vulkan`** — window surface, swapchain, submission + present.
- **`Guikit.Utf8`** — text measurement.
- **`Textrender`** — font loading + the glyph atlas.

The app itself (this crate) supplies only the domain: scanning XDG `.desktop`
applications (`Launcher.Applications`), the model + state (`Launcher.Model`), the
frame/glyph building (`Launcher.Render`), and the window + main loop
(`Launcher.Main`).

## Build & run

```sh
alr build
bin/launcher              # open the launcher window
bin/launcher --list       # print the discovered applications and exit
```

Requires sibling checkouts of `../guikit` and `../textrender`, plus a Vulkan
driver and a display.

## License

MIT OR Apache-2.0 WITH LLVM-exception.

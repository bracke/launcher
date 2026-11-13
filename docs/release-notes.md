# launcher release notes

All notable changes to the launcher are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/); versions track the Alire crate.

## [Unreleased]

- Desktop entries are read as the Desktop Entry Specification has them:
  string escapes (`\s` `\n` `\t` `\r` `\\`) decoded, `Exec` split into an
  argument vector by its own quoting rules and started by that vector (no
  shell), field codes expanded (`%c` the name, `%i` `--icon <Icon>`, `%k` the
  file; file codes dropped), `TryExec`, `OnlyShowIn`/`NotShowIn` (against
  `XDG_CURRENT_DESKTOP`), `Terminal=true` (run inside the host's terminal, or
  not listed when its way of taking a command is unknown) and `Path=` honoured,
  and subfolders of `applications/` scanned under their desktop-file ids
  (`kde/konsole.desktop` is `kde-konsole.desktop`). The folders come from
  `Hostkit.Fs.Application_Data_Directories`.
- Launch counts are kept per application id (desktop-file id, Start Menu
  place, bundle path), not per display name, so two applications called
  "Terminal" no longer share one; counts from the old name-keyed file carry
  over. The file lives in the host's state place (the application-data folder
  on Windows and macOS, where it was never written before), is replaced
  atomically, and a launch is counted only once it has started.
- A Start Menu shortcut that Windows will not open is reported as a failed
  launch, rather than its path being handed unquoted to a shell.
- The catalogue renders in the host's own language on Windows and macOS when
  no `LANG`/`LC_*` is set (shared `Messages.Program_Catalog`).
- Touchpad scrolling: fractional wheel offsets accumulate into whole steps
  instead of being truncated away.
- A failure to read the host's font folders is reported on standard error,
  and a launcher with no usable font says so and exits non-zero.
- CI runs the release check and the `--smoke` render gate on all three hosts
  (lavapipe software Vulkan, set up as files sets it up).

- Initial launcher: a keyboard-driven application launcher built on the guikit
  toolkit. Fuzzy-filter installed XDG applications, navigate with the arrow keys,
  launch with Enter, quit with Escape.
- Reuses `Guikit.Palette` (search), `Guikit.Layout`, `Guikit.Widgets`,
  `Guikit.Text` and `Guikit.Vulkan`.
- Planned: locale support (translated UI strings via i18n).

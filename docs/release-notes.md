# launcher release notes

All notable changes to the launcher are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/); versions track the Alire crate.

## [Unreleased]

- Initial launcher: a keyboard-driven application launcher built on the guikit
  toolkit. Fuzzy-filter installed XDG applications, navigate with the arrow keys,
  launch with Enter, quit with Escape.
- Reuses `Guikit.Palette` (search), `Guikit.Layout`, `Guikit.Widgets`,
  `Guikit.Text` and `Guikit.Vulkan`.
- Planned: locale support (translated UI strings via i18n).

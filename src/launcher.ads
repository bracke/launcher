with Ada.Strings.Unbounded;

--  Root package for the launcher app: a keyboard-driven application launcher.
--
--  The launcher is, in essence, a searchable list of installed applications:
--  type to fuzzy-filter, arrow keys to move the selection, Enter to spawn the
--  highlighted application, Escape to quit. It is deliberately thin -- the
--  search/ranking, layout, and list/input rendering all come from the reusable
--  guikit toolkit (Guikit.Palette / Guikit.Layout / Guikit.Widgets); this crate
--  supplies only the domain (which applications exist and how to launch them)
--  and the window/main loop.
package Launcher is
   subtype UString is Ada.Strings.Unbounded.Unbounded_String;
end Launcher;

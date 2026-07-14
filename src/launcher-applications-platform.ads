--  How the host itself records the applications it has installed.
--
--  XDG .desktop files are a freedesktop convention: they exist on Linux and on
--  neither Windows nor macOS. Discovery that reads only those finds nothing at all on
--  the other two, which is why the launcher came up empty there -- not because those
--  systems have no applications, but because nobody had asked them.
--
--  Each host is asked in its own terms: the Start Menu on Windows, the application
--  bundles under /Applications on macOS.
package Launcher.Applications.Platform is

   --  The applications this host installs, in its own native form. Empty on Linux,
   --  where the XDG scan in the parent already covers it.
   function Installed_Native return Application_Vectors.Vector;

   --  Start App the way this host starts its own applications, and say whether that
   --  was done. False means the host has no such notion and the shell should be used
   --  -- which is the answer everywhere except Windows.
   --
   --  Windows needs its own way in. A Start Menu entry is a .lnk whose path routinely
   --  contains spaces, so it would have to be quoted to survive a shell -- and a
   --  quoted command line cannot be got to cmd through an argument vector: the C
   --  runtime escapes the quotes on the way, and cmd then strips the ones it finds.
   --  ShellExecuteW takes the path itself, as a string, and no quoting is involved at
   --  any point.
   function Launch_Native (App : Application) return Boolean;

end Launcher.Applications.Platform;

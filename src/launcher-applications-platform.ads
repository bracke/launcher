--  How the host itself records the applications it has installed.
--
--  XDG .desktop files are a freedesktop convention: they exist on Linux and on
--  neither Windows nor macOS. Discovery that reads only those finds nothing at all on
--  the other two, which is why the launcher came up empty there -- not because those
--  systems have no applications, but because nobody had asked them.
--
--  Each host is asked in its own terms: the Start Menu on Windows (shell links,
--  Internet shortcuts and ClickOnce references; not Store applications, which only
--  the shell's COM AppsFolder lists), the application bundles under /Applications
--  and the plain folders in it on macOS. The host-independent rules are in
--  Launcher.Native_Entries.
package Launcher.Applications.Platform is

   --  The applications this host installs, in its own native form. Empty on Linux,
   --  where the XDG scan in the parent already covers it.
   function Installed_Native return Application_Vectors.Vector;

   --  Start App the way this host starts its own applications, when it is one
   --  only the host can start. False means it is not -- it has a program and
   --  arguments, which Launch starts itself -- and Started is then meaningless.
   --  True means the host was asked, and Started is its answer: there is no
   --  command line to fall back on, so a failure here is the launch failing.
   --
   --  Windows needs its own way in. A Start Menu entry is a .lnk whose path routinely
   --  contains spaces, so it would have to be quoted to survive a shell -- and a
   --  quoted command line cannot be got to cmd through an argument vector: the C
   --  runtime escapes the quotes on the way, and cmd then strips the ones it finds.
   --  ShellExecuteW takes the path itself, as a string, and no quoting is involved at
   --  any point.
   --
   --  @param App The application to start.
   --  @param Started Whether the host started it, when the result is True.
   --  @return True when App is the host's to start.
   function Launch_Native (App : Application; Started : out Boolean) return Boolean;

end Launcher.Applications.Platform;

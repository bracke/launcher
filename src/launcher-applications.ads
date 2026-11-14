with Ada.Containers.Vectors;

with Hostkit;

--  Discovery and launching of installed desktop applications.
--
--  On Linux applications are read from the freedesktop "applications" folders
--  (Hostkit.Desktop_Entries.Application_Folders, subfolders included) as
--  Desktop Entry files, which Hostkit.Desktop_Entries reads as the Desktop
--  Entry Specification has them -- strictly, string escapes decoded, Name,
--  Icon and Comment in the message locale, TryExec, OnlyShowIn and NotShowIn
--  honoured -- and whose Exec line it makes into an argument vector with the
--  field codes expanded. Here Terminal=true entries are started inside a
--  terminal and Path= is the working directory. Windows and macOS add what the host itself
--  records (Launcher.Applications.Platform). The set is domain-only: it knows
--  nothing about the UI.
package Launcher.Applications is

   type Application is record
      --  What the application is, for counting its launches: the desktop-file
      --  id ("org.gnome.Terminal.desktop"), the shortcut's place in the Start
      --  Menu, or the bundle's path. Two entries can share a Name; never an Id.
      Id        : UString;
      Name      : UString;
      --  The command as the entry wrote it, for showing (--list), not running.
      --  For a Start Menu shortcut, the shortcut's own path, which the host opens
      --  (for an Internet shortcut, the URL it names).
      Exec      : UString;
      --  What runs: the program (a name looked up on the search path, or a
      --  path) and its arguments, field codes already expanded. Program is ""
      --  for an entry only the host can start (a Start Menu shortcut).
      Program   : UString;
      Arguments : Hostkit.String_Vectors.Vector;
      --  The working directory to start it in (Path=), or "" for the launcher's own.
      Directory : UString;
      Comment   : UString;
      Icon      : UString;  --  the .desktop Icon= value (an icon name or a path)
   end record;

   package Application_Vectors is new Ada.Containers.Vectors
     (Index_Type   => Positive,
      Element_Type => Application);

   --  Scan the host's application folders for launchable entries, de-duplicated
   --  by desktop-file id (earlier folders win, per the XDG precedence), then add
   --  what the host records natively. Malformed, Hidden, NoDisplay,
   --  non-Application and Exec-less entries, entries whose TryExec program is missing, entries not
   --  meant for the current desktop (OnlyShowIn/NotShowIn against
   --  XDG_CURRENT_DESKTOP) and Terminal=true entries with no terminal to run
   --  them in are skipped. Unsorted.
   --
   --  @return The launchable applications.
   function Installed return Application_Vectors.Vector;

   --  The launchable entries of one "applications" folder and its subfolders,
   --  each under its desktop-file id: its path below the folder with each
   --  separator turned into '-' ("kde/konsole.desktop" is
   --  "kde-konsole.desktop"). An id is read once: the first file met under
   --  it decides, launchable or not. (Installed shares that record across the
   --  folders, so a hidden entry in a higher one masks a lower one's.)
   --
   --  @param Folder An "applications" folder.
   --  @param Apps Receives the launchable entries.
   procedure Scan_Folder (Folder : String; Apps : in out Application_Vectors.Vector);

   --  Start an application detached, so it keeps running after the launcher
   --  exits: by argument vector (no shell is involved), in its working
   --  directory, or -- for an entry only the host can start -- the host's way.
   --
   --  @param App The application to launch.
   --  @return True when the process was spawned.
   function Launch (App : Application) return Boolean;

   --  The arguments that put a command line after a terminal's own, so the
   --  terminal runs it: "-e" for xterm and those that copy it, "--" for the
   --  GNOME family, nothing for kitty, and so on -- the host's own table,
   --  Hostkit.Process.Terminal_Program_Prefix.
   --
   --  @param Terminal The terminal program, by name or path (Hostkit.Process.Default_Terminal).
   --  @param Prefix The arguments that go between the terminal and the command.
   --  @return False for a terminal whose way of being given a command is not known.
   function Terminal_Prefix
     (Terminal : String;
      Prefix   : out Hostkit.String_Vectors.Vector)
      return Boolean;

end Launcher.Applications;

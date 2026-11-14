with Ada.Containers.Vectors;

with Hostkit;

--  Discovery and launching of installed desktop applications.
--
--  On Linux applications are read from the freedesktop "applications" folders
--  (under each of Hostkit.Fs.Application_Data_Directories, subfolders included)
--  as Desktop Entry files, read as the Desktop Entry Specification has them:
--  string escapes decoded, the Exec line split into an argument vector by its
--  own quoting rules and its field codes expanded, TryExec, OnlyShowIn and
--  NotShowIn honoured, Terminal=true entries started inside a terminal and
--  Path= as the working directory. Windows and macOS add what the host itself
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
      --  For a Start Menu shortcut, the shortcut's own path, which the host opens.
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
   --  what the host records natively. Hidden, NoDisplay, non-Application and
   --  Exec-less entries, entries whose TryExec program is missing, entries not
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

   --  Read one Desktop Entry file as the entry Id.
   --
   --  @param Path The .desktop file.
   --  @param Id Its desktop-file id.
   --  @param App The application, valid only when Found.
   --  @param Found True when the file is a launchable Application entry here.
   procedure Parse_Desktop_File
     (Path  : String;
      Id    : String;
      App   : out Application;
      Found : out Boolean);

   --  Decode a Desktop Entry string value's escapes: \s, \n, \t, \r and \\
   --  become a space, a newline, a tab, a carriage return and a backslash. Any
   --  other backslash is kept as it is.
   --
   --  @param Value A raw value, as it follows '=' in the file.
   --  @return The decoded value.
   function Decode_Escapes (Value : String) return String;

   --  Split a (string-decoded) Exec value into its arguments: separated by
   --  spaces, a double-quoted argument may hold spaces, and inside quotes a
   --  backslash escapes '"', '`', '$' and '\'.
   --
   --  @param Exec The Exec value after Decode_Escapes.
   --  @param Arguments The arguments, the program first.
   --  @return False when a quote is left open.
   function Split_Exec
     (Exec      : String;
      Arguments : out Hostkit.String_Vectors.Vector)
      return Boolean;

   --  Expand the field codes in split Exec arguments for a launch with no
   --  files: %f %F %u %U (and the deprecated %d %D %n %N %v %m) are dropped --
   --  an argument that is only one of them disappears -- %i becomes the two
   --  arguments "--icon" and Icon (nothing when there is no icon), %c the
   --  entry's Name, %k the desktop file's path, and %% a single '%'.
   --
   --  @param Arguments Split Exec arguments.
   --  @param Name The entry's Name.
   --  @param Icon The entry's Icon, or "".
   --  @param Location The desktop file's path.
   --  @return The arguments with the field codes expanded.
   function Expand_Field_Codes
     (Arguments : Hostkit.String_Vectors.Vector;
      Name      : String;
      Icon      : String;
      Location  : String)
      return Hostkit.String_Vectors.Vector;

   --  Whether an entry is meant for the current desktop: when Only_Show_In is
   --  given, one of the current desktops must be in it; none of them may be in
   --  Not_Show_In.
   --
   --  @param Only_Show_In The OnlyShowIn value (';'-separated), or "".
   --  @param Not_Show_In The NotShowIn value (';'-separated), or "".
   --  @param Current_Desktop XDG_CURRENT_DESKTOP (':'-separated), or "".
   --  @return True when the entry should be shown.
   function Shown_In
     (Only_Show_In    : String;
      Not_Show_In     : String;
      Current_Desktop : String)
      return Boolean;

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

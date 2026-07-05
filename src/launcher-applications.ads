with Ada.Containers.Vectors;

--  Discovery and launching of installed desktop applications.
--
--  Applications are read from the XDG "applications" directories (the per-user
--  and system data dirs) as freedesktop .desktop entries. Each launchable entry
--  contributes an Application with its display name, a runnable command (Exec
--  with the field codes stripped) and an optional comment. The set is
--  domain-only: it knows nothing about the UI.
package Launcher.Applications is

   type Application is record
      Name    : UString;
      Exec    : UString;
      Comment : UString;
      Icon    : UString;  --  the .desktop Icon= value (an icon name or a path)
   end record;

   package Application_Vectors is new Ada.Containers.Vectors
     (Index_Type   => Positive,
      Element_Type => Application);

   --  Scan the XDG application directories for launchable entries, de-duplicated
   --  by desktop-file id (earlier directories win, per the XDG precedence) and
   --  sorted case-insensitively by display name. Hidden, NoDisplay and non-
   --  Application entries and entries without an Exec are skipped.
   --
   --  @return The launchable applications in display order.
   function Installed return Application_Vectors.Vector;

   --  Spawn an application's command detached, so it keeps running after the
   --  launcher exits. The Exec string is run through the shell.
   --
   --  @param App The application to launch.
   --  @return True when the process was spawned.
   function Launch (App : Application) return Boolean;

   --  Strip freedesktop Exec field codes (%f %F %u %U %i %c %k %d ...), leaving
   --  a runnable command; a literal "%%" becomes "%". Exposed for testing.
   --
   --  @param Exec A .desktop Exec value.
   --  @return The command with field codes removed and trimmed.
   function Strip_Field_Codes (Exec : String) return String;

end Launcher.Applications;

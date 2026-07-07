with Guikit.Command_Palette;

with Launcher.Applications;
with Launcher.Icons;
with Launcher.Usage;

--  The launcher's data layer: the installed applications (ordered most-used
--  first), their decoded icons, and the usage store. The query/selection/scroll
--  state and all rendering now live in Guikit.Command_Palette; this package just
--  supplies the command list and maps a chosen command back to an application.
package Launcher.Model is

   type State is record
      Apps  : Applications.Application_Vectors.Vector;
      Icons : Launcher.Icons.Loaded_Icon_Vectors.Vector;  --  parallel to Apps
      Usage : Launcher.Usage.Store;
   end record;

   --  Scan the installed applications, order them by usage (then name), and
   --  decode each icon once.
   procedure Load (M : in out State);

   --  The palette commands for the loaded applications. Each command's Id is the
   --  one-based index of its application in M.Apps, so a chosen command maps back
   --  through Application_For.
   --
   --  @param M Launcher state.
   --  @return The commands (label = name, description = comment, icon decoded).
   function Commands (M : State) return Guikit.Command_Palette.Command_Vectors.Vector;

   --  The application a chosen command Id refers to.
   --
   --  @param M Launcher state.
   --  @param Id A command Id from Guikit.Command_Palette.Selected_Id.
   --  @param App The application (valid only when the result is True).
   --  @return True when Id refers to a loaded application.
   function Application_For
     (M   : State;
      Id  : Natural;
      App : out Applications.Application)
      return Boolean;

   --  Record that an application was launched (increments + persists its usage
   --  count), so it ranks higher on the next run.
   procedure Record_Launch (M : in out State; App : Applications.Application);

end Launcher.Model;

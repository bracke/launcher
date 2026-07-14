package body Launcher.Applications.Platform is

   --  An unknown host records its applications somewhere we cannot name.
   function Installed_Native return Application_Vectors.Vector is
      None : Application_Vectors.Vector;
   begin
      return None;
   end Installed_Native;

   --  Nothing native to start: the shell runs the Exec, as it always has.
   function Launch_Native (App : Application) return Boolean is
      pragma Unreferenced (App);
   begin
      return False;
   end Launch_Native;

end Launcher.Applications.Platform;

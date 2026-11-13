package body Launcher.Applications.Platform is

   --  An unknown host records its applications somewhere we cannot name.
   function Installed_Native return Application_Vectors.Vector is
      None : Application_Vectors.Vector;
   begin
      return None;
   end Installed_Native;

   --  Nothing native to start: Launch runs the entry's program, as it always has.
   function Launch_Native (App : Application; Started : out Boolean) return Boolean is
      pragma Unreferenced (App);
   begin
      Started := False;
      return False;
   end Launch_Native;

end Launcher.Applications.Platform;

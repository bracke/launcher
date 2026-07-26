with Ada.Command_Line;
with Ada.Directories;
with Ada.Text_IO;

procedure Launcher_Release_Check is
   Errors : Natural := 0;

   procedure Require_File (Path : String) is
   begin
      if not Ada.Directories.Exists (Path) then
         Ada.Text_IO.Put_Line ("missing: " & Path);
         Errors := Errors + 1;
      end if;
   end Require_File;

begin
   Require_File ("../README.md");
   Require_File ("../share/launcher.catalog");
   --  The build bundles the load-only i18n data into share/i18n (tools/i18n_bundle);
   --  launcher renders its catalog through the messages crate, which needs it.
   Require_File ("../share/i18n/formats.i18ndata");
   Require_File ("tests/src/launcher_suite.adb");

   if Errors > 0 then
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
   end if;
end Launcher_Release_Check;

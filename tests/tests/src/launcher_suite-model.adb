with Ada.Strings.Unbounded;

with AUnit;
with AUnit.Assertions;
with AUnit.Test_Cases;

with Guikit.Command_Palette;

with Launcher.Applications;
with Launcher.Model;

--  Exercises the launcher's data layer: turning the loaded applications into
--  palette commands (label/id) and mapping a chosen command id back to its
--  application. Query/selection/filtering now live in Guikit.Command_Palette and
--  are tested there.
package body Launcher_Suite.Model is

   use AUnit.Assertions;
   use Ada.Strings.Unbounded;

   type Model_Test_Case is new AUnit.Test_Cases.Test_Case with null record;

   overriding function Name (T : Model_Test_Case) return AUnit.Message_String;
   overriding procedure Register_Tests (T : in out Model_Test_Case);

   procedure Test_Commands (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Application_For (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  A model seeded with three known applications.
   function Sample return Launcher.Model.State is
      M : Launcher.Model.State;

      procedure Add (Name, Exec, Comment : String) is
      begin
         M.Apps.Append
           (Launcher.Applications.Application'
              (Name    => To_Unbounded_String (Name),
               Exec    => To_Unbounded_String (Exec),
               Comment => To_Unbounded_String (Comment),
               Icon    => Null_Unbounded_String));
      end Add;
   begin
      Add ("Firefox", "firefox", "Web Browser");
      Add ("Files", "files", "File Manager");
      Add ("Calculator", "kcalc", "");
      return M;
   end Sample;

   overriding function Name (T : Model_Test_Case) return AUnit.Message_String is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("launcher model command list and application mapping");
   end Name;

   overriding procedure Register_Tests (T : in out Model_Test_Case) is
   begin
      AUnit.Test_Cases.Registration.Register_Routine
        (T, Test_Commands'Access, "Commands turns applications into palette commands with index ids");
      AUnit.Test_Cases.Registration.Register_Routine
        (T, Test_Application_For'Access, "Application_For maps a command id back to its application");
   end Register_Tests;

   procedure Test_Commands (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      M    : constant Launcher.Model.State := Sample;
      Cmds : constant Guikit.Command_Palette.Command_Vectors.Vector := Launcher.Model.Commands (M);
   begin
      Assert (Natural (Cmds.Length) = 3, "each application becomes one command");
      Assert (Cmds.Element (1).Id = 1, "a command's id is its one-based application index");
      Assert (To_String (Cmds.Element (1).Label) = "Firefox", "the command label is the application name");
      Assert (To_String (Cmds.Element (3).Description) = "", "an empty comment yields an empty description");
   end Test_Commands;

   procedure Test_Application_For (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      M   : constant Launcher.Model.State := Sample;
      App : Launcher.Applications.Application;
      pragma Warnings (Off, App);  --  App is an out param ignored on the miss cases
   begin
      Assert (Launcher.Model.Application_For (M, 1, App), "id 1 maps to an application");
      Assert (To_String (App.Name) = "Firefox", "id 1 is the first application");
      Assert (Launcher.Model.Application_For (M, 3, App) and then To_String (App.Name) = "Calculator",
              "id 3 is the third application");
      Assert (not Launcher.Model.Application_For (M, 0, App), "id 0 maps to nothing");
      Assert (not Launcher.Model.Application_For (M, 4, App), "an out-of-range id maps to nothing");
   end Test_Application_For;

   function Suite return AUnit.Test_Suites.Access_Test_Suite is
      Result : constant AUnit.Test_Suites.Access_Test_Suite := new AUnit.Test_Suites.Test_Suite;
   begin
      pragma Warnings (Off, "use of an anonymous access type allocator");
      Result.Add_Test (new Model_Test_Case);
      pragma Warnings (On, "use of an anonymous access type allocator");
      return Result;
   end Suite;

end Launcher_Suite.Model;

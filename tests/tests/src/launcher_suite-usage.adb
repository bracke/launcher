with Ada.Directories;
with Ada.Environment_Variables;

with AUnit;
with AUnit.Assertions;
with AUnit.Test_Cases;

with Launcher.Usage;

--  Exercises Launcher.Usage against a throwaway XDG_STATE_HOME: launch counts
--  increment, unknown apps count zero, and the counts persist across a reload.
package body Launcher_Suite.Usage is

   use AUnit.Assertions;

   type Usage_Test_Case is new AUnit.Test_Cases.Test_Case with null record;

   overriding function Name (T : Usage_Test_Case) return AUnit.Message_String;
   overriding procedure Register_Tests (T : in out Usage_Test_Case);

   procedure Test_Record_Count_And_Persist (T : in out AUnit.Test_Cases.Test_Case'Class);

   overriding function Name (T : Usage_Test_Case) return AUnit.Message_String is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("launcher application-usage store");
   end Name;

   overriding procedure Register_Tests (T : in out Usage_Test_Case) is
   begin
      AUnit.Test_Cases.Registration.Register_Routine
        (T, Test_Record_Count_And_Persist'Access,
         "launch counts increment, default to zero, and persist across a reload");
   end Register_Tests;

   procedure Test_Record_Count_And_Persist (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Base : constant String := Ada.Directories.Compose (Ada.Directories.Current_Directory, "usage_test_state");
   begin
      if Ada.Directories.Exists (Base) then
         Ada.Directories.Delete_Tree (Base);
      end if;
      Ada.Environment_Variables.Set ("XDG_STATE_HOME", Base);

      declare
         S : Launcher.Usage.Store := Launcher.Usage.Load;
      begin
         Assert (Launcher.Usage.Count (S, "Firefox") = 0, "an unrecorded app counts zero");
         Launcher.Usage.Record_Launch (S, "Firefox");
         Launcher.Usage.Record_Launch (S, "Firefox");
         Launcher.Usage.Record_Launch (S, "Files");
         Assert (Launcher.Usage.Count (S, "Firefox") = 2, "two launches count two");
         Assert (Launcher.Usage.Count (S, "Files") = 1, "one launch counts one");
      end;

      declare
         Reloaded : constant Launcher.Usage.Store := Launcher.Usage.Load;
      begin
         Assert (Launcher.Usage.Count (Reloaded, "Firefox") = 2, "counts persist across a reload");
         Assert (Launcher.Usage.Count (Reloaded, "Files") = 1, "second count persists across a reload");
         Assert (Launcher.Usage.Count (Reloaded, "Nothing") = 0, "an unknown app still counts zero");
      end;

      if Ada.Directories.Exists (Base) then
         Ada.Directories.Delete_Tree (Base);
      end if;
   end Test_Record_Count_And_Persist;

   function Suite return AUnit.Test_Suites.Access_Test_Suite is
      Result : constant AUnit.Test_Suites.Access_Test_Suite := new AUnit.Test_Suites.Test_Suite;
   begin
      pragma Warnings (Off, "use of an anonymous access type allocator");
      Result.Add_Test (new Usage_Test_Case);
      pragma Warnings (On, "use of an anonymous access type allocator");
      return Result;
   end Suite;

end Launcher_Suite.Usage;

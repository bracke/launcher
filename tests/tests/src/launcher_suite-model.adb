with Ada.Strings.Unbounded;

with AUnit;
with AUnit.Assertions;
with AUnit.Test_Cases;

with Launcher.Applications;
with Launcher.Model;

--  Exercises the launcher model over a fixed set of applications: typing appends
--  and resets the selection, backspace deletes a whole UTF-8 codepoint, selection
--  movement clamps to the result range, and the highlighted result maps back to
--  the right application. Filtering itself is delegated to Guikit.Palette (tested
--  in guikit); here we check the model's use of it.
package body Launcher_Suite.Model is

   use AUnit.Assertions;
   use Ada.Strings.Unbounded;

   type Model_Test_Case is new AUnit.Test_Cases.Test_Case with null record;

   overriding function Name (T : Model_Test_Case) return AUnit.Message_String;
   overriding procedure Register_Tests (T : in out Model_Test_Case);

   procedure Test_Insert_And_Backspace (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Move_Selection (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Results_And_Selected (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Select_First_And_Last (T : in out AUnit.Test_Cases.Test_Case'Class);

   --  A model seeded with three known applications and an empty query.
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
      return AUnit.Format ("launcher model query, selection and result mapping");
   end Name;

   overriding procedure Register_Tests (T : in out Model_Test_Case) is
   begin
      AUnit.Test_Cases.Registration.Register_Routine
        (T, Test_Insert_And_Backspace'Access, "insert appends; backspace deletes a whole UTF-8 codepoint");
      AUnit.Test_Cases.Registration.Register_Routine
        (T, Test_Move_Selection'Access, "selection movement clamps to the result range");
      AUnit.Test_Cases.Registration.Register_Routine
        (T, Test_Results_And_Selected'Access, "a query narrows results and the selection maps to an app");
      AUnit.Test_Cases.Registration.Register_Routine
        (T, Test_Select_First_And_Last'Access, "Home/End jump the selection to the first/last result");
   end Register_Tests;

   procedure Test_Insert_And_Backspace (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      M : Launcher.Model.State := Sample;
   begin
      Launcher.Model.Insert (M, "fi");
      Assert (To_String (M.Query) = "fi", "insert appends the typed text");
      Assert (M.Selected = 1, "insert resets the selection to the top");

      --  "f" followed by U+00E9 (e-acute), a two-byte sequence.
      M.Query := To_Unbounded_String ("f" & Character'Val (16#C3#) & Character'Val (16#A9#));
      Launcher.Model.Backspace (M);
      Assert (To_String (M.Query) = "f", "backspace removes a whole two-byte codepoint");
      Launcher.Model.Backspace (M);
      Assert (To_String (M.Query) = "", "backspace on the last character empties the query");
      Launcher.Model.Backspace (M);
      Assert (To_String (M.Query) = "", "backspace on an empty query is a no-op");
   end Test_Insert_And_Backspace;

   procedure Test_Move_Selection (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      M : Launcher.Model.State := Sample;
   begin
      Assert (M.Selected = 1, "the selection starts at the top");
      Launcher.Model.Move_Selection (M, 1);
      Assert (M.Selected = 2, "moving down advances the selection by one");
      Launcher.Model.Move_Selection (M, 10);
      Assert (M.Selected = 3, "moving past the end clamps to the last result");
      Launcher.Model.Move_Selection (M, -10);
      Assert (M.Selected = 1, "moving before the start clamps to the first result");

      Launcher.Model.Insert (M, "zzzzzzz");
      Launcher.Model.Move_Selection (M, 1);
      Assert (M.Selected = 0, "with no matching results the selection is cleared");
   end Test_Move_Selection;

   procedure Test_Results_And_Selected (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      M     : Launcher.Model.State := Sample;
      App   : Launcher.Applications.Application;
      Found : Boolean;
   begin
      Assert (Natural (Launcher.Model.Results (M).Length) = 3, "an empty query lists every application");

      Launcher.Model.Insert (M, "fire");
      Assert (Natural (Launcher.Model.Results (M).Length) = 1, "a specific query narrows the results");

      Found := Launcher.Model.Selected_Application (M, App);
      Assert (Found, "a highlighted result maps to an application");
      Assert (To_String (App.Name) = "Firefox", "the selected application is the matching one");
   end Test_Results_And_Selected;

   procedure Test_Select_First_And_Last (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      M : Launcher.Model.State := Sample;
   begin
      Launcher.Model.Move_Selection (M, 1);
      Launcher.Model.Select_First (M);
      Assert (M.Selected = 1, "Select_First highlights the first result");
      Launcher.Model.Select_Last (M);
      Assert (M.Selected = 3, "Select_Last highlights the last result");

      Launcher.Model.Insert (M, "zzzzzzz");
      Launcher.Model.Select_First (M);
      Assert (M.Selected = 0, "Select_First with no results clears the selection");
      Launcher.Model.Select_Last (M);
      Assert (M.Selected = 0, "Select_Last with no results clears the selection");
   end Test_Select_First_And_Last;

   function Suite return AUnit.Test_Suites.Access_Test_Suite is
      Result : constant AUnit.Test_Suites.Access_Test_Suite := new AUnit.Test_Suites.Test_Suite;
   begin
      pragma Warnings (Off, "use of an anonymous access type allocator");
      Result.Add_Test (new Model_Test_Case);
      pragma Warnings (On, "use of an anonymous access type allocator");
      return Result;
   end Suite;

end Launcher_Suite.Model;

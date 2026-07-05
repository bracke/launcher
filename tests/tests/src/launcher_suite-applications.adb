with AUnit;
with AUnit.Assertions;
with AUnit.Test_Cases;

with Launcher.Applications;

--  Exercises Launcher.Applications.Strip_Field_Codes: freedesktop Exec field
--  codes (%f %F %u %U %i %c %k ...) are removed and the result trimmed, while a
--  literal "%%" collapses to a single "%".
package body Launcher_Suite.Applications is

   use AUnit.Assertions;

   type Applications_Test_Case is new AUnit.Test_Cases.Test_Case with null record;

   overriding function Name (T : Applications_Test_Case) return AUnit.Message_String;
   overriding procedure Register_Tests (T : in out Applications_Test_Case);

   procedure Test_No_Codes (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Trailing_Codes (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Percent_Literal (T : in out AUnit.Test_Cases.Test_Case'Class);

   overriding function Name (T : Applications_Test_Case) return AUnit.Message_String is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("launcher .desktop Exec field-code stripping");
   end Name;

   overriding procedure Register_Tests (T : in out Applications_Test_Case) is
   begin
      AUnit.Test_Cases.Registration.Register_Routine
        (T, Test_No_Codes'Access, "a command with no field codes is returned unchanged");
      AUnit.Test_Cases.Registration.Register_Routine
        (T, Test_Trailing_Codes'Access, "trailing field codes are removed and the result trimmed");
      AUnit.Test_Cases.Registration.Register_Routine
        (T, Test_Percent_Literal'Access, "a literal %% collapses to a single %");
   end Register_Tests;

   procedure Test_No_Codes (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      use Launcher.Applications;
   begin
      Assert (Strip_Field_Codes ("") = "", "an empty Exec stays empty");
      Assert (Strip_Field_Codes ("firefox") = "firefox", "a bare command is unchanged");
      Assert (Strip_Field_Codes ("env X=1 /usr/bin/foo") = "env X=1 /usr/bin/foo",
              "a command with arguments but no field codes is unchanged");
   end Test_No_Codes;

   procedure Test_Trailing_Codes (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      use Launcher.Applications;
   begin
      Assert (Strip_Field_Codes ("gimp %f") = "gimp", "a trailing %f is removed and trimmed");
      Assert (Strip_Field_Codes ("firefox %u") = "firefox", "a trailing %u is removed and trimmed");
      Assert (Strip_Field_Codes ("vlc --started-from-file %U") = "vlc --started-from-file",
              "a trailing %U after arguments is removed and trimmed");
   end Test_Trailing_Codes;

   procedure Test_Percent_Literal (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      use Launcher.Applications;
   begin
      Assert (Strip_Field_Codes ("show 100%%") = "show 100%", "a literal %% becomes a single %");
      Assert (Strip_Field_Codes ("app %%d %f") = "app %d", "a %% is kept while %f is stripped");
   end Test_Percent_Literal;

   function Suite return AUnit.Test_Suites.Access_Test_Suite is
      Result : constant AUnit.Test_Suites.Access_Test_Suite := new AUnit.Test_Suites.Test_Suite;
   begin
      pragma Warnings (Off, "use of an anonymous access type allocator");
      Result.Add_Test (new Applications_Test_Case);
      pragma Warnings (On, "use of an anonymous access type allocator");
      return Result;
   end Suite;

end Launcher_Suite.Applications;

with Ada.Directories;
with Ada.Text_IO;

with AUnit;
with AUnit.Assertions;
with AUnit.Test_Cases;

with Hostkit.Environment;
with Hostkit.Fs;

with Launcher.Usage;

--  Exercises Launcher.Usage against a throwaway XDG_STATE_HOME: launch counts
--  increment per application id, unknown apps count zero, the counts persist
--  across a reload, and a count from the old name-keyed file carries over.
--  The variable and the folder are put back as they were whatever happens.
package body Launcher_Suite.Usage is

   use AUnit.Assertions;

   type Usage_Test_Case is new AUnit.Test_Cases.Test_Case with null record;

   overriding function Name (T : Usage_Test_Case) return AUnit.Message_String;
   overriding procedure Register_Tests (T : in out Usage_Test_Case);

   procedure Test_Record_Count_And_Persist (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Name_Counts_Carry_Over (T : in out AUnit.Test_Cases.Test_Case'Class);

   overriding function Name (T : Usage_Test_Case) return AUnit.Message_String is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("launcher application-usage store");
   end Name;

   overriding procedure Register_Tests (T : in out Usage_Test_Case) is
   begin
      AUnit.Test_Cases.Registration.Register_Routine
        (T, Test_Record_Count_And_Persist'Access,
         "launch counts increment by id, default to zero, and persist across a reload");
      AUnit.Test_Cases.Registration.Register_Routine
        (T, Test_Name_Counts_Carry_Over'Access,
         "a count from the old name-keyed file answers until one id of that name takes it over");
   end Register_Tests;

   --  Run Body with XDG_STATE_HOME pointing at a fresh temporary folder, then
   --  put the variable back as it was and remove the folder -- on failure too.
   generic
      with procedure Body_Of_Test (Base : String);
   procedure With_State_Home;

   procedure With_State_Home is
      Had_Old : Boolean;
      Old     : constant String := Hostkit.Environment.Value ("XDG_STATE_HOME", Had_Old);
      Base    : constant String := Hostkit.Fs.Create_Temporary_Directory ("launcher-usage-test");

      procedure Restore is
         Ignore : Hostkit.Fs.Delete_Tree_Outcome;
      begin
         if Had_Old then
            Hostkit.Environment.Set ("XDG_STATE_HOME", Old);
         else
            Hostkit.Environment.Clear ("XDG_STATE_HOME");
         end if;
         if Base /= "" then
            Ignore := Hostkit.Fs.Delete_Tree_No_Follow (Base);
         end if;
      end Restore;
   begin
      Assert (Base /= "", "a temporary state folder was made");
      Hostkit.Environment.Set ("XDG_STATE_HOME", Base);
      Body_Of_Test (Base);
      Restore;
   exception
      when others =>
         Restore;
         raise;
   end With_State_Home;

   procedure Record_Count_And_Persist (Base : String) is
      pragma Unreferenced (Base);
   begin
      declare
         S : Launcher.Usage.Store := Launcher.Usage.Load;
      begin
         Assert (Launcher.Usage.Count (S, "firefox.desktop", "Firefox") = 0, "an unrecorded app counts zero");
         Launcher.Usage.Record_Launch (S, "firefox.desktop", "Firefox");
         Launcher.Usage.Record_Launch (S, "firefox.desktop", "Firefox");
         Launcher.Usage.Record_Launch (S, "files.desktop", "Files");
         Assert (Launcher.Usage.Count (S, "firefox.desktop", "Firefox") = 2, "two launches count two");
         Assert (Launcher.Usage.Count (S, "files.desktop", "Files") = 1, "one launch counts one");
         --  Two entries named alike are two applications.
         Launcher.Usage.Record_Launch (S, "org.gnome.Terminal.desktop", "Terminal");
         Assert (Launcher.Usage.Count (S, "org.kde.konsole.desktop", "Terminal") = 0,
                 "another application with the same name has its own count");
      end;

      declare
         Reloaded : constant Launcher.Usage.Store := Launcher.Usage.Load;
      begin
         Assert (Launcher.Usage.Count (Reloaded, "firefox.desktop", "Firefox") = 2, "counts persist across a reload");
         Assert (Launcher.Usage.Count (Reloaded, "files.desktop", "Files") = 1,
                 "second count persists across a reload");
         Assert (Launcher.Usage.Count (Reloaded, "nothing.desktop", "Nothing") = 0, "an unknown app still counts zero");
      end;

      Assert (not Ada.Directories.Exists (Launcher.Usage.Usage_File & ".tmp"),
              "the save leaves no temporary file behind");
   end Record_Count_And_Persist;

   procedure Name_Counts_Carry_Over (Base : String) is
      Folder : constant String := Hostkit.Fs.Join (Base, "launcher");
      File   : Ada.Text_IO.File_Type;
   begin
      --  The file as the name-keyed launcher wrote it.
      Ada.Directories.Create_Path (Folder);
      Ada.Text_IO.Create (File, Ada.Text_IO.Out_File, Launcher.Usage.Usage_File, Form => "shared=no");
      Ada.Text_IO.Put_Line (File, "5" & ASCII.HT & "Terminal");
      Ada.Text_IO.Put_Line (File, "3" & ASCII.HT & "Firefox");
      Ada.Text_IO.Close (File);

      declare
         S : Launcher.Usage.Store := Launcher.Usage.Load;
      begin
         Assert (Launcher.Usage.Count (S, "org.gnome.Terminal.desktop", "Terminal") = 5,
                 "an old name count answers for an id with none");
         Launcher.Usage.Record_Launch (S, "firefox.desktop", "Firefox");
         Assert (Launcher.Usage.Count (S, "firefox.desktop", "Firefox") = 4,
                 "the first launch by id carries on from the name count");
      end;

      declare
         Reloaded : constant Launcher.Usage.Store := Launcher.Usage.Load;
      begin
         Assert (Launcher.Usage.Count (Reloaded, "firefox.desktop", "Firefox") = 4,
                 "the id count is what was saved");
         Assert (Launcher.Usage.Count (Reloaded, "org.kde.konsole.desktop", "Terminal") = 5,
                 "name counts not yet carried over are kept");
      end;

      --  Two applications called "Terminal": the first launched takes the
      --  name count over, and the other starts at zero -- now and after a
      --  reload, since the name count is gone from the file.
      declare
         S : Launcher.Usage.Store := Launcher.Usage.Load;
      begin
         Launcher.Usage.Record_Launch (S, "org.gnome.Terminal.desktop", "Terminal");
         Assert (Launcher.Usage.Count (S, "org.gnome.Terminal.desktop", "Terminal") = 6,
                 "the first of two same-named applications carries on from the name count");
         Assert (Launcher.Usage.Count (S, "org.kde.konsole.desktop", "Terminal") = 0,
                 "the other application of the same name does not inherit the name count");
         Launcher.Usage.Record_Launch (S, "org.gnome.Terminal.desktop", "Terminal");
         Assert (Launcher.Usage.Count (S, "org.gnome.Terminal.desktop", "Terminal") = 7,
                 "later launches count on from the migrated count");
      end;

      declare
         Reloaded : constant Launcher.Usage.Store := Launcher.Usage.Load;
      begin
         Assert (Launcher.Usage.Count (Reloaded, "org.kde.konsole.desktop", "Terminal") = 0,
                 "the migrated name count is not saved again for the other application");
         Assert (Launcher.Usage.Count (Reloaded, "org.gnome.Terminal.desktop", "Terminal") = 7,
                 "the migrated count is saved under its id");
      end;
   end Name_Counts_Carry_Over;

   procedure Test_Record_Count_And_Persist (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      procedure Run is new With_State_Home (Record_Count_And_Persist);
   begin
      Run;
   end Test_Record_Count_And_Persist;

   procedure Test_Name_Counts_Carry_Over (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      procedure Run is new With_State_Home (Name_Counts_Carry_Over);
   begin
      Run;
   end Test_Name_Counts_Carry_Over;

   function Suite return AUnit.Test_Suites.Access_Test_Suite is
      Result : constant AUnit.Test_Suites.Access_Test_Suite := new AUnit.Test_Suites.Test_Suite;
   begin
      Result.Add_Test (AUnit.Test_Cases.Test_Case_Access'(new Usage_Test_Case));
      return Result;
   end Suite;

end Launcher_Suite.Usage;

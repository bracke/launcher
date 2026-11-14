with Hostkit.Host;
with Ada.Directories;
with Ada.Strings.Unbounded;
with Ada.Text_IO;

with AUnit;
with AUnit.Assertions;
with AUnit.Test_Cases;

with Hostkit;
with Hostkit.Fs;

with Launcher.Applications;

--  Exercises Launcher.Applications' use of the Desktop Entry files that
--  Hostkit.Desktop_Entries reads (its own suite tests the reading): what is
--  launchable, the program and arguments an entry starts, its working
--  directory and comment, TryExec and OnlyShowIn honoured, Terminal=true
--  wrapped, and entries in subfolders found under their desktop-file ids.
package body Launcher_Suite.Applications is

   use AUnit.Assertions;
   use Ada.Strings.Unbounded;
   use Launcher.Applications;

   subtype Vector is Hostkit.String_Vectors.Vector;

   type Applications_Test_Case is new AUnit.Test_Cases.Test_Case with null record;

   overriding function Name (T : Applications_Test_Case) return AUnit.Message_String;
   overriding procedure Register_Tests (T : in out Applications_Test_Case);

   procedure Test_Terminal_Prefix (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Desktop_Files (T : in out AUnit.Test_Cases.Test_Case'Class);

   overriding function Name (T : Applications_Test_Case) return AUnit.Message_String is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("launcher Desktop Entry reading");
   end Name;

   overriding procedure Register_Tests (T : in out Applications_Test_Case) is
   begin
      AUnit.Test_Cases.Registration.Register_Routine
        (T, Test_Terminal_Prefix'Access, "a terminal is given a command its own way");
      AUnit.Test_Cases.Registration.Register_Routine
        (T, Test_Desktop_Files'Access,
         "desktop files: argv, TryExec, OnlyShowIn, Hidden and subfolder ids");
   end Register_Tests;

   function Image (Items : Vector) return String is
      Result : Unbounded_String;
   begin
      for Item of Items loop
         Append (Result, "[" & Item & "]");
      end loop;
      return To_String (Result);
   end Image;

   procedure Test_Terminal_Prefix (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);

      function Prefix (Terminal : String) return String is
         Items : Vector;
      begin
         if not Terminal_Prefix (Terminal, Items) then
            return "<unknown>";
         end if;
         return Image (Items);
      end Prefix;
   begin
      Assert (Prefix ("xterm") = "[-e]", "xterm takes -e");
      Assert (Prefix ("/usr/bin/x-terminal-emulator") = "[-e]", "a path is read by its name");
      Assert (Prefix ("gnome-terminal") = "[--]", "gnome-terminal takes --");
      Assert (Prefix ("xfce4-terminal") = "[-x]", "xfce4-terminal takes -x");
      Assert (Prefix ("wezterm") = "[start][--]", "wezterm takes start --");
      Assert (Prefix ("kitty") = "", "kitty runs the command that follows it, so Terminal=true entries stay");
      Assert (Prefix ("tilix") = "[-e]", "tilix takes -e, so Terminal=true entries stay");
      --  An unlisted terminal is assumed to take -e, as most do, where a
      --  terminal program is offered at all; a shell never stands in for one.
      Assert (Prefix ("no-such-terminal") =
                (if Hostkit.Host."=" (Hostkit.Host.Current, Hostkit.Host.Windows) then "<unknown>" else "[-e]"),
              "an unknown terminal takes -e on a POSIX host and is refused on Windows");
      Assert (Prefix ("bash") = "<unknown>", "a shell is not a terminal");
   end Test_Terminal_Prefix;

   procedure Test_Desktop_Files (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      Root : constant String := Hostkit.Fs.Create_Temporary_Directory ("launcher-apps-test");

      procedure Write (Relative : String; Lines : String) is
         File : Ada.Text_IO.File_Type;
      begin
         Ada.Text_IO.Create
           (File, Ada.Text_IO.Out_File, Hostkit.Fs.Join (Root, Relative), Form => "shared=no");
         Ada.Text_IO.Put (File, Lines);
         Ada.Text_IO.Close (File);
      end Write;

      function Entry_Text (Name, Exec : String; Extra : String := "") return String is
        ("[Desktop Entry]" & ASCII.LF & "Type=Application" & ASCII.LF
         & "Name=" & Name & ASCII.LF & "Exec=" & Exec & ASCII.LF & Extra);

      --  A path as a Desktop Entry value: each backslash (a Windows separator)
      --  written as the \\ escape, or "C:\tmp" would read as "C:" TAB "mp".
      function Escaped (Path : String) return String is
         Result : Unbounded_String;
      begin
         for C of Path loop
            if C = '\' then
               Append (Result, "\\");
            else
               Append (Result, C);
            end if;
         end loop;
         return To_String (Result);
      end Escaped;

      procedure Clean_Up is
         Ignore : Hostkit.Fs.Delete_Tree_Outcome;
      begin
         if Root /= "" then
            Ignore := Hostkit.Fs.Delete_Tree_No_Follow (Root);
         end if;
      end Clean_Up;

      Apps : Application_Vectors.Vector;

      --  The application scanned under Id; Found False when there is none.
      function Find (Id : String; Found : out Boolean) return Application is
      begin
         for App of Apps loop
            if To_String (App.Id) = Id then
               Found := True;
               return App;
            end if;
         end loop;
         Found := False;
         return (others => <>);
      end Find;

      LF : constant Character := ASCII.LF;
   begin
      Assert (Root /= "", "a temporary folder was made");
      Ada.Directories.Create_Path (Hostkit.Fs.Join (Root, "kde/sub"));

      Write ("plain.desktop",
             "# a comment line" & LF
             & Entry_Text ("Plain", """/opt/My App/run"" --name=%c %U",
                           "Icon=plain-icon" & LF
                           & "Comment=A\scomment" & LF
                           & "Path=" & Escaped (Root) & LF)
             & "[Desktop Action other]" & LF & "Exec=not-this-one" & LF);
      Write ("kde/konsole.desktop", Entry_Text ("Konsole", "konsole"));
      Write ("kde/sub/deep.desktop", Entry_Text ("Deep", "deep"));
      Write ("tryexec-missing.desktop",
             Entry_Text ("Missing", "missing", "TryExec=/nonexistent-launcher-test/program" & LF));
      Write ("tryexec-present.desktop",
             Entry_Text ("Present", "present", "TryExec=" & Escaped (Hostkit.Fs.Own_Executable) & LF));
      Write ("only.desktop",
             Entry_Text ("Only", "only", "OnlyShowIn=No-Such-Desktop-For-Launcher-Tests;" & LF));
      Write ("hidden.desktop", Entry_Text ("Hidden", "hidden", "NoDisplay=true" & LF));
      Write ("deleted.desktop", Entry_Text ("Deleted", "deleted", "Hidden=true" & LF));
      Write ("link.desktop", "[Desktop Entry]" & LF & "Type=Link" & LF & "Name=Link" & LF & "URL=x" & LF);
      Write ("noexec.desktop", "[Desktop Entry]" & LF & "Type=Application" & LF & "Name=NoExec" & LF);
      Write ("unbalanced.desktop", Entry_Text ("Unbalanced", "app ""open"));
      Write ("invalid-escape.desktop", Entry_Text ("Invalid Escape", "say \$HOME"));
      Write ("notes.txt", Entry_Text ("Text", "text"));

      Scan_Folder (Root, Apps);

      Assert (Natural (Apps.Length) = 4,
              "four launchable entries, found" & Natural'Image (Natural (Apps.Length)));

      declare
         Found : Boolean;
         Plain : constant Application := Find ("plain.desktop", Found);
      begin
         Assert (Found, "an entry at the top is under its file name");
         Assert (To_String (Plain.Name) = "Plain", "its Name");
         Assert (To_String (Plain.Program) = "/opt/My App/run", "the quoted program is one argument");
         Assert (Image (Plain.Arguments) = "[--name=Plain]",
                 "%c expanded and %U dropped: " & Image (Plain.Arguments));
         Assert (To_String (Plain.Comment) = "A comment", "the comment's \s escape is decoded");
         Assert (To_String (Plain.Directory) = Root, "Path= is the working directory");
         Assert (To_String (Plain.Icon) = "plain-icon", "its Icon");
      end;

      declare
         Found   : Boolean;
         Konsole : constant Application := Find ("kde-konsole.desktop", Found);
      begin
         Assert (Found, "an entry in a subfolder is under a folder-joined id");
         Assert (To_String (Konsole.Program) = "konsole", "and is read like any other");
      end;

      declare
         Found  : Boolean;
         Ignore : Application := Find ("kde-sub-deep.desktop", Found);
      begin
         Assert (Found, "each folder level joins the id with '-'");
         Ignore := Find ("tryexec-present.desktop", Found);
         Assert (Found, "an entry whose TryExec program exists is listed");
         Ignore := Find ("tryexec-missing.desktop", Found);
         Assert (not Found, "an entry whose TryExec program is missing is not");
         Ignore := Find ("only.desktop", Found);
         Assert (not Found, "an entry only for another desktop is not");
         Ignore := Find ("hidden.desktop", Found);
         Assert (not Found, "a NoDisplay entry is not");
         Ignore := Find ("deleted.desktop", Found);
         Assert (not Found, "a Hidden entry is not");
         Ignore := Find ("unbalanced.desktop", Found);
         Assert (not Found, "an entry whose Exec cannot be split is not");
         Ignore := Find ("invalid-escape.desktop", Found);
         Assert (not Found, "an entry with an invalid string escape is not");
      end;

      Clean_Up;
   exception
      when others =>
         Clean_Up;
         raise;
   end Test_Desktop_Files;

   function Suite return AUnit.Test_Suites.Access_Test_Suite is
      Result : constant AUnit.Test_Suites.Access_Test_Suite := new AUnit.Test_Suites.Test_Suite;
   begin
      Result.Add_Test (AUnit.Test_Cases.Test_Case_Access'(new Applications_Test_Case));
      return Result;
   end Suite;

end Launcher_Suite.Applications;

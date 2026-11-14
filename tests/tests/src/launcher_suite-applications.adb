with Ada.Directories;
with Ada.Strings.Unbounded;
with Ada.Text_IO;

with AUnit;
with AUnit.Assertions;
with AUnit.Test_Cases;

with Hostkit;
with Hostkit.Fs;

with Launcher.Applications;

--  Exercises Launcher.Applications' reading of Desktop Entry files, as the
--  Desktop Entry Specification has it: string escapes decoded, Exec split by
--  its own quoting rules into an argument vector, field codes expanded,
--  TryExec and OnlyShowIn/NotShowIn honoured, Terminal=true wrapped, and
--  entries in subfolders found under their desktop-file ids.
package body Launcher_Suite.Applications is

   use AUnit.Assertions;
   use Ada.Strings.Unbounded;
   use Launcher.Applications;

   subtype Vector is Hostkit.String_Vectors.Vector;

   type Applications_Test_Case is new AUnit.Test_Cases.Test_Case with null record;

   overriding function Name (T : Applications_Test_Case) return AUnit.Message_String;
   overriding procedure Register_Tests (T : in out Applications_Test_Case);

   procedure Test_Escapes (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Split_Exec (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Field_Codes (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Shown_In (T : in out AUnit.Test_Cases.Test_Case'Class);
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
        (T, Test_Escapes'Access, "string escapes \s \n \t \r \\ are decoded, others kept");
      AUnit.Test_Cases.Registration.Register_Routine
        (T, Test_Split_Exec'Access, "Exec splits into arguments by its quoting rules");
      AUnit.Test_Cases.Registration.Register_Routine
        (T, Test_Field_Codes'Access, "field codes expand: files dropped, %i %c %k filled, %% kept");
      AUnit.Test_Cases.Registration.Register_Routine
        (T, Test_Shown_In'Access, "OnlyShowIn and NotShowIn are read against XDG_CURRENT_DESKTOP");
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

   function Split (Exec : String) return String is
      Items : Vector;
   begin
      if not Split_Exec (Exec, Items) then
         return "<unbalanced>";
      end if;
      return Image (Items);
   end Split;

   procedure Test_Escapes (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert (Decode_Escapes ("plain") = "plain", "a value with no escapes is unchanged");
      Assert (Decode_Escapes ("a\sb") = "a b", "\s is a space");
      Assert (Decode_Escapes ("a\nb\tc\rd") = "a" & ASCII.LF & "b" & ASCII.HT & "c" & ASCII.CR & "d",
              "\n \t \r are newline, tab and carriage return");
      Assert (Decode_Escapes ("C:\\Tools") = "C:\Tools", "\\ is one backslash");
      Assert (Decode_Escapes ("say \$HOME") = "say \$HOME",
              "an Exec quoting escape is left for Split_Exec");
      Assert (Decode_Escapes ("ends\") = "ends\", "a trailing backslash is kept");
   end Test_Escapes;

   procedure Test_Split_Exec (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert (Split ("firefox") = "[firefox]", "a bare program");
      Assert (Split ("env  X=1   /usr/bin/foo") = "[env][X=1][/usr/bin/foo]",
              "runs of spaces separate arguments");
      Assert (Split ("""/opt/My App/run"" --flag") = "[/opt/My App/run][--flag]",
              "a quoted argument keeps its spaces");
      Assert (Split ("sh -c ""echo \""hi\"" \$HOME \`x\` \\""") = "[sh][-c][echo ""hi"" $HOME `x` \]",
              "inside quotes \"" \$ \` \\ are escapes");
      Assert (Split ("app """"") = "[app][]", "an empty quoted argument is an argument");
      Assert (Split ("pre""fix""ed") = "[prefixed]", "quotes join with the text around them");
      Assert (Split ("app ""open") = "<unbalanced>", "an open quote is refused");
      Assert (Split ("") = "", "nothing is no arguments");
   end Test_Split_Exec;

   procedure Test_Field_Codes (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);

      function Expand (Exec : String; Icon : String := "") return String is
         Items : Vector;
         Ok    : constant Boolean := Split_Exec (Exec, Items);
      begin
         Assert (Ok, "the Exec splits");
         return Image (Expand_Field_Codes (Items, "My App", Icon, "/usr/share/applications/my.desktop"));
      end Expand;
   begin
      Assert (Expand ("gimp %f") = "[gimp]", "a lone %f disappears, leaving no empty argument");
      Assert (Expand ("vlc --started-from-file %U") = "[vlc][--started-from-file]", "a lone %U disappears");
      Assert (Expand ("app %F %u %d %D %n %N %v %m") = "[app]", "file and deprecated codes all go");
      Assert (Expand ("app %i", "app-icon") = "[app][--icon][app-icon]", "%i is --icon and the Icon");
      Assert (Expand ("app %i") = "[app]", "%i with no Icon is nothing");
      Assert (Expand ("app --title=%c") = "[app][--title=My App]", "%c is the Name, inside an argument too");
      Assert (Expand ("app %c") = "[app][My App]", "%c is one argument even with a space in it");
      Assert (Expand ("app %k") = "[app][/usr/share/applications/my.desktop]", "%k is the file's path");
      Assert (Expand ("show 100%%") = "[show][100%]", "%% is a single %");
      Assert (Expand ("app %%d %f") = "[app][%d]", "a %% is kept while %f is dropped");
   end Test_Field_Codes;

   procedure Test_Shown_In (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert (Shown_In ("", "", ""), "no restriction shows everywhere");
      Assert (Shown_In ("", "", "KDE"), "no restriction shows on any desktop");
      Assert (Shown_In ("GNOME;KDE;", "", "KDE"), "OnlyShowIn naming the desktop shows it");
      Assert (not Shown_In ("GNOME;", "", "KDE"), "OnlyShowIn naming another desktop hides it");
      Assert (not Shown_In ("GNOME;", "", ""), "OnlyShowIn with no current desktop hides it");
      Assert (Shown_In ("GNOME;", "", "ubuntu:GNOME"), "any of the current desktops may match");
      Assert (not Shown_In ("", "KDE;", "KDE"), "NotShowIn naming the desktop hides it");
      Assert (Shown_In ("", "KDE;", "GNOME"), "NotShowIn naming another desktop shows it");
      Assert (not Shown_In ("", "XFCE;", "ubuntu:XFCE"), "any current desktop in NotShowIn hides it");
      Assert (not Shown_In ("GNOME;", "", "gnome"), "desktop names compare with case");
   end Test_Shown_In;

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
      Assert (Prefix ("no-such-terminal") = "<unknown>", "an unknown terminal is refused");
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

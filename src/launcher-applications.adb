with Ada.Characters.Handling;
with Ada.Containers.Indefinite_Hashed_Sets;
with Ada.Directories;
with Ada.Environment_Variables;
with Ada.Strings.Fixed;
with Ada.Strings.Hash;
with Ada.Strings.Unbounded;
with Ada.Text_IO;

with Hostkit.Process;

with Launcher.Applications.Platform;

package body Launcher.Applications is
   use Ada.Strings.Unbounded;

   package String_Sets is new Ada.Containers.Indefinite_Hashed_Sets
     (Element_Type        => String,
      Hash                => Ada.Strings.Hash,
      Equivalent_Elements => "=");

   --  Read one environment variable, or a default when it is unset or empty.
   function Env (Name : String; Default : String) return String is
   begin
      if Ada.Environment_Variables.Exists (Name)
        and then Ada.Environment_Variables.Value (Name) /= ""
      then
         return Ada.Environment_Variables.Value (Name);
      end if;
      return Default;
   end Env;

   --  The colon-separated list of "applications" directories to scan, highest
   --  precedence first (the user data home, then each XDG_DATA_DIRS entry, each
   --  with "/applications" appended).
   function Search_Dirs return String is
      Home      : constant String := Env ("HOME", "");
      Data_Home : constant String :=
        Env ("XDG_DATA_HOME", (if Home = "" then "" else Home & "/.local/share"));
      Data_Dirs : constant String := Env ("XDG_DATA_DIRS", "/usr/local/share:/usr/share");
      Result    : Unbounded_String;
      First     : Integer := Data_Dirs'First;

      procedure Add (Dir : String) is
      begin
         if Dir /= "" then
            if Length (Result) > 0 then
               Append (Result, ':');
            end if;
            Append (Result, Dir & "/applications");
         end if;
      end Add;
   begin
      Add (Data_Home);
      for I in Data_Dirs'Range loop
         if Data_Dirs (I) = ':' then
            Add (Data_Dirs (First .. I - 1));
            First := I + 1;
         end if;
      end loop;
      if First <= Data_Dirs'Last then
         Add (Data_Dirs (First .. Data_Dirs'Last));
      end if;
      return To_String (Result);
   end Search_Dirs;

   --  Strip freedesktop Exec field codes (%f %F %u %U %i %c %k %d ...), leaving a
   --  runnable command; a literal "%%" becomes "%".
   function Strip_Field_Codes (Exec : String) return String is
      Result : Unbounded_String;
      I      : Integer := Exec'First;
   begin
      while I <= Exec'Last loop
         if Exec (I) = '%' and then I < Exec'Last then
            if Exec (I + 1) = '%' then
               Append (Result, '%');
            end if;
            I := I + 2;
         else
            Append (Result, Exec (I));
            I := I + 1;
         end if;
      end loop;
      return Ada.Strings.Fixed.Trim (To_String (Result), Ada.Strings.Both);
   end Strip_Field_Codes;

   --  Parse a single .desktop file; sets Found and the fields when it is a
   --  launchable Application entry.
   procedure Parse_Desktop
     (Path  : String;
      App   : out Application;
      Found : out Boolean)
   is
      File     : Ada.Text_IO.File_Type;
      In_Entry : Boolean := False;
      Name     : Unbounded_String;
      Exec     : Unbounded_String;
      Comment  : Unbounded_String;
      Icon     : Unbounded_String;
      Is_App   : Boolean := False;
      Hidden   : Boolean := False;
   begin
      App   := (others => Null_Unbounded_String);
      Found := False;
      Ada.Text_IO.Open (File, Ada.Text_IO.In_File, Path);
      while not Ada.Text_IO.End_Of_File (File) loop
         declare
            Line : constant String :=
              Ada.Strings.Fixed.Trim (Ada.Text_IO.Get_Line (File), Ada.Strings.Both);
            Eq   : constant Natural := Ada.Strings.Fixed.Index (Line, "=");
         begin
            if Line'Length > 0 and then Line (Line'First) = '[' then
               In_Entry := Line = "[Desktop Entry]";
            elsif In_Entry and then Eq > Line'First then
               declare
                  Key : constant String := Line (Line'First .. Eq - 1);
                  Val : constant String := Line (Eq + 1 .. Line'Last);
               begin
                  if Key = "Name" then
                     Name := To_Unbounded_String (Val);
                  elsif Key = "Exec" then
                     Exec := To_Unbounded_String (Strip_Field_Codes (Val));
                  elsif Key = "Comment" then
                     Comment := To_Unbounded_String (Val);
                  elsif Key = "Icon" then
                     Icon := To_Unbounded_String (Val);
                  elsif Key = "Type" then
                     Is_App := Val = "Application";
                  elsif Key = "NoDisplay" or else Key = "Hidden" then
                     Hidden := Hidden or else Val = "true";
                  end if;
               end;
            end if;
         end;
      end loop;
      Ada.Text_IO.Close (File);

      if Is_App and then not Hidden and then Length (Name) > 0 and then Length (Exec) > 0 then
         App   := (Name => Name, Exec => Exec, Comment => Comment, Icon => Icon);
         Found := True;
      end if;
   exception
      when others =>
         if Ada.Text_IO.Is_Open (File) then
            Ada.Text_IO.Close (File);
         end if;
         Found := False;
   end Parse_Desktop;

   --  Scan one directory's *.desktop files into Apps, skipping ids already Seen.
   procedure Scan_Dir
     (Dir  : String;
      Seen : in out String_Sets.Set;
      Apps : in out Application_Vectors.Vector)
   is
      use Ada.Directories;
      Search : Search_Type;
      Item   : Directory_Entry_Type;
   begin
      if not Exists (Dir) or else Kind (Dir) /= Directory then
         return;
      end if;
      Start_Search (Search, Dir, "*.desktop", (Ordinary_File => True, others => False));
      while More_Entries (Search) loop
         Get_Next_Entry (Search, Item);
         declare
            Id  : constant String := Simple_Name (Item);
            App : Application;
            Ok  : Boolean;
         begin
            if not Seen.Contains (Id) then
               Seen.Insert (Id);
               Parse_Desktop (Full_Name (Item), App, Ok);
               if Ok then
                  Apps.Append (App);
               end if;
            end if;
         end;
      end loop;
      End_Search (Search);
   exception
      when others =>
         null;
   end Scan_Dir;

   function Installed return Application_Vectors.Vector is
      Dirs : constant String := Search_Dirs;
      Seen : String_Sets.Set;
      Apps : Application_Vectors.Vector;
      First : Integer := Dirs'First;

      function Less (Left, Right : Application) return Boolean is
        (Ada.Characters.Handling.To_Lower (To_String (Left.Name))
           < Ada.Characters.Handling.To_Lower (To_String (Right.Name)));

      package Sorting is new Application_Vectors.Generic_Sorting ("<" => Less);
   begin
      for I in Dirs'Range loop
         if Dirs (I) = ':' then
            if I > First then
               Scan_Dir (Dirs (First .. I - 1), Seen, Apps);
            end if;
            First := I + 1;
         end if;
      end loop;
      if First <= Dirs'Last then
         Scan_Dir (Dirs (First .. Dirs'Last), Seen, Apps);
      end if;

      --  Whatever the host records natively -- the Start Menu, the .app bundles --
      --  joins what the XDG scan found. On Linux that is nothing, because the XDG scan
      --  IS the native answer there; on Windows and macOS it is everything, because
      --  the XDG scan finds nothing at all.
      for App of Launcher.Applications.Platform.Installed_Native loop
         declare
            Key : constant String := To_String (App.Name);
         begin
            if not Seen.Contains (Key) then
               Seen.Insert (Key);
               Apps.Append (App);
            end if;
         end;
      end loop;

      Sorting.Sort (Apps);
      return Apps;
   end Installed;

   --  An Exec is a command line, not a program and a list of arguments, so it goes
   --  through a shell -- which one, and how its arguments are quoted, is Hostkit's
   --  problem now rather than a second copy of the answer here.
   function Launch (App : Application) return Boolean is
      Command : constant String := To_String (App.Exec);
      Status  : Integer := -1;
   begin
      if Command = "" then
         return False;
      end if;

      --  Windows starts a Start Menu shortcut through the shell API rather than by
      --  running a command line. Everywhere else this is False and the Exec goes to the
      --  shell, as it always has.
      if Launcher.Applications.Platform.Launch_Native (App) then
         return True;
      end if;

      return Hostkit.Process.Run_Shell_Command (Command, Wait => False, Exit_Status => Status);
   exception
      when others =>
         return False;
   end Launch;

end Launcher.Applications;

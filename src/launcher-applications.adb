with Ada.Characters.Handling;
with Ada.Containers.Indefinite_Hashed_Sets;
with Ada.Directories;
with Ada.Strings.Fixed;
with Ada.Strings.Hash;
with Ada.Strings.Unbounded;
with Ada.Text_IO;

with Hostkit.Environment;
with Hostkit.Fs;
with Hostkit.Process;

with Launcher.Applications.Platform;

package body Launcher.Applications is
   use Ada.Strings.Unbounded;
   use type Hostkit.Fs.Entry_Kind;

   package String_Sets is new Ada.Containers.Indefinite_Hashed_Sets
     (Element_Type        => String,
      Hash                => Ada.Strings.Hash,
      Equivalent_Elements => "=");

   Suffix : constant String := ".desktop";

   function Decode_Escapes (Value : String) return String is
      Result : Unbounded_String;
      I      : Integer := Value'First;
   begin
      while I <= Value'Last loop
         if Value (I) = '\' and then I < Value'Last then
            case Value (I + 1) is
               when 's' => Append (Result, ' ');
               when 'n' => Append (Result, ASCII.LF);
               when 't' => Append (Result, ASCII.HT);
               when 'r' => Append (Result, ASCII.CR);
               when '\' => Append (Result, '\');
               when others =>
                  --  Not a string escape. Exec's own quoting escapes ("\$" and
                  --  the like) pass through to Split_Exec untouched.
                  Append (Result, Value (I .. I + 1));
            end case;
            I := I + 2;
         else
            Append (Result, Value (I));
            I := I + 1;
         end if;
      end loop;
      return To_String (Result);
   end Decode_Escapes;

   function Split_Exec
     (Exec      : String;
      Arguments : out Hostkit.String_Vectors.Vector)
      return Boolean
   is
      Current : Unbounded_String;
      --  An argument has begun: "" is an argument, a run of spaces is not.
      Started : Boolean := False;
      Quoted  : Boolean := False;
      I       : Integer := Exec'First;
   begin
      Arguments.Clear;
      while I <= Exec'Last loop
         declare
            C : constant Character := Exec (I);
         begin
            if Quoted then
               if C = '\'
                 and then I < Exec'Last
                 and then Exec (I + 1) in '"' | '`' | '$' | '\'
               then
                  Append (Current, Exec (I + 1));
                  I := I + 1;
               elsif C = '"' then
                  Quoted := False;
               else
                  Append (Current, C);
               end if;
            elsif C = '"' then
               Quoted  := True;
               Started := True;
            elsif C = ' ' or else C = ASCII.HT then
               if Started then
                  Arguments.Append (Current);
                  Current := Null_Unbounded_String;
                  Started := False;
               end if;
            else
               Append (Current, C);
               Started := True;
            end if;
         end;
         I := I + 1;
      end loop;

      if Quoted then
         Arguments.Clear;
         return False;
      end if;
      if Started then
         Arguments.Append (Current);
      end if;
      return True;
   end Split_Exec;

   function Expand_Field_Codes
     (Arguments : Hostkit.String_Vectors.Vector;
      Name      : String;
      Icon      : String;
      Location  : String)
      return Hostkit.String_Vectors.Vector
   is
      Result : Hostkit.String_Vectors.Vector;

      --  The codes that stand for files or URLs, and the deprecated ones: with
      --  no file to open, each expands to nothing.
      function Is_File_Code (C : Character) return Boolean is
        (C in 'f' | 'F' | 'u' | 'U' | 'd' | 'D' | 'n' | 'N' | 'v' | 'm');
   begin
      for Item of Arguments loop
         declare
            Text : constant String := To_String (Item);
         begin
            if Text'Length = 2 and then Text (Text'First) = '%' and then Is_File_Code (Text (Text'Last)) then
               null;  --  the whole argument was a file list: no argument at all

            elsif Text = "%i" then
               if Icon /= "" then
                  Result.Append (To_Unbounded_String ("--icon"));
                  Result.Append (To_Unbounded_String (Icon));
               end if;

            else
               declare
                  Expanded : Unbounded_String;
                  I        : Integer := Text'First;
               begin
                  while I <= Text'Last loop
                     if Text (I) = '%' and then I < Text'Last then
                        case Text (I + 1) is
                           when '%' => Append (Expanded, '%');
                           when 'c' => Append (Expanded, Name);
                           when 'k' => Append (Expanded, Location);
                           --  %i inside a longer argument: the icon name alone,
                           --  since "--icon" cannot be half of one argument.
                           when 'i' => Append (Expanded, Icon);
                           when others => null;  --  a file code, or unknown
                        end case;
                        I := I + 2;
                     else
                        Append (Expanded, Text (I));
                        I := I + 1;
                     end if;
                  end loop;
                  Result.Append (Expanded);
               end;
            end if;
         end;
      end loop;
      return Result;
   end Expand_Field_Codes;

   --  Whether the ';'-separated List (a trailing ';' is customary) holds Item.
   function List_Contains (List : String; Item : String) return Boolean is
      First : Integer := List'First;
   begin
      if Item = "" then
         return False;
      end if;
      for I in List'First .. List'Last + 1 loop
         if I > List'Last or else List (I) = ';' then
            if List (First .. I - 1) = Item then
               return True;
            end if;
            First := I + 1;
         end if;
      end loop;
      return False;
   end List_Contains;

   function Shown_In
     (Only_Show_In    : String;
      Not_Show_In     : String;
      Current_Desktop : String)
      return Boolean
   is
      Wanted : Boolean := Only_Show_In = "";
      First  : Integer := Current_Desktop'First;
   begin
      for I in Current_Desktop'First .. Current_Desktop'Last + 1 loop
         if I > Current_Desktop'Last or else Current_Desktop (I) = ':' then
            declare
               Desktop : constant String := Current_Desktop (First .. I - 1);
            begin
               if List_Contains (Not_Show_In, Desktop) then
                  return False;
               end if;
               Wanted := Wanted or else List_Contains (Only_Show_In, Desktop);
            end;
            First := I + 1;
         end if;
      end loop;
      return Wanted;
   end Shown_In;

   function Terminal_Prefix
     (Terminal : String;
      Prefix   : out Hostkit.String_Vectors.Vector)
      return Boolean
   is
      --  The terminal's own name: no folder, no ".exe", any case.
      function Simple (Path : String) return String is
         First : Integer := Path'First;
         Last  : Integer := Path'Last;
      begin
         for I in Path'Range loop
            if Hostkit.Fs.Is_Separator (Path (I)) then
               First := I + 1;
            end if;
         end loop;
         if Last - First + 1 > 4
           and then Ada.Characters.Handling.To_Lower (Path (Last - 3 .. Last)) = ".exe"
         then
            Last := Last - 4;
         end if;
         return Ada.Characters.Handling.To_Lower (Path (First .. Last));
      end Simple;

      Name : constant String := Simple (Terminal);

      procedure Add (Item : String) is
      begin
         Prefix.Append (To_Unbounded_String (Item));
      end Add;
   begin
      Prefix.Clear;
      if Name in "x-terminal-emulator" | "xterm" | "uxterm" | "konsole" | "alacritty"
        | "urxvt" | "rxvt" | "ghostty"
      then
         --  xterm's "-e program args...", which the Debian alternative must accept.
         Add ("-e");
      elsif Name in "xfce4-terminal" | "terminator" then
         --  Their "-e" takes one string for a shell; "-x" takes the rest as argv.
         Add ("-x");
      elsif Name in "gnome-terminal" | "kgx" | "ptyxis" | "foot" then
         Add ("--");
      elsif Name = "wezterm" then
         Add ("start");
         Add ("--");
      else
         return False;
      end if;
      return True;
   end Terminal_Prefix;

   --  The terminal Terminal=true entries run in and the arguments before the
   --  command, asked of the host once per scan (it looks the candidates up).
   type Terminal_Choice is record
      Asked     : Boolean := False;
      Available : Boolean := False;
      Program   : Unbounded_String;
      Prefix    : Hostkit.String_Vectors.Vector;
   end record;

   Chosen_Terminal : Terminal_Choice;

   procedure Ensure_Terminal is
   begin
      if not Chosen_Terminal.Asked then
         Chosen_Terminal.Asked := True;
         declare
            Program : constant String := Hostkit.Process.Default_Terminal;
         begin
            Chosen_Terminal.Program := To_Unbounded_String (Program);
            Chosen_Terminal.Available :=
              Program /= "" and then Terminal_Prefix (Program, Chosen_Terminal.Prefix);
         end;
      end if;
   end Ensure_Terminal;

   procedure Parse_Desktop_File
     (Path  : String;
      Id    : String;
      App   : out Application;
      Found : out Boolean)
   is
      File         : Ada.Text_IO.File_Type;
      In_Entry     : Boolean := False;
      Name         : Unbounded_String;
      Exec         : Unbounded_String;
      Try_Exec     : Unbounded_String;
      Work_Dir     : Unbounded_String;
      Comment      : Unbounded_String;
      Icon         : Unbounded_String;
      Only_Show_In : Unbounded_String;
      Not_Show_In  : Unbounded_String;
      Is_App       : Boolean := False;
      Hidden       : Boolean := False;
      In_Terminal  : Boolean := False;
   begin
      App   := (others => <>);
      Found := False;
      Ada.Text_IO.Open (File, Ada.Text_IO.In_File, Path, Form => "shared=no");
      while not Ada.Text_IO.End_Of_File (File) loop
         declare
            Line : constant String :=
              Ada.Strings.Fixed.Trim (Ada.Text_IO.Get_Line (File), Ada.Strings.Both);
            Eq   : constant Natural := Ada.Strings.Fixed.Index (Line, "=");
         begin
            if Line'Length > 0 and then Line (Line'First) = '#' then
               null;  --  a comment
            elsif Line'Length > 0 and then Line (Line'First) = '[' then
               --  Only the first group is the entry; [Desktop Action ...] groups
               --  after it describe other things.
               In_Entry := Line = "[Desktop Entry]";
            elsif In_Entry and then Eq > Line'First then
               declare
                  --  Spaces around '=' are not part of the key or the value.
                  Key : constant String :=
                    Ada.Strings.Fixed.Trim (Line (Line'First .. Eq - 1), Ada.Strings.Right);
                  Val : constant String :=
                    Decode_Escapes (Ada.Strings.Fixed.Trim (Line (Eq + 1 .. Line'Last), Ada.Strings.Left));
               begin
                  if Key = "Name" then
                     Name := To_Unbounded_String (Val);
                  elsif Key = "Exec" then
                     Exec := To_Unbounded_String (Val);
                  elsif Key = "TryExec" then
                     Try_Exec := To_Unbounded_String (Val);
                  elsif Key = "Path" then
                     Work_Dir := To_Unbounded_String (Val);
                  elsif Key = "Comment" then
                     Comment := To_Unbounded_String (Val);
                  elsif Key = "Icon" then
                     Icon := To_Unbounded_String (Val);
                  elsif Key = "Type" then
                     Is_App := Val = "Application";
                  elsif Key = "NoDisplay" or else Key = "Hidden" then
                     Hidden := Hidden or else Val = "true";
                  elsif Key = "Terminal" then
                     In_Terminal := Val = "true";
                  elsif Key = "OnlyShowIn" then
                     Only_Show_In := To_Unbounded_String (Val);
                  elsif Key = "NotShowIn" then
                     Not_Show_In := To_Unbounded_String (Val);
                  end if;
               end;
            end if;
         end;
      end loop;
      Ada.Text_IO.Close (File);

      if not Is_App or else Hidden or else Length (Name) = 0 or else Length (Exec) = 0 then
         return;
      end if;

      --  TryExec names a program the entry needs; without it the entry is for
      --  something not installed (a leftover after an uninstall, say).
      if Length (Try_Exec) > 0 and then not Hostkit.Process.Is_Runnable (To_String (Try_Exec)) then
         return;
      end if;

      if not Shown_In
        (To_String (Only_Show_In),
         To_String (Not_Show_In),
         Hostkit.Environment.Value ("XDG_CURRENT_DESKTOP", Default => ""))
      then
         return;
      end if;

      declare
         Split    : Hostkit.String_Vectors.Vector;
         Expanded : Hostkit.String_Vectors.Vector;
         Command  : Hostkit.String_Vectors.Vector;
      begin
         if not Split_Exec (To_String (Exec), Split) then
            return;  --  an unbalanced quote: no telling what was meant
         end if;
         Expanded := Expand_Field_Codes (Split, To_String (Name), To_String (Icon), Path);
         if Expanded.Is_Empty or else Length (Expanded.First_Element) = 0 then
            return;
         end if;

         if In_Terminal then
            --  A program that needs a terminal (htop, vim) started without one
            --  has nowhere to draw: run it inside one, or not list it at all.
            Ensure_Terminal;
            if not Chosen_Terminal.Available then
               return;
            end if;
            Command := Chosen_Terminal.Prefix;
            Command.Append_Vector (Expanded);
            App.Program := Chosen_Terminal.Program;
         else
            App.Program := Expanded.First_Element;
            Command := Expanded;
            Command.Delete_First;
         end if;

         App.Id        := To_Unbounded_String (Id);
         App.Name      := Name;
         App.Exec      := Exec;
         App.Arguments := Command;
         App.Directory := Work_Dir;
         App.Comment   := Comment;
         App.Icon      := Icon;
         Found := True;
      end;
   exception
      when others =>
         if Ada.Text_IO.Is_Open (File) then
            Ada.Text_IO.Close (File);
         end if;
         App   := (others => <>);
         Found := False;
   end Parse_Desktop_File;

   --  How deep below an "applications" folder entries are looked for. Real
   --  trees are one or two levels deep; the bound is what keeps a linked
   --  folder that leads back up from being walked forever.
   Max_Depth : constant := 8;

   --  Scan Folder (whose entries' ids begin with Id_Prefix) and its subfolders
   --  into Apps, skipping ids already Seen and adding each new one to it.
   procedure Scan_Tree
     (Folder    : String;
      Id_Prefix : String;
      Depth     : Natural;
      Seen      : in out String_Sets.Set;
      Apps      : in out Application_Vectors.Vector)
   is
      use Ada.Directories;
      Search : Search_Type;
      Item   : Directory_Entry_Type;
   begin
      if Hostkit.Fs.Kind_Of (Folder) /= Hostkit.Fs.Directory_Entry then
         return;
      end if;
      Start_Search (Search, Folder, "", [Ordinary_File => True, Directory => True, others => False]);
      while More_Entries (Search) loop
         Get_Next_Entry (Search, Item);
         declare
            Name : constant String := Simple_Name (Item);
         begin
            if Name = "." or else Name = ".." then
               null;

            elsif Kind (Item) = Directory then
               --  The specification's ids: "kde/konsole.desktop" is "kde-konsole.desktop".
               if Depth < Max_Depth then
                  Scan_Tree (Full_Name (Item), Id_Prefix & Name & "-", Depth + 1, Seen, Apps);
               end if;

            elsif Name'Length > Suffix'Length
              and then Name (Name'Last - Suffix'Length + 1 .. Name'Last) = Suffix
            then
               declare
                  Id  : constant String := Id_Prefix & Name;
                  App : Application;
                  Ok  : Boolean;
               begin
                  if not Seen.Contains (Id) then
                     Seen.Insert (Id);
                     Parse_Desktop_File (Full_Name (Item), Id, App, Ok);
                     if Ok then
                        Apps.Append (App);
                     end if;
                  end if;
               end;
            end if;
         end;
      end loop;
      End_Search (Search);
   exception
      when others =>
         null;  --  an unreadable folder holds nothing launchable
   end Scan_Tree;

   procedure Scan_Folder (Folder : String; Apps : in out Application_Vectors.Vector) is
      Seen : String_Sets.Set;
   begin
      Scan_Tree (Folder, "", 0, Seen, Apps);
   end Scan_Folder;

   function Installed return Application_Vectors.Vector is
      Seen : String_Sets.Set;
      Apps : Application_Vectors.Vector;
   begin
      --  Hostkit says where this desktop keeps the data folders whose
      --  "applications" subfolders hold the entries -- XDG_DATA_HOME and
      --  XDG_DATA_DIRS on Linux, highest precedence first -- and nothing on a
      --  host without them.
      for Base of Hostkit.Fs.Application_Data_Directories loop
         Scan_Tree (Hostkit.Fs.Join (To_String (Base), "applications"), "", 0, Seen, Apps);
      end loop;

      --  Whatever the host records natively -- the Start Menu, the .app bundles --
      --  joins what the XDG scan found. On Linux that is nothing, because the XDG scan
      --  IS the native answer there; on Windows and macOS it is everything, because
      --  the XDG scan finds nothing at all.
      for App of Launcher.Applications.Platform.Installed_Native loop
         declare
            Key : constant String := To_String (App.Id);
         begin
            if not Seen.Contains (Key) then
               Seen.Insert (Key);
               Apps.Append (App);
            end if;
         end;
      end loop;

      --  Returned unsorted: the sole caller (Launcher.Model.Load) immediately
      --  re-sorts by launch frequency, so sorting by name here was pure waste.
      return Apps;
   end Installed;

   --  Start Program with Arguments in Directory (the entry's Path=), or in
   --  ours when it names no folder there is.
   function Start_In
     (Program   : String;
      Arguments : Hostkit.String_Vectors.Vector;
      Directory : String)
      return Boolean is
     (if Directory = "" or else Hostkit.Fs.Kind_Of (Directory) /= Hostkit.Fs.Directory_Entry
      then Hostkit.Process.Launch (Program, Arguments)
      else Hostkit.Process.Launch (Program, Arguments, Working_Directory => Directory));

   function Launch (App : Application) return Boolean is
      Started : Boolean := False;
   begin
      --  An entry only the host can start (a Start Menu shortcut) goes to the
      --  host, and its answer is the answer: there is no command line to fall
      --  back on.
      if Launcher.Applications.Platform.Launch_Native (App, Started) then
         return Started;
      end if;

      declare
         Program : constant String := To_String (App.Program);
         --  Hostkit.Process.Launch takes a path: a bare name is looked up first,
         --  so a program not installed is told apart from one that failed.
         Located : constant String :=
           (if Program = "" then ""
            elsif (for some C of Program => Hostkit.Fs.Is_Separator (C)) then Program
            else Hostkit.Process.Locate (Program));
      begin
         if Located = "" then
            return False;
         end if;
         return Start_In (Located, App.Arguments, To_String (App.Directory));
      end;
   exception
      when others =>
         return False;
   end Launch;

end Launcher.Applications;

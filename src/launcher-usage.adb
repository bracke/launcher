with Ada.Directories;
with Ada.Strings.Fixed;
with Ada.Text_IO;

with Hostkit.Environment;
with Hostkit.Fs;
with Hostkit.Host;

package body Launcher.Usage is

   --  A line is "<count> TAB id TAB <id>" or "<count> TAB name TAB <name>". The
   --  old file's lines were "<count> TAB <name>", and are read as name lines.
   Id_Tag   : constant String := "id" & ASCII.HT;
   Name_Tag : constant String := "name" & ASCII.HT;

   function State_Dir return String is
      State : constant String := Hostkit.Environment.Value ("XDG_STATE_HOME", Default => "");
   begin
      --  An explicit XDG_STATE_HOME is honoured on every host: it is how a
      --  user (or a test) moves the state somewhere else.
      if State /= "" then
         return Hostkit.Fs.Join (State, "launcher");
      end if;

      case Hostkit.Host.Current is
         when Hostkit.Host.Windows | Hostkit.Host.MacOS =>
            declare
               Data : constant String := Hostkit.Fs.Application_Data_Directory;
            begin
               return (if Data = "" then "" else Hostkit.Fs.Join (Data, "launcher"));
            end;
         when Hostkit.Host.Linux | Hostkit.Host.Unsupported =>
            declare
               Home : constant String := Hostkit.Fs.Home_Directory;
            begin
               return (if Home = "" then "" else Hostkit.Fs.Join (Home, ".local/state/launcher"));
            end;
      end case;
   end State_Dir;

   function Usage_File return String is
      Dir : constant String := State_Dir;
   begin
      return (if Dir = "" then "" else Hostkit.Fs.Join (Dir, "usage.tsv"));
   end Usage_File;

   function Starts_With (Text, Prefix : String) return Boolean is
     (Text'Length >= Prefix'Length
      and then Text (Text'First .. Text'First + Prefix'Length - 1) = Prefix);

   function Load return Store is
      Result : Store;
      Path   : constant String := Usage_File;
      File   : Ada.Text_IO.File_Type;
   begin
      if Path = "" or else not Ada.Directories.Exists (Path) then
         return Result;
      end if;

      Ada.Text_IO.Open (File, Ada.Text_IO.In_File, Path, Form => "shared=no");
      while not Ada.Text_IO.End_Of_File (File) loop
         declare
            Line : constant String := Ada.Text_IO.Get_Line (File);
            Tab  : constant Natural := Ada.Strings.Fixed.Index (Line, "" & ASCII.HT);
         begin
            if Tab > Line'First then
               declare
                  Rest  : constant String := Line (Tab + 1 .. Line'Last);
                  Value : constant Natural := Natural'Value (Line (Line'First .. Tab - 1));
               begin
                  if Starts_With (Rest, Id_Tag) then
                     if Rest'Length > Id_Tag'Length then
                        Result.Counts.Include (Rest (Rest'First + Id_Tag'Length .. Rest'Last), Value);
                     end if;
                  elsif Starts_With (Rest, Name_Tag) then
                     if Rest'Length > Name_Tag'Length then
                        Result.Legacy.Include (Rest (Rest'First + Name_Tag'Length .. Rest'Last), Value);
                     end if;
                  elsif Rest /= "" then
                     --  The old, name-keyed file.
                     Result.Legacy.Include (Rest, Value);
                  end if;
               exception
                  when others =>
                     null;  --  skip a malformed line
               end;
            end if;
         end;
      end loop;
      Ada.Text_IO.Close (File);
      return Result;
   exception
      when others =>
         if Ada.Text_IO.Is_Open (File) then
            Ada.Text_IO.Close (File);
         end if;
         return Result;
   end Load;

   function Count (S : Store; Id : String; Name : String) return Natural is
   begin
      --  An old name count answers only until it is migrated: the first
      --  launch by id of an application with that name takes it (see
      --  Record_Launch), and after that it is gone.
      if S.Counts.Contains (Id) then
         return S.Counts.Element (Id);
      elsif S.Legacy.Contains (Name) then
         return S.Legacy.Element (Name);
      end if;
      return 0;
   end Count;

   --  Write the store to a temporary file beside the real one and rename it
   --  over: a crash or a full disk part-way through leaves the old counts, not
   --  a truncated file. Hostkit's rename replaces an existing file on Windows
   --  too, where a plain rename refuses to.
   procedure Save (S : Store) is
      Dir  : constant String := State_Dir;
      Path : constant String := Usage_File;
      Temp : constant String := Path & ".tmp";
      File : Ada.Text_IO.File_Type;

      function Image (Value : Natural) return String is
        (Ada.Strings.Fixed.Trim (Natural'Image (Value), Ada.Strings.Both));
   begin
      if Path = "" then
         return;
      end if;
      Ada.Directories.Create_Path (Dir);
      Ada.Text_IO.Create (File, Ada.Text_IO.Out_File, Temp, Form => "shared=no");
      for C in S.Counts.Iterate loop
         Ada.Text_IO.Put_Line
           (File, Image (Count_Maps.Element (C)) & ASCII.HT & Id_Tag & Count_Maps.Key (C));
      end loop;
      for C in S.Legacy.Iterate loop
         Ada.Text_IO.Put_Line
           (File, Image (Count_Maps.Element (C)) & ASCII.HT & Name_Tag & Count_Maps.Key (C));
      end loop;
      Ada.Text_IO.Close (File);

      if not Hostkit.Fs.Replace_File (Source => Temp, Target => Path) then
         --  Nothing replaced: leave the old file as it was, and no stray temp.
         if Ada.Directories.Exists (Temp) then
            Ada.Directories.Delete_File (Temp);
         end if;
      end if;
   exception
      when others =>
         if Ada.Text_IO.Is_Open (File) then
            Ada.Text_IO.Close (File);
         end if;
         begin
            if Ada.Directories.Exists (Temp) then
               Ada.Directories.Delete_File (Temp);
            end if;
         exception
            when others =>
               null;
         end;
   end Save;

   procedure Record_Launch (S : in out Store; Id : String; Name : String) is
      Next : Natural;
   begin
      if Id = "" then
         return;
      end if;
      --  The first launch counted by id carries on from the old name count,
      --  and takes it: the name count is migrated to this id alone, so
      --  another application with the same name starts from nothing rather
      --  than inheriting it as well.
      Next := Count (S, Id, Name) + 1;
      if not S.Counts.Contains (Id) and then S.Legacy.Contains (Name) then
         S.Legacy.Delete (Name);
      end if;
      S.Counts.Include (Id, Next);
      Save (S);
   end Record_Launch;

end Launcher.Usage;

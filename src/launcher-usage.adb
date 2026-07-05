with Ada.Directories;
with Ada.Environment_Variables;
with Ada.Strings.Fixed;
with Ada.Text_IO;

package body Launcher.Usage is

   function Env (Name, Default : String) return String is
   begin
      if Ada.Environment_Variables.Exists (Name)
        and then Ada.Environment_Variables.Value (Name) /= ""
      then
         return Ada.Environment_Variables.Value (Name);
      end if;
      return Default;
   end Env;

   function State_Dir return String is
      Home  : constant String := Env ("HOME", "");
      State : constant String :=
        Env ("XDG_STATE_HOME", (if Home = "" then "" else Home & "/.local/state"));
   begin
      return (if State = "" then "" else State & "/launcher");
   end State_Dir;

   function Usage_File return String is
      Dir : constant String := State_Dir;
   begin
      return (if Dir = "" then "" else Dir & "/usage.tsv");
   end Usage_File;

   function Load return Store is
      Result : Store;
      Path   : constant String := Usage_File;
      File   : Ada.Text_IO.File_Type;
   begin
      if Path = "" or else not Ada.Directories.Exists (Path) then
         return Result;
      end if;

      Ada.Text_IO.Open (File, Ada.Text_IO.In_File, Path);
      while not Ada.Text_IO.End_Of_File (File) loop
         declare
            Line : constant String := Ada.Text_IO.Get_Line (File);
            Tab  : constant Natural := Ada.Strings.Fixed.Index (Line, "" & ASCII.HT);
         begin
            if Tab > Line'First then
               declare
                  Name  : constant String := Line (Tab + 1 .. Line'Last);
                  Value : constant Natural := Natural'Value (Line (Line'First .. Tab - 1));
               begin
                  if Name /= "" then
                     Result.Counts.Include (Name, Value);
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

   function Count (S : Store; Name : String) return Natural is
   begin
      if S.Counts.Contains (Name) then
         return S.Counts.Element (Name);
      end if;
      return 0;
   end Count;

   procedure Save (S : Store) is
      Dir  : constant String := State_Dir;
      Path : constant String := Usage_File;
      File : Ada.Text_IO.File_Type;
   begin
      if Path = "" then
         return;
      end if;
      Ada.Directories.Create_Path (Dir);
      Ada.Text_IO.Create (File, Ada.Text_IO.Out_File, Path);
      for C in S.Counts.Iterate loop
         Ada.Text_IO.Put_Line
           (File,
            Ada.Strings.Fixed.Trim (Natural'Image (Count_Maps.Element (C)), Ada.Strings.Both)
            & ASCII.HT & Count_Maps.Key (C));
      end loop;
      Ada.Text_IO.Close (File);
   exception
      when others =>
         if Ada.Text_IO.Is_Open (File) then
            Ada.Text_IO.Close (File);
         end if;
   end Save;

   procedure Record_Launch (S : in out Store; Name : String) is
   begin
      if Name = "" then
         return;
      end if;
      if S.Counts.Contains (Name) then
         S.Counts.Replace (Name, S.Counts.Element (Name) + 1);
      else
         S.Counts.Insert (Name, 1);
      end if;
      Save (S);
   end Record_Launch;

end Launcher.Usage;

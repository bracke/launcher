with Ada.Containers.Indefinite_Hashed_Sets;
with Ada.Directories;
with Ada.Strings.Hash_Case_Insensitive;
with Ada.Strings.Equal_Case_Insensitive;
with Ada.Strings.Unbounded;

with Hostkit.Environment;
with Hostkit.Process;

package body Launcher.Applications.Platform is
   use Ada.Strings.Unbounded;

   Suffix : constant String := ".lnk";

   --  Windows records an installed application as a shortcut in the Start Menu: one
   --  per-user, one for everybody. Both are read, the per-user one first, so a user's
   --  own shortcut wins over a machine-wide one of the same name.
   Roots : constant array (Positive range <>) of access constant String :=
     [new String'("APPDATA"), new String'("ProgramData")];

   Start_Menu : constant String := "\Microsoft\Windows\Start Menu\Programs";

   --  A shortcut's place in the Start Menu, "Accessories\Notepad.lnk": the same
   --  in the per-user and the machine-wide menu, and compared as Windows compares
   --  names, without case.
   package Place_Sets is new Ada.Containers.Indefinite_Hashed_Sets
     (Element_Type        => String,
      Hash                => Ada.Strings.Hash_Case_Insensitive,
      Equivalent_Elements => Ada.Strings.Equal_Case_Insensitive);

   --  The Start Menu is a tree -- shortcuts sit in per-vendor folders -- so a scan of
   --  the top level alone would find almost nothing.
   --
   --  Place is Root's own place in the menu ("" at the top), and Seen the places
   --  already taken, so a per-user shortcut, read first, hides the machine-wide
   --  one at the same place.
   procedure Scan
     (Root  : String;
      Place : String;
      Seen  : in out Place_Sets.Set;
      Apps  : in out Application_Vectors.Vector)
   is
      use Ada.Directories;
      Search : Search_Type;
      Item   : Directory_Entry_Type;
   begin
      if not Exists (Root) or else Kind (Root) /= Directory then
         return;
      end if;

      Start_Search (Search, Root, "", [Ordinary_File => True, Directory => True, others => False]);
      while More_Entries (Search) loop
         Get_Next_Entry (Search, Item);
         declare
            Name : constant String := Simple_Name (Item);
         begin
            if Name /= "." and then Name /= ".." then
               if Kind (Item) = Directory then
                  Scan (Full_Name (Item), Place & Name & "\", Seen, Apps);

               elsif Name'Length > Suffix'Length
                 and then Name (Name'Last - Suffix'Length + 1 .. Name'Last) = Suffix
               then
                  declare
                     Here : constant String := Place & Name;
                     App  : Application;
                  begin
                     if not Seen.Contains (Here) then
                        Seen.Insert (Here);
                        --  Counted by its place in the menu, which a reinstall
                        --  keeps and which two shortcuts never share.
                        App.Id   := To_Unbounded_String (Here);
                        App.Name :=
                          To_Unbounded_String (Name (Name'First .. Name'Last - Suffix'Length));
                        --  The shortcut's own path, not a command line: Launch_Native
                        --  hands it to ShellExecuteW, which resolves the shortcut and
                        --  starts what it points at. Nothing here has to be quoted,
                        --  and nothing parses it. Program stays "": only the host
                        --  can start this.
                        App.Exec := To_Unbounded_String (Full_Name (Item));
                        Apps.Append (App);
                     end if;
                  end;
               end if;
            end if;
         end;
      end loop;
      End_Search (Search);
   exception
      when others =>
         null;
   end Scan;

   function Installed_Native return Application_Vectors.Vector is
      Apps : Application_Vectors.Vector;
      Seen : Place_Sets.Set;
   begin
      for Root of Roots loop
         declare
            Base : constant String := Hostkit.Environment.Value (Root.all, Default => "");
         begin
            if Base /= "" then
               Scan (Base & Start_Menu, "", Seen, Apps);
            end if;
         end;
      end loop;

      return Apps;
   exception
      when others =>
         return Apps;
   end Installed_Native;

   --  A .lnk whose path routinely contains spaces cannot be got to cmd as a quoted
   --  command line -- the C runtime escapes the quotes on the way in, and cmd strips the
   --  ones it finds. Hostkit hands the path itself to the shell API, and nothing quotes
   --  or parses anything. Its answer is final: the raw path is not a command line, and
   --  handing it to a shell after a failure would only split it at its first space.
   function Launch_Native (App : Application; Started : out Boolean) return Boolean is
   begin
      Started := False;
      if App.Program /= Null_Unbounded_String then
         return False;
      end if;
      Started := Hostkit.Process.Open_Native (To_String (App.Exec));
      return True;
   end Launch_Native;

end Launcher.Applications.Platform;

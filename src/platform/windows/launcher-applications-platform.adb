with Ada.Directories;
with Ada.Environment_Variables;
with Ada.Strings.Unbounded;

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

   --  The Start Menu is a tree -- shortcuts sit in per-vendor folders -- so a scan of
   --  the top level alone would find almost nothing.
   procedure Scan (Root : String; Apps : in out Application_Vectors.Vector) is
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
                  Scan (Full_Name (Item), Apps);

               elsif Name'Length > Suffix'Length
                 and then Name (Name'Last - Suffix'Length + 1 .. Name'Last) = Suffix
               then
                  Apps.Append
                    (Application'
                       (Name    =>
                          To_Unbounded_String (Name (Name'First .. Name'Last - Suffix'Length)),
                        --  The shortcut's own path, not a command line: Launch_Native
                        --  hands it to ShellExecuteW, which resolves the shortcut and
                        --  starts what it points at. Nothing here has to be quoted,
                        --  and nothing parses it.
                        Exec    => To_Unbounded_String (Full_Name (Item)),
                        Comment => Null_Unbounded_String,
                        Icon    => Null_Unbounded_String));
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
   begin
      for Root of Roots loop
         if Ada.Environment_Variables.Exists (Root.all) then
            Scan (Ada.Environment_Variables.Value (Root.all) & Start_Menu, Apps);
         end if;
      end loop;

      return Apps;
   exception
      when others =>
         return Apps;
   end Installed_Native;

   --  A .lnk whose path routinely contains spaces cannot be got to cmd as a quoted
   --  command line -- the C runtime escapes the quotes on the way in, and cmd strips the
   --  ones it finds. Hostkit hands the path itself to the shell API, and nothing quotes
   --  or parses anything.
   function Launch_Native (App : Application) return Boolean is
   begin
      return Hostkit.Process.Open_Native (To_String (App.Exec));
   end Launch_Native;

end Launcher.Applications.Platform;

with Ada.Directories;
with Ada.Environment_Variables;
with Ada.Strings.Unbounded;
with Ada.Strings.UTF_Encoding.Wide_Strings;

with Interfaces.C;

with System.Storage_Elements;
with System;

package body Launcher.Applications.Platform is
   use Ada.Strings.Unbounded;
   use type System.Storage_Elements.Integer_Address;

   Suffix : constant String := ".lnk";

   --  Windows records an installed application as a shortcut in the Start Menu: one
   --  per-user, one for everybody. Both are read, the per-user one first, so a user's
   --  own shortcut wins over a machine-wide one of the same name.
   Roots : constant array (Positive range <>) of access constant String :=
     [new String'("APPDATA"), new String'("ProgramData")];

   Start_Menu : constant String := "\Microsoft\Windows\Start Menu\Programs";

   SW_Show_Normal : constant Interfaces.C.int := 1;

   --  Returns > 32 on success. It is an HINSTANCE for historical reasons only; the
   --  value means nothing else.
   function Shell_Execute
     (Window     : System.Address;
      Operation  : System.Address;
      File       : System.Address;
      Parameters : System.Address;
      Directory  : System.Address;
      Show       : Interfaces.C.int)
      return System.Address
     with Import => True, Convention => Stdcall, External_Name => "ShellExecuteW";

   function Wide (Value : String) return Wide_String is
     (Ada.Strings.UTF_Encoding.Wide_Strings.Decode (Value) & Wide_Character'Val (0));

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

   function Launch_Native (App : Application) return Boolean is
      Path      : constant String := To_String (App.Exec);
      Wide_Path : aliased Wide_String := Wide (Path);
      Operation : aliased Wide_String := Wide ("open");
      Result    : System.Address;
   begin
      if Path = "" then
         return False;
      end if;

      Result :=
        Shell_Execute
          (Window     => System.Null_Address,
           Operation  => Operation'Address,
           File       => Wide_Path'Address,
           Parameters => System.Null_Address,
           Directory  => System.Null_Address,
           Show       => SW_Show_Normal);

      --  Anything at or below 32 is one of the documented failure codes.
      return System.Storage_Elements.To_Integer (Result) > 32;
   exception
      when others =>
         return False;
   end Launch_Native;

end Launcher.Applications.Platform;

with Ada.Directories;
with Ada.Environment_Variables;
with Ada.Strings.Unbounded;

package body Launcher.Applications.Platform is
   use Ada.Strings.Unbounded;

   Suffix : constant String := ".app";

   --  An application on macOS is a directory whose name ends in ".app", not a file
   --  describing one. The bundle is the application.
   Roots : constant array (Positive range <>) of access constant String :=
     [new String'("/Applications"),
      new String'("/Applications/Utilities"),
      new String'("/System/Applications"),
      new String'("/System/Applications/Utilities")];

   --  Wrap a path for /bin/sh. Application paths routinely contain spaces -- "Visual
   --  Studio Code.app" -- so an unquoted one would reach the shell as several
   --  arguments and launch nothing.
   function Shell_Quote (Value : String) return String is
      Result : Unbounded_String := To_Unbounded_String ("'");
   begin
      for Character_Value of Value loop
         if Character_Value = ''' then
            Append (Result, "'\''");
         else
            Append (Result, Character_Value);
         end if;
      end loop;
      Append (Result, "'");
      return To_String (Result);
   end Shell_Quote;

   procedure Scan (Root : String; Apps : in out Application_Vectors.Vector) is
      use Ada.Directories;
      Search : Search_Type;
      Item   : Directory_Entry_Type;
   begin
      if not Exists (Root) or else Kind (Root) /= Directory then
         return;
      end if;

      Start_Search (Search, Root, "*" & Suffix, [Directory => True, others => False]);
      while More_Entries (Search) loop
         Get_Next_Entry (Search, Item);
         declare
            Name : constant String := Simple_Name (Item);
            Path : constant String := Full_Name (Item);
         begin
            if Name'Length > Suffix'Length then
               Apps.Append
                 (Application'
                    (Name    =>
                       To_Unbounded_String (Name (Name'First .. Name'Last - Suffix'Length)),
                     --  "open" is how macOS launches a bundle: handing the shell the
                     --  bundle directory itself would only try to execute a directory.
                     Exec    => To_Unbounded_String ("open " & Shell_Quote (Path)),
                     Comment => Null_Unbounded_String,
                     Icon    => Null_Unbounded_String));
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
      Home : constant String :=
        (if Ada.Environment_Variables.Exists ("HOME")
         then Ada.Environment_Variables.Value ("HOME")
         else "");
   begin
      for Root of Roots loop
         Scan (Root.all, Apps);
      end loop;

      if Home /= "" then
         Scan (Home & "/Applications", Apps);
      end if;

      return Apps;
   exception
      when others =>
         return Apps;
   end Installed_Native;

   --  macOS launches a bundle through "open", which the shell runs perfectly well,
   --  so there is nothing here the shell cannot already do.
   function Launch_Native (App : Application) return Boolean is
      pragma Unreferenced (App);
   begin
      return False;
   end Launch_Native;

end Launcher.Applications.Platform;

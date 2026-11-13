with Ada.Directories;
with Ada.Strings.Unbounded;

with Hostkit.Fs;

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
               declare
                  App : Application;
               begin
                  --  The bundle's path is what it is: two bundles can share a name.
                  App.Id   := To_Unbounded_String (Path);
                  App.Name := To_Unbounded_String (Name (Name'First .. Name'Last - Suffix'Length));
                  --  "open" is how macOS launches a bundle: running the bundle
                  --  directory itself would only try to execute a directory. The
                  --  path is an argument of its own, so a space in it is just a space.
                  App.Program := To_Unbounded_String ("open");
                  App.Arguments.Append (To_Unbounded_String (Path));
                  App.Exec := To_Unbounded_String ("open " & Path);
                  Apps.Append (App);
               end;
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
      Home : constant String := Hostkit.Fs.Home_Directory;
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

   --  macOS launches a bundle through "open", an ordinary program Launch starts
   --  with the bundle as its argument, so there is nothing native to do here.
   function Launch_Native (App : Application; Started : out Boolean) return Boolean is
      pragma Unreferenced (App);
   begin
      Started := False;
      return False;
   end Launch_Native;

end Launcher.Applications.Platform;

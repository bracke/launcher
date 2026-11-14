with Ada.Directories;
with Ada.Exceptions;
with Ada.Strings.Unbounded;
with Ada.Text_IO;

with Hostkit.Fs;

with Launcher.Messages;
with Launcher.Native_Entries;

package body Launcher.Applications.Platform is
   use Ada.Strings.Unbounded;

   Suffix : constant String := ".app";

   --  An application on macOS is a directory whose name ends in ".app", not a file
   --  describing one. The bundle is the application.
   --
   --  /Applications and ~/Applications are scanned with the plain folders in them
   --  (Utilities, and the folders vendors install into: "Microsoft Office",
   --  "Adobe ...") down to Launcher.Native_Entries.Max_Bundle_Folder_Depth -- never
   --  into a bundle, whose insides are the application's own. The system's folders
   --  hold bundles only at their top and in Utilities.
   type Root is record
      Path    : access constant String;
      Recurse : Boolean;
   end record;

   Roots : constant array (Positive range <>) of Root :=
     [(new String'("/Applications"), True),
      (new String'("/System/Applications"), False),
      (new String'("/System/Applications/Utilities"), False)];

   --  Add the bundles in Folder, Depth folders below its scan's root, and -- when
   --  Recurse -- those in the plain folders below it.
   procedure Scan
     (Folder  : String;
      Recurse : Boolean;
      Depth   : Natural;
      Apps    : in out Application_Vectors.Vector)
   is
      use Ada.Directories;
      Search  : Search_Type;
      Item    : Directory_Entry_Type;
      Started : Boolean := False;
   begin
      if not Exists (Folder) or else Kind (Folder) /= Directory then
         return;
      end if;

      Start_Search (Search, Folder, "", [Directory => True, others => False]);
      Started := True;
      while More_Entries (Search) loop
         Get_Next_Entry (Search, Item);
         declare
            Name : constant String := Simple_Name (Item);
            Path : constant String := Full_Name (Item);
         begin
            if Name = "." or else Name = ".." then
               null;

            elsif Launcher.Native_Entries.Is_Bundle (Name) then
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

            elsif Recurse and then Launcher.Native_Entries.Descend_Into (Name, Depth + 1) then
               Scan (Path, Recurse, Depth + 1, Apps);
            end if;
         end;
      end loop;
      End_Search (Search);
   exception
      --  A folder that cannot be read (or vanishes mid-scan) holds nothing more
      --  that can be listed: what was found before it stays, the search is ended
      --  rather than left open, and the other folders are still scanned.
      --  Standard error says which folder and why.
      when Error : others =>
         if Started then
            begin
               End_Search (Search);
            exception
               when others =>
                  null;
            end;
         end if;
         Ada.Text_IO.Put_Line
           (Ada.Text_IO.Standard_Error,
            Launcher.Messages.Text ("app.name") & ": " & Folder & ": "
            & Launcher.Messages.Text ("diagnostic.applications_folder.unreadable")
            & " (" & Ada.Exceptions.Exception_Name (Error) & ": " & Ada.Exceptions.Exception_Message (Error) & ")");
   end Scan;

   function Installed_Native return Application_Vectors.Vector is
      Apps : Application_Vectors.Vector;
      Home : constant String := Hostkit.Fs.Home_Directory;
   begin
      for Item of Roots loop
         Scan (Item.Path.all, Item.Recurse, 0, Apps);
      end loop;

      if Home /= "" then
         Scan (Home & "/Applications", Recurse => True, Depth => 0, Apps => Apps);
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

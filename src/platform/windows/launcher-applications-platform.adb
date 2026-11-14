with Ada.Containers.Indefinite_Hashed_Sets;
with Ada.Directories;
with Ada.Exceptions;
with Ada.Streams.Stream_IO;
with Ada.Strings.Hash_Case_Insensitive;
with Ada.Strings.Equal_Case_Insensitive;
with Ada.Strings.Unbounded;
with Ada.Text_IO;

with Hostkit.Environment;
with Hostkit.Process;

with Launcher.Messages;
with Launcher.Native_Entries;

package body Launcher.Applications.Platform is
   use Ada.Strings.Unbounded;
   use type Launcher.Native_Entries.Shortcut_Kind;

   --  Windows records an installed application as a shortcut in the Start Menu: one
   --  per-user, one for everybody. Both are read, the per-user one first, so a user's
   --  own shortcut wins over a machine-wide one of the same name.
   --
   --  A shortcut is a shell link (.lnk), an Internet shortcut (.url -- how Steam and
   --  other stores install games) or a ClickOnce reference (.appref-ms); suffixes are
   --  compared as Windows compares names, without case, so NOTEPAD.LNK is one too.
   --
   --  Not read: Microsoft Store (UWP/MSIX) applications. They have no file in the
   --  Start Menu folders; the shell lists them in its virtual AppsFolder
   --  (shell:AppsFolder), which is reached only through the shell's COM interfaces
   --  (IShellItem / IShellFolder) or PowerShell's Get-StartApps -- neither of which
   --  the launcher uses. See README.md, "Windows".
   Roots : constant array (Positive range <>) of access constant String :=
     [new String'("APPDATA"), new String'("ProgramData")];

   Start_Menu : constant String := "\Microsoft\Windows\Start Menu\Programs";

   --  An Internet shortcut is a few lines of INI; more than this is not one.
   Max_Internet_Shortcut_Size : constant := 64 * 1024;

   --  The contents of the Internet shortcut at Path, up to
   --  Max_Internet_Shortcut_Size bytes; "" when it cannot be read.
   function Read_Internet_Shortcut (Path : String) return String is
      use Ada.Streams.Stream_IO;
      File   : File_Type;
      Length : Natural;
   begin
      Open (File, In_File, Path, Form => "shared=yes");
      Length := Natural (Long_Long_Integer'Min (Long_Long_Integer (Size (File)), Max_Internet_Shortcut_Size));
      declare
         Text : String (1 .. Length);
      begin
         String'Read (Stream (File), Text);
         Close (File);
         return Text;
      end;
   exception
      when others =>
         if Is_Open (File) then
            Close (File);
         end if;
         return "";
   end Read_Internet_Shortcut;

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
      Search  : Search_Type;
      Item    : Directory_Entry_Type;
      Started : Boolean := False;
   begin
      if not Exists (Root) or else Kind (Root) /= Directory then
         return;
      end if;

      Start_Search (Search, Root, "", [Ordinary_File => True, Directory => True, others => False]);
      Started := True;
      while More_Entries (Search) loop
         Get_Next_Entry (Search, Item);
         declare
            Name      : constant String := Simple_Name (Item);
            Shortcut  : constant Launcher.Native_Entries.Shortcut_Kind :=
              Launcher.Native_Entries.Shortcut_Kind_Of (Name);
         begin
            if Name /= "." and then Name /= ".." then
               if Kind (Item) = Directory then
                  Scan (Full_Name (Item), Place & Name & "\", Seen, Apps);

               elsif Shortcut /= Launcher.Native_Entries.Not_A_Shortcut then
                  declare
                     Here : constant String := Place & Name;
                     Path : constant String := Full_Name (Item);
                     --  What the host opens: the shortcut file itself, which
                     --  ShellExecuteW resolves (a shell link) or hands to its
                     --  handler (a ClickOnce reference) -- or, for an Internet
                     --  shortcut, the URL it names, which the host opens with
                     --  that URL's own handler (a browser, steam://, ...).
                     Target : constant String :=
                       (if Shortcut = Launcher.Native_Entries.Internet_Shortcut
                        then Launcher.Native_Entries.Internet_Shortcut_URL (Read_Internet_Shortcut (Path))
                        else Path);
                     App  : Application;
                  begin
                     --  An Internet shortcut that names no URL opens nothing, and
                     --  does not hide a machine-wide one at the same place.
                     if Target /= "" and then not Seen.Contains (Here) then
                        Seen.Insert (Here);
                        --  Counted by its place in the menu, which a reinstall
                        --  keeps and which two shortcuts never share.
                        App.Id   := To_Unbounded_String (Here);
                        App.Name := To_Unbounded_String (Launcher.Native_Entries.Display_Name (Name));
                        --  A path or a URL, not a command line: Launch_Native hands
                        --  it to ShellExecuteW, and nothing here has to be quoted,
                        --  and nothing parses it. Program stays "": only the host
                        --  can start this.
                        App.Exec := To_Unbounded_String (Target);
                        Apps.Append (App);
                     end if;
                  end;
               end if;
            end if;
         end;
      end loop;
      End_Search (Search);
   exception
      --  A folder that cannot be read (or vanishes mid-scan) holds nothing more
      --  that can be listed: what was found before it stays, the search is
      --  ended rather than left open, and the scan of the rest of the menu goes
      --  on. Standard error says which folder and why.
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
            Launcher.Messages.Text ("app.name") & ": " & Root & ": "
            & Launcher.Messages.Text ("diagnostic.start_menu.unreadable")
            & " (" & Ada.Exceptions.Exception_Name (Error) & ": " & Ada.Exceptions.Exception_Message (Error) & ")");
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

   --  A shortcut whose path routinely contains spaces cannot be got to cmd as a quoted
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

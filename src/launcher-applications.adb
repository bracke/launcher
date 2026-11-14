with Ada.Containers.Indefinite_Hashed_Sets;
with Ada.Strings.Hash;
with Ada.Strings.Unbounded;

with Hostkit.Desktop_Entries;
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

   --  The table is the host's, shared with every program that runs a
   --  command in a terminal.
   function Terminal_Prefix
     (Terminal : String;
      Prefix   : out Hostkit.String_Vectors.Vector)
      return Boolean
      renames Hostkit.Process.Terminal_Program_Prefix;

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

   --  The application a listed desktop entry starts: its Exec made into a
   --  command (no file to open, so the file codes expand to nothing), and a
   --  Terminal=true entry put inside the terminal. False when there is
   --  nothing to start: a program that needs a terminal (htop, vim) started
   --  without one has nowhere to draw, so it is not listed at all.
   function To_Application
     (Item : Hostkit.Desktop_Entries.Desktop_Entry;
      App  : out Application)
      return Boolean
   is
      Command      : Hostkit.String_Vectors.Vector;
      Target_Field : Boolean;
      Arguments    : Hostkit.String_Vectors.Vector;
   begin
      App := (others => <>);
      if not Hostkit.Desktop_Entries.Command_For
        (Exec         => To_String (Item.Exec),
         Name         => To_String (Item.Name),
         Icon         => To_String (Item.Icon),
         Location     => To_String (Item.Location),
         Targets      => Hostkit.String_Vectors.Empty_Vector,
         Command      => Command,
         Target_Field => Target_Field)
      then
         return False;
      end if;

      if Item.Terminal then
         Ensure_Terminal;
         if not Chosen_Terminal.Available then
            return False;
         end if;
         App.Program := Chosen_Terminal.Program;
         Arguments := Chosen_Terminal.Prefix;
         Arguments.Append_Vector (Command);
      else
         App.Program := Command.First_Element;
         Arguments := Command;
         Arguments.Delete_First;
      end if;

      App.Id        := Item.Id;
      App.Name      := Item.Name;
      App.Exec      := Item.Exec;
      App.Arguments := Arguments;
      App.Directory := Item.Working_Directory;
      App.Comment   := Item.Comment;
      App.Icon      := Item.Icon;
      return True;
   end To_Application;

   --  The launchable applications of the entries Folders hold, read by
   --  Hostkit.Desktop_Entries in the locale messages are shown in; Seen
   --  receives their ids.
   procedure Scan_Folders
     (Folders : Hostkit.String_Vectors.Vector;
      Seen    : in out String_Sets.Set;
      Apps    : in out Application_Vectors.Vector)
   is
   begin
      for Item of Hostkit.Desktop_Entries.Scan (Folders, Hostkit.Desktop_Entries.Message_Locale_Candidates) loop
         declare
            App : Application;
         begin
            Seen.Include (To_String (Item.Id));
            if To_Application (Item, App) then
               Apps.Append (App);
            end if;
         end;
      end loop;
   end Scan_Folders;

   procedure Scan_Folder (Folder : String; Apps : in out Application_Vectors.Vector) is
      Seen    : String_Sets.Set;
      Folders : Hostkit.String_Vectors.Vector;
   begin
      Folders.Append (To_Unbounded_String (Folder));
      Scan_Folders (Folders, Seen, Apps);
   end Scan_Folder;

   function Installed return Application_Vectors.Vector is
      Seen : String_Sets.Set;
      Apps : Application_Vectors.Vector;
   begin
      --  Hostkit says where this desktop keeps the "applications" folders
      --  that hold the entries -- under XDG_DATA_HOME and XDG_DATA_DIRS on
      --  Linux, highest precedence first -- and nothing on a host without them.
      Scan_Folders (Hostkit.Desktop_Entries.Application_Folders, Seen, Apps);

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

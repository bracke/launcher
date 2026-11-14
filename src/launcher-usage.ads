private with Ada.Containers.Indefinite_Hashed_Maps;
private with Ada.Strings.Hash;

--  Persistent per-application launch counts, so the launcher can float the
--  applications you use most to the top of the list.
--
--  Counted by application id (Launcher.Applications.Application.Id: the
--  desktop-file id, the Start Menu place, the bundle path), not by display
--  name -- two entries can both be called "Terminal", and counting them
--  together floated the one never launched. The counts used to be kept by
--  name; a name-keyed count read from such a file still answers for an
--  application that has no count of its own yet, until the first application
--  of that name is launched: that one takes the count over, and it is removed,
--  so the others of the same name start from nothing.
--
--  Stored as a small tab-separated file in the host's per-user state place:
--  $XDG_STATE_HOME/launcher when that is set, else ~/.local/state/launcher on
--  Linux and the host's application-data folder (Hostkit.Fs.
--  Application_Data_Directory) elsewhere -- there is no ~/.local on Windows,
--  and no HOME, so a launch there was never remembered.
package Launcher.Usage is

   type Store is private;

   --  Read the usage counts from disk (an empty store when none exists).
   --
   --  @return The loaded usage store.
   function Load return Store;

   --  The recorded launch count for an application.
   --
   --  @param S The usage store.
   --  @param Id The application's id.
   --  @param Name The application's display name, for a count recorded by name.
   --  @return How many times the application has been launched (0 if never).
   function Count (S : Store; Id : String; Name : String) return Natural;

   --  Increment an application's launch count and persist the store.
   --
   --  @param S The usage store.
   --  @param Id The application's id.
   --  @param Name The application's display name, whose old count it carries on from.
   procedure Record_Launch (S : in out Store; Id : String; Name : String);

   --  The file the counts are kept in, or "" where the host names no place.
   --
   --  @return The usage file's path.
   function Usage_File return String;

private

   package Count_Maps is new Ada.Containers.Indefinite_Hashed_Maps
     (Key_Type        => String,
      Element_Type    => Natural,
      Hash            => Ada.Strings.Hash,
      Equivalent_Keys => "=");

   type Store is record
      Counts : Count_Maps.Map;  --  by application id
      Legacy : Count_Maps.Map;  --  by display name, from the old file
   end record;

end Launcher.Usage;

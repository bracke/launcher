private with Ada.Containers.Indefinite_Hashed_Maps;
private with Ada.Strings.Hash;

--  Persistent per-application launch counts, so the launcher can float the
--  applications you use most to the top of the list. Keyed by display name and
--  stored as a small tab-separated file under the XDG state directory.
package Launcher.Usage is

   type Store is private;

   --  Read the usage counts from disk (an empty store when none exists).
   --
   --  @return The loaded usage store.
   function Load return Store;

   --  The recorded launch count for an application.
   --
   --  @param S The usage store.
   --  @param Name The application's display name.
   --  @return How many times the application has been launched (0 if never).
   function Count (S : Store; Name : String) return Natural;

   --  Increment an application's launch count and persist the store.
   --
   --  @param S The usage store.
   --  @param Name The application's display name.
   procedure Record_Launch (S : in out Store; Name : String);

private

   package Count_Maps is new Ada.Containers.Indefinite_Hashed_Maps
     (Key_Type        => String,
      Element_Type    => Natural,
      Hash            => Ada.Strings.Hash,
      Equivalent_Keys => "=");

   type Store is record
      Counts : Count_Maps.Map;
   end record;

end Launcher.Usage;

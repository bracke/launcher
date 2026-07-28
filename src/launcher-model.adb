with Ada.Characters.Handling;
with Ada.Containers.Vectors;
with Ada.Strings.Unbounded;

package body Launcher.Model is
   use Ada.Strings.Unbounded;

   Icon_Pixel_Size : constant := 48;

   procedure Load (M : in out State) is

      --  Precompute each application's launch count and lowercased name once,
      --  then sort an index permutation, so the comparison neither queries the
      --  usage store (two hashed lookups of the full name) nor lowercases names
      --  on every one of the sort's O(N log N) comparisons.
      type Sort_Key is record
         Count      : Natural;
         Name_Lower : Unbounded_String;
      end record;

      package Key_Vectors is new Ada.Containers.Vectors (Positive, Sort_Key);
      package Index_Vectors is new Ada.Containers.Vectors (Positive, Positive);

      Keys   : Key_Vectors.Vector;
      Order  : Index_Vectors.Vector;
      Sorted : Applications.Application_Vectors.Vector;

      --  Most-launched first; ties keep name order. Names are unique (Installed
      --  deduplicates on name), so this is a strict total order.
      function More_Used (Left, Right : Positive) return Boolean is
      begin
         if Keys (Left).Count /= Keys (Right).Count then
            return Keys (Left).Count > Keys (Right).Count;
         end if;
         return Keys (Left).Name_Lower < Keys (Right).Name_Lower;
      end More_Used;

      package Usage_Sorting is new Index_Vectors.Generic_Sorting ("<" => More_Used);
   begin
      M.Apps  := Applications.Installed;
      M.Usage := Launcher.Usage.Load;

      for I in M.Apps.First_Index .. M.Apps.Last_Index loop
         Keys.Append
           (Sort_Key'
              (Count      =>
                 Launcher.Usage.Count (M.Usage, To_String (M.Apps (I).Name)),
               Name_Lower =>
                 To_Unbounded_String
                   (Ada.Characters.Handling.To_Lower (To_String (M.Apps (I).Name)))));
         Order.Append (I);
      end loop;

      Usage_Sorting.Sort (Order);

      for I of Order loop
         Sorted.Append (M.Apps (I));
      end loop;
      Applications.Application_Vectors.Move (Target => M.Apps, Source => Sorted);

      M.Icons.Clear;
      for A of M.Apps loop
         M.Icons.Append (Launcher.Icons.Load (To_String (A.Icon), Icon_Pixel_Size));
      end loop;
   end Load;

   function Commands (M : State) return Guikit.Command_Palette.Command_Vectors.Vector is
      Result : Guikit.Command_Palette.Command_Vectors.Vector;
   begin
      for I in M.Apps.First_Index .. M.Apps.Last_Index loop
         declare
            A    : constant Applications.Application := M.Apps.Element (I);
            Icon : constant Launcher.Icons.Loaded_Icon :=
              (if I <= Natural (M.Icons.Length) then M.Icons.Element (I)
               else (Width => 0, Height => 0, Pixels => <>));
         begin
            Result.Append
              (Guikit.Command_Palette.Command'
                 (Id          => I,
                  Identifier  => A.Name,
                  Label       => A.Name,
                  Description => A.Comment,
                  Shortcut    => Null_Unbounded_String,
                  Enabled     => True,
                  Icon        =>
                    (Width  => Icon.Width,
                     Height => Icon.Height,
                     Pixels => Icon.Pixels)));
         end;
      end loop;
      return Result;
   end Commands;

   function Application_For
     (M   : State;
      Id  : Natural;
      App : out Applications.Application)
      return Boolean
   is
   begin
      App := (others => Null_Unbounded_String);
      if Id in 1 .. Natural (M.Apps.Length) then
         App := M.Apps.Element (Id);
         return True;
      end if;
      return False;
   end Application_For;

   procedure Record_Launch (M : in out State; App : Applications.Application) is
   begin
      Launcher.Usage.Record_Launch (M.Usage, To_String (App.Name));
   end Record_Launch;

end Launcher.Model;

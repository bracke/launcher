with Ada.Characters.Handling;
with Ada.Strings.Unbounded;

package body Launcher.Model is
   use Ada.Strings.Unbounded;

   Icon_Pixel_Size : constant := 48;

   procedure Load (M : in out State) is

      --  Order the most-launched applications first; ties keep name order.
      function More_Used (Left, Right : Applications.Application) return Boolean is
         Lc : constant Natural := Launcher.Usage.Count (M.Usage, To_String (Left.Name));
         Rc : constant Natural := Launcher.Usage.Count (M.Usage, To_String (Right.Name));
      begin
         if Lc /= Rc then
            return Lc > Rc;
         end if;
         return Ada.Characters.Handling.To_Lower (To_String (Left.Name))
                < Ada.Characters.Handling.To_Lower (To_String (Right.Name));
      end More_Used;

      package Usage_Sorting is
        new Applications.Application_Vectors.Generic_Sorting ("<" => More_Used);
   begin
      M.Apps  := Applications.Installed;
      M.Usage := Launcher.Usage.Load;
      Usage_Sorting.Sort (M.Apps);

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

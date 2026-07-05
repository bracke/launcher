with Ada.Strings.Unbounded;

package body Launcher.Model is
   use Ada.Strings.Unbounded;

   procedure Load (M : in out State) is
   begin
      M.Apps     := Applications.Installed;
      M.Query    := Null_Unbounded_String;
      M.Selected := 1;
      M.Offset   := 0;
   end Load;

   function Results (M : State) return Guikit.Palette.Item_Vectors.Vector is
      Items : Guikit.Palette.Item_Vectors.Vector;
   begin
      for I in M.Apps.First_Index .. M.Apps.Last_Index loop
         declare
            A : constant Applications.Application := M.Apps.Element (I);
         begin
            Items.Append
              (Guikit.Palette.Item'
                 (Id          => I,
                  Identifier  => A.Name,
                  Label       => A.Name,
                  Description => A.Comment,
                  Shortcut    => Null_Unbounded_String,
                  Enabled     => True,
                  Score       => 0));
         end;
      end loop;
      return Guikit.Palette.Search (To_String (M.Query), Items);
   end Results;

   procedure Insert (M : in out State; Text : String) is
   begin
      Append (M.Query, Text);
      M.Selected := 1;
      M.Offset   := 0;
   end Insert;

   procedure Backspace (M : in out State) is
      S    : constant String := To_String (M.Query);
      Last : Integer := S'Last;
   begin
      if S'Length = 0 then
         return;
      end if;
      --  Step back over UTF-8 continuation bytes so a whole codepoint is removed.
      while Last > S'First and then Character'Pos (S (Last)) in 16#80# .. 16#BF# loop
         Last := Last - 1;
      end loop;
      M.Query    := To_Unbounded_String (S (S'First .. Last - 1));
      M.Selected := 1;
      M.Offset   := 0;
   end Backspace;

   procedure Move_Selection (M : in out State; Delta_Rows : Integer) is
      Count : constant Natural := Natural (Results (M).Length);
      Moved : Integer;
   begin
      if Count = 0 then
         M.Selected := 0;
         return;
      end if;
      Moved := Integer'Max (1, Integer'Min (Integer (M.Selected) + Delta_Rows, Count));
      M.Selected := Natural (Moved);
   end Move_Selection;

   function Selected_Application
     (M   : State;
      App : out Applications.Application)
      return Boolean
   is
      Ranked : constant Guikit.Palette.Item_Vectors.Vector := Results (M);
   begin
      App := (others => Null_Unbounded_String);
      if M.Selected in 1 .. Natural (Ranked.Length) then
         App := M.Apps.Element (Ranked.Element (M.Selected).Id);
         return True;
      end if;
      return False;
   end Selected_Application;

end Launcher.Model;

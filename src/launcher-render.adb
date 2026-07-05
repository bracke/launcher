with Ada.Strings.Unbounded;
with System;

with Guikit.Utf8;
with Guikit.Widgets;

package body Launcher.Render is
   use Ada.Strings.Unbounded;
   use type Textrender.Status_Code;

   --  Decode the UTF-8 codepoint starting at Start; Next is the index of the
   --  byte after it. Malformed input is treated one byte at a time.
   procedure Decode_Next
     (S     : String;
      Start : Integer;
      CP    : out Natural;
      Next  : out Integer)
   is
      function B (I : Integer) return Natural is (Character'Pos (S (I)));
      B0 : constant Natural := B (Start);
   begin
      if B0 < 16#80# then
         CP := B0;
         Next := Start + 1;
      elsif B0 < 16#E0# and then Start + 1 <= S'Last then
         CP := ((B0 mod 32) * 64) + (B (Start + 1) mod 64);
         Next := Start + 2;
      elsif B0 < 16#F0# and then Start + 2 <= S'Last then
         CP := ((B0 mod 16) * 4096) + ((B (Start + 1) mod 64) * 64) + (B (Start + 2) mod 64);
         Next := Start + 3;
      elsif Start + 3 <= S'Last then
         CP := ((B0 mod 8) * 262_144) + ((B (Start + 1) mod 64) * 4096)
               + ((B (Start + 2) mod 64) * 64) + (B (Start + 3) mod 64);
         Next := Start + 4;
      else
         CP := B0;
         Next := Start + 1;
      end if;
   end Decode_Next;

   function Build_Glyphs
     (Text        : in out Textrender.Renderer;
      Commands    : Guikit.Draw.Text_Command_Vectors.Vector;
      Line_Height : Positive)
      return Guikit.Draw.Text_Render_Result
   is
      pragma Unreferenced (Line_Height);
      Result : Guikit.Draw.Text_Render_Result;
      Cell_W : constant Natural := Textrender.Cell_Width (Text);
   begin
      for Cmd of Commands loop
         declare
            S         : constant String := To_String (Cmd.Text);
            Index     : Integer := S'First;
            Cell      : Natural := 0;
            Box_Right : constant Float := Float (Cmd.X) + Float (Cmd.Width);
         begin
            while Index <= S'Last loop
               declare
                  CP     : Natural;
                  Next   : Integer;
                  Cell_X : constant Float := Float (Cmd.X) + Float (Cell * Cell_W);
                  Metric : Textrender.Glyph_Metric;
                  Status : Textrender.Status_Code;
               begin
                  exit when Cell_X + Float (Cell_W) > Box_Right + 0.5;
                  Decode_Next (S, Index, CP, Next);
                  Status := Textrender.Get_Glyph (Text, Textrender.Codepoint (CP), Metric);
                  if (Status = Textrender.Success or else Status = Textrender.Glyph_Missing)
                    and then Metric.W > 0 and then Metric.H > 0
                  then
                     declare
                        P : constant Textrender.Glyph_Placement :=
                          Textrender.Place_Glyph_In_Cell (Text, Metric, Cell_X, Float (Cmd.Y));
                     begin
                        Result.Glyphs.Append
                          (Guikit.Draw.Glyph_Command'
                             (X         => P.X,
                              Y         => P.Y,
                              Width     => Float (Metric.W),
                              Height    => Float (Metric.H),
                              U0        => Metric.U0,
                              V0        => Metric.V0,
                              U1        => Metric.U1,
                              V1        => Metric.V1,
                              Color     => Cmd.Color,
                              Codepoint => CP));
                     end;
                  end if;
                  Cell  := Cell + 1;
                  Index := Next;
               end;
            end loop;
         end;
      end loop;

      declare
         Pixels : constant access constant Textrender.Alpha_Buffer := Textrender.Atlas_Pixels (Text);
      begin
         Result.Status       := Guikit.Draw.Text_Render_Success;
         Result.Atlas_Width  := Textrender.Atlas_Width (Text);
         Result.Atlas_Height := Textrender.Atlas_Height (Text);
         Result.Atlas_Bytes  := Result.Atlas_Width * Result.Atlas_Height;
         Result.Atlas_Dirty  := Textrender.Atlas_Dirty (Text);
         if Pixels /= null and then Pixels.all'Length > 0 then
            Result.Atlas_Pixels := Pixels.all (Pixels.all'First)'Address;
         else
            Result.Atlas_Pixels := System.Null_Address;
         end if;
      end;
      return Result;
   end Build_Glyphs;

   procedure Build_Frame
     (M           : Launcher.Model.State;
      Ranked      : Guikit.Palette.Item_Vectors.Vector;
      Width       : Natural;
      Height      : Natural;
      Line_Height : Positive;
      Hover_X     : Integer;
      Hover_Y     : Integer;
      Rectangles  : out Guikit.Draw.Rectangle_Command_Vectors.Vector;
      Text        : out Guikit.Draw.Text_Command_Vectors.Vector;
      Rows        : out Guikit.Layout.Palette_Result_Row_Vectors.Vector)
   is
      Layout  : constant Guikit.Layout.Palette_Layout :=
        Guikit.Layout.Calculate_Palette_Layout (0, 0, Width, Height, Line_Height);
      Pad     : constant Natural := Guikit.Layout.Palette_Padding;
      Row_Pad : constant Natural := Guikit.Layout.Palette_Result_Row_Padding;
      Cell_W  : constant Natural := Guikit.Layout.Caret_Advance_Width (Line_Height);
      Query   : constant String := To_String (M.Query);
      Text_Y  : constant Natural :=
        (if Layout.Search_Height > Line_Height
         then Layout.Search_Y + (Layout.Search_Height - Line_Height) / 2
         else Layout.Search_Y);
      Enabled : Guikit.Layout.Palette_Enabled_Vectors.Vector;
   begin
      Guikit.Widgets.Draw_Menu_Panel
        (Rectangles, Width, Height, Layout.X, Layout.Y, Layout.Width, Layout.Height,
         Guikit.Draw.Pane_Color, Guikit.Draw.Border_Color);
      Rectangles.Append
        (Guikit.Draw.Rectangle_Command'
           (X => Layout.X, Y => Layout.Y, Width => Layout.Width,
            Height => Natural'Min (3, Layout.Height), Color => Guikit.Draw.Selection_Color));

      Guikit.Widgets.Draw_Input_Field
        (Rectangles, Width, Height, Layout.Search_X, Layout.Search_Y,
         Layout.Search_Width, Layout.Search_Height, Guikit.Draw.Input_Color, Guikit.Draw.Border_Color);

      declare
         Field_W : constant Natural :=
           (if Layout.Search_Width > 2 * Pad then Layout.Search_Width - 2 * Pad else 0);
      begin
         if Query'Length > 0 then
            Text.Append
              (Guikit.Draw.Text_Command'
                 (X => Layout.Search_X + Pad, Y => Text_Y, Width => Field_W, Height => Line_Height,
                  Text => M.Query, Color => Guikit.Draw.Text_Color, others => <>));
         else
            Text.Append
              (Guikit.Draw.Text_Command'
                 (X => Layout.Search_X + Pad, Y => Text_Y, Width => Field_W, Height => Line_Height,
                  Text => To_Unbounded_String ("Type to search applications..."),
                  Color => Guikit.Draw.Muted_Text_Color, others => <>));
         end if;
      end;

      --  Caret at the end of the query.
      Rectangles.Append
        (Guikit.Draw.Rectangle_Command'
           (X      => Layout.Search_X + Pad + Guikit.Utf8.Display_Units (Query) * Cell_W,
            Y      => Text_Y,
            Width  => Natural'Max (1, Cell_W / 6),
            Height => Line_Height,
            Color  => Guikit.Draw.Text_Color));

      for Item of Ranked loop
         Enabled.Append (Item.Enabled);
      end loop;
      Rows := Guikit.Layout.Calculate_Palette_Result_Rows (Layout, Enabled, M.Selected, M.Offset);

      for Row of Rows loop
         declare
            Item    : constant Guikit.Palette.Item := Ranked.Element (Row.Result_Index);
            Hovered : constant Boolean :=
              Hover_X >= Row.X and then Hover_X < Row.X + Row.Width
              and then Hover_Y >= Row.Y and then Hover_Y < Row.Y + Row.Height;
            Label_X : constant Natural := Row.X + Pad;
            Label_Y : constant Natural := Row.Y + Row_Pad;
            Label_W : constant Natural := (if Row.Width > 2 * Pad then Row.Width - 2 * Pad else 0);
         begin
            Guikit.Widgets.Draw_Palette_Row
              (Rectangles       => Rectangles,
               Text             => Text,
               Clip_Width       => Width,
               Clip_Height      => Height,
               Row_X            => Row.X,
               Row_Y            => Row.Y,
               Row_Width        => Row.Width,
               Row_Height       => Row.Height,
               Background_Color =>
                 (if Row.Selected then Guikit.Draw.Selection_Color
                  elsif Hovered then Guikit.Draw.Hover_Color
                  else Guikit.Draw.Pane_Color),
               Selected         => Row.Selected,
               Accent_Color     => Guikit.Draw.Border_Color,
               Label_X          => Label_X,
               Label_Y          => Label_Y,
               Label_Width      => Label_W,
               Label_Height     => Natural'Min (Line_Height, Row.Height),
               Label_Text       => Item.Label,
               Label_Truncated  => False,
               Label_Color      => Guikit.Draw.Text_Color,
               Shortcut_X       => 0,
               Shortcut_Width   => 0,
               Shortcut_Text    => Null_Unbounded_String,
               Shortcut_Truncated => False,
               Shortcut_Color   => Guikit.Draw.Muted_Text_Color,
               Description_Y    => Label_Y + Line_Height,
               Description_Width  => (if Row.Height > Line_Height then Label_W else 0),
               Description_Height =>
                 Natural'Min (Line_Height,
                   (if Row.Height > Row_Pad + Line_Height then Row.Height - Row_Pad - Line_Height else 0)),
               Description_Text => Item.Description,
               Description_Truncated => False,
               Description_Color => Guikit.Draw.Muted_Text_Color);
         end;
      end loop;
   end Build_Frame;

end Launcher.Render;

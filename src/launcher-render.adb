with Ada.Strings.Unbounded;

with Guikit.Utf8;
with Guikit.Widgets;

package body Launcher.Render is
   use Ada.Strings.Unbounded;


   procedure Build_Frame
     (M           : in out Launcher.Model.State;
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

      --  Scroll so the highlighted result stays on screen.
      M.Offset :=
        Guikit.Layout.Scroll_Offset_For_Selection
          (Selected       => M.Selected,
           Result_Count   => Natural (Ranked.Length),
           Visible_Rows   =>
             (if Layout.Row_Height = 0 then 0 else Layout.Results_Height / Layout.Row_Height),
           Current_Offset => M.Offset);
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

      --  Empty state: a query that matches nothing shows a muted message rather
      --  than a blank void.
      if Ranked.Is_Empty then
         Text.Append
           (Guikit.Draw.Text_Command'
              (X      => Layout.Results_X + Pad,
               Y      => Layout.Results_Y + Row_Pad,
               Width  => (if Layout.Results_Width > 2 * Pad then Layout.Results_Width - 2 * Pad else 0),
               Height => Line_Height,
               Text   => To_Unbounded_String ("No matching applications"),
               Color  => Guikit.Draw.Muted_Text_Color,
               others => <>));
      end if;
   end Build_Frame;

end Launcher.Render;

with Guikit.Draw;
with Guikit.Layout;
with Guikit.Palette;

with Launcher.Model;

--  Frame building for the launcher: turn the model into guikit draw-command
--  vectors (the palette overlay filling the whole window), and rasterize the
--  frame's text through Textrender into the glyph/atlas result the Vulkan
--  backend uploads. The layout and per-row drawing are reused from guikit.
package Launcher.Render is

   --  Build the launcher frame: the panel, the search box + query + caret, and
   --  the visible result rows. Also returns the laid-out rows so the caller can
   --  hit-test mouse clicks.
   --
   --  @param M Launcher state.
   --  @param Ranked The current ranked results (Model.Results).
   --  @param Width Window width in pixels.
   --  @param Height Window height in pixels.
   --  @param Line_Height Text line height in pixels.
   --  @param Hover_X Cursor X in pixels (negative when the cursor is off-window).
   --  @param Hover_Y Cursor Y in pixels.
   --  @param Rectangles Out: the frame's rectangle commands.
   --  @param Text Out: the frame's text commands.
   --  @param Rows Out: the laid-out result rows (for click hit-testing).
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
      Rows        : out Guikit.Layout.Palette_Result_Row_Vectors.Vector);

end Launcher.Render;

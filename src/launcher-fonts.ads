with Guikit.Text;

--  Font discovery for the launcher: a monospace primary face plus a small
--  fallback chain (symbols / broad Unicode) so labels with the odd non-Latin
--  glyph still render. Only paths that exist on disk are returned.
package Launcher.Fonts is

   --  Path to the monospace primary font, or "" if none of the candidates
   --  exist on this system.
   --
   --  @return An existing monospace .ttf path, or the empty string.
   function Primary return String;

   --  Existing fallback font paths (broad Unicode / symbol faces), in order.
   --
   --  @return The fallback font paths that exist on disk.
   function Fallbacks return Guikit.Text.Font_Path_Vectors.Vector;

end Launcher.Fonts;

with Ada.Containers.Vectors;

with Guikit.Draw;

--  Application-icon loading for the launcher: resolve a freedesktop `.desktop`
--  Icon= value (an icon name or an absolute path) to a file via the XDG icon
--  directories, and decode it (PNG/SVG, through gdk_pixbuf) into an RGBA pixel
--  buffer scaled to a square size. The buffer is in the layout the guikit icon
--  atlas expects (row-major RGBA, 4 bytes/pixel).
package Launcher.Icons is

   type Loaded_Icon is record
      Width  : Natural := 0;
      Height : Natural := 0;
      Pixels : Guikit.Draw.Byte_Vectors.Vector;
   end record;
   --  Width = 0 means "no icon" (not found, empty, or failed to decode).

   package Loaded_Icon_Vectors is new Ada.Containers.Vectors
     (Index_Type   => Positive,
      Element_Type => Loaded_Icon);

   --  Resolve and load an application's icon, scaled to Size x Size.
   --
   --  @param Icon A .desktop Icon= value: an icon name or an absolute path.
   --  @param Size The desired square icon size in pixels.
   --  @return The decoded RGBA icon, or an unloaded icon (Width = 0) on failure.
   function Load (Icon : String; Size : Positive) return Loaded_Icon;

end Launcher.Icons;

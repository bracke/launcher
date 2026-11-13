with Ada.Strings.Unbounded;

with Hostkit.Fs;

with Guikit.Fonts;

--  The chain is guikit's (Guikit.Fonts), the one every guikit application
--  draws with; the launcher contributes only where its host keeps fonts.
package body Launcher.Fonts is

   --  The host's font folders, the system's first.
   function Font_Directories return Guikit.Text.Font_Path_Vectors.Vector is
      Result : Guikit.Text.Font_Path_Vectors.Vector;
   begin
      for Folder of Hostkit.Fs.Font_Directories loop
         Result.Append (Ada.Strings.Unbounded.To_String (Folder));
      end loop;
      return Result;
   exception
      --  No host folders: the known whole paths are still looked for.
      when others =>
         return Result;
   end Font_Directories;

   function Primary return String is
     (Guikit.Fonts.Default_Font_Path (Font_Directories => Font_Directories));

   --  No image decoder is linked, so the bitmap emoji fonts are left out and
   --  only the layered (COLR) kind, which textrender draws unaided, is listed.
   function Fallbacks return Guikit.Text.Font_Path_Vectors.Vector is
     (Guikit.Fonts.Fallback_Font_Paths
        (Primary          => Primary,
         Font_Directories => Font_Directories,
         Colour_Bitmaps   => False));

end Launcher.Fonts;

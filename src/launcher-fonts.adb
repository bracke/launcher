with Ada.Directories;

package body Launcher.Fonts is

   --  Every candidate was a Linux path, so on macOS and Windows the probe found
   --  nothing and the launcher had no font at all -- it would come up unable to draw
   --  a single character. The lists carry those platforms' own locations too now,
   --  which is what the file manager already does.
   Mono_Candidates : constant array (Positive range <>) of access constant String :=
     (new String'("/usr/share/fonts/truetype/noto/NotoSansMono-Regular.ttf"),
      new String'("/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf"),
      new String'("/usr/share/fonts/truetype/liberation/LiberationMono-Regular.ttf"),
      new String'("/usr/share/fonts/TTF/DejaVuSansMono.ttf"),
      new String'("/usr/share/fonts/noto/NotoSansMono-Regular.ttf"),
      new String'("/System/Library/Fonts/Menlo.ttc"),
      new String'("/System/Library/Fonts/Monaco.ttf"),
      new String'("C:\Windows\Fonts\consola.ttf"),
      new String'("C:\Windows\Fonts\cour.ttf"));

   Fallback_Candidates : constant array (Positive range <>) of access constant String :=
     (new String'("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"),
      new String'("/usr/share/fonts/truetype/noto/NotoSans-Regular.ttf"),
      new String'("/usr/share/fonts/TTF/DejaVuSans.ttf"),
      new String'("/usr/share/fonts/truetype/unifont/unifont.ttf"),
      new String'("/System/Library/Fonts/Supplemental/Arial.ttf"),
      new String'("/System/Library/Fonts/Helvetica.ttc"),
      new String'("C:\Windows\Fonts\segoeui.ttf"),
      new String'("C:\Windows\Fonts\arial.ttf"));

   function Exists (Path : String) return Boolean is
      use type Ada.Directories.File_Kind;
   begin
      return Ada.Directories.Exists (Path)
        and then Ada.Directories.Kind (Path) = Ada.Directories.Ordinary_File;
   exception
      when others =>
         return False;
   end Exists;

   function Primary return String is
   begin
      for Candidate of Mono_Candidates loop
         if Exists (Candidate.all) then
            return Candidate.all;
         end if;
      end loop;
      return "";
   end Primary;

   function Fallbacks return Guikit.Text.Font_Path_Vectors.Vector is
      Result : Guikit.Text.Font_Path_Vectors.Vector;
   begin
      for Candidate of Fallback_Candidates loop
         if Exists (Candidate.all) then
            Result.Append (Candidate.all);
         end if;
      end loop;
      return Result;
   end Fallbacks;

end Launcher.Fonts;

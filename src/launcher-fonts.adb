with Ada.Directories;

package body Launcher.Fonts is

   Mono_Candidates : constant array (Positive range <>) of access constant String :=
     (new String'("/usr/share/fonts/truetype/noto/NotoSansMono-Regular.ttf"),
      new String'("/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf"),
      new String'("/usr/share/fonts/truetype/liberation/LiberationMono-Regular.ttf"),
      new String'("/usr/share/fonts/TTF/DejaVuSansMono.ttf"),
      new String'("/usr/share/fonts/noto/NotoSansMono-Regular.ttf"));

   Fallback_Candidates : constant array (Positive range <>) of access constant String :=
     (new String'("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"),
      new String'("/usr/share/fonts/truetype/noto/NotoSans-Regular.ttf"),
      new String'("/usr/share/fonts/TTF/DejaVuSans.ttf"),
      new String'("/usr/share/fonts/truetype/unifont/unifont.ttf"));

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

   function Fallbacks return Path_Vectors.Vector is
      Result : Path_Vectors.Vector;
   begin
      for Candidate of Fallback_Candidates loop
         if Exists (Candidate.all) then
            Result.Append (Candidate.all);
         end if;
      end loop;
      return Result;
   end Fallbacks;

end Launcher.Fonts;

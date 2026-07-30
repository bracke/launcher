with Ada.Directories;
with Ada.Environment_Variables;

package body Launcher.Fonts is

   --  Every candidate was a Linux path, so on macOS and Windows the probe found
   --  nothing and the launcher had no font at all -- it would come up unable to draw
   --  a single character. The lists carry those platforms' own locations too now,
   --  which is what the file manager already does.
   Mono_Candidates : constant array (Positive range <>) of access constant String :=
     [new String'("/usr/share/fonts/truetype/noto/NotoSansMono-Regular.ttf"),
      new String'("/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf"),
      new String'("/usr/share/fonts/truetype/liberation/LiberationMono-Regular.ttf"),
      new String'("/usr/share/fonts/TTF/DejaVuSansMono.ttf"),
      new String'("/usr/share/fonts/noto/NotoSansMono-Regular.ttf"),
      new String'("/System/Library/Fonts/Menlo.ttc"),
      new String'("/System/Library/Fonts/Monaco.ttf"),
      new String'("C:\Windows\Fonts\consola.ttf"),
      new String'("C:\Windows\Fonts\cour.ttf")];

   Fallback_Candidates : constant array (Positive range <>) of access constant String :=
     [new String'("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"),
      new String'("/usr/share/fonts/truetype/noto/NotoSans-Regular.ttf"),
      new String'("/usr/share/fonts/TTF/DejaVuSans.ttf"),
      new String'("/usr/share/fonts/truetype/unifont/unifont.ttf"),
      new String'("/System/Library/Fonts/Supplemental/Arial.ttf"),
      new String'("/System/Library/Fonts/Helvetica.ttc"),
      new String'("C:\Windows\Fonts\segoeui.ttf"),
      new String'("C:\Windows\Fonts\arial.ttf")];

   --  Colour emoji, and last in the chain on purpose: the chain is resolved by
   --  asking each font whether it maps a codepoint and taking the first that
   --  says yes, and an emoji font maps far more than emoji -- arrows, stars, the
   --  check mark. Ahead of the text fonts it would capture characters those draw
   --  perfectly well.
   --
   --  Only the layered kind is listed. Textrender draws COLR/CPAL glyphs from
   --  outlines and a palette, needing nothing but the font; the bitmap kinds
   --  (Noto Color Emoji on Linux, Apple Color Emoji on macOS) hold PNGs and want
   --  a decoder from the caller, which the launcher has no reason to link. So
   --  Windows gets emoji from Segoe out of the box, and a Linux machine gets them
   --  wherever a COLR font is installed.
   Emoji_Candidates : constant array (Positive range <>) of access constant String :=
     [new String'("/usr/share/fonts/truetype/twemoji/TwemojiMozilla.ttf"),
      new String'("/usr/share/fonts/TTF/TwemojiMozilla.ttf"),
      new String'("C:\Windows\Fonts\seguiemj.ttf")];

   --  A font the user installed for themselves, which is where one lands without
   --  root. Checked after the system locations, and skipped when HOME is unset.
   function User_Emoji_Font return String;

   function User_Emoji_Font return String is
   begin
      if not Ada.Environment_Variables.Exists ("HOME") then
         return "";
      end if;

      return Ada.Environment_Variables.Value ("HOME")
        & "/.local/share/fonts/TwemojiMozilla.ttf";
   exception
      when others =>
         return "";
   end User_Emoji_Font;

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

      for Candidate of Emoji_Candidates loop
         if Exists (Candidate.all) then
            Result.Append (Candidate.all);
         end if;
      end loop;

      if User_Emoji_Font /= "" and then Exists (User_Emoji_Font) then
         Result.Append (User_Emoji_Font);
      end if;

      return Result;
   end Fallbacks;

end Launcher.Fonts;

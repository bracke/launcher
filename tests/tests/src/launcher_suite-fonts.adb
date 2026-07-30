with AUnit;
with AUnit.Assertions;
with AUnit.Test_Cases;

with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;

with Guikit.Draw;
with Guikit.Text;

with Launcher.Fonts;

package body Launcher_Suite.Fonts is

   use AUnit.Assertions;

   type Fonts_Test_Case is new AUnit.Test_Cases.Test_Case with null record;

   overriding function Name (T : Fonts_Test_Case) return AUnit.Message_String;
   overriding procedure Register_Tests (T : in out Fonts_Test_Case);

   procedure Test_Emoji_Becomes_A_Colour_Glyph (T : in out AUnit.Test_Cases.Test_Case'Class);

   overriding function Name (T : Fonts_Test_Case) return AUnit.Message_String is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("launcher font chain");
   end Name;

   overriding procedure Register_Tests (T : in out Fonts_Test_Case) is
   begin
      AUnit.Test_Cases.Registration.Register_Routine
        (T, Test_Emoji_Becomes_A_Colour_Glyph'Access,
         "an emoji in a command name draws as a colour glyph, with no decoder");
   end Register_Tests;

   --  An emoji in a command name draws as a picture, not as a '?'.
   --
   --  The launcher links no image decoder, and this is the point of the test:
   --  a layered COLR/CPAL emoji font is outlines and a palette, so textrender
   --  draws it with nothing supplied by the caller. The bitmap emoji fonts hold
   --  PNGs and would need one, which is why the chain lists only the layered
   --  kind.
   --
   --  Skipped where no such font is installed, which is most Linux machines --
   --  the emoji font shipped by default is the bitmap kind.
   procedure Test_Emoji_Becomes_A_Colour_Glyph (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      use type Guikit.Draw.Text_Render_Status;

      --  U+1F389 PARTY POPPER, spelled out so this file stays plain ASCII.
      Party : constant String :=
        Character'Val (16#F0#) & Character'Val (16#9F#)
        & Character'Val (16#8E#) & Character'Val (16#89#);

      Renderer : Guikit.Text.Renderer;
      Commands : Guikit.Draw.Text_Command_Vectors.Vector;
      Overlay  : Guikit.Draw.Text_Command_Vectors.Vector;
      Command  : Guikit.Draw.Text_Command;
      Layered  : Boolean := False;
   begin
      if Launcher.Fonts.Primary = "" then
         return;
      end if;

      --  Only a layered font can be drawn here; a bitmap one in the chain is
      --  not a failure, it simply cannot produce a picture without a decoder.
      for Path of Launcher.Fonts.Fallbacks loop
         if Ada.Strings.Unbounded.Index
              (To_Unbounded_String (Path), "Twemoji") > 0
           or else Ada.Strings.Unbounded.Index
              (To_Unbounded_String (Path), "seguiemj") > 0
         then
            Layered := True;
         end if;
      end loop;

      if not Layered then
         return;
      end if;

      Assert
        (Guikit.Text.Initialize
           (Renderer,
            Launcher.Fonts.Primary,
            Launcher.Fonts.Fallbacks,
            16, 10, 20, 1024, 1024) = Guikit.Draw.Text_Render_Success,
         "the launcher's own font chain initialises");

      Command.X := 0;
      Command.Y := 0;
      Command.Width := 400;
      Command.Height := 20;
      Command.Text := To_Unbounded_String ("open " & Party & " files");
      Commands.Append (Command);

      declare
         Result : constant Guikit.Draw.Text_Render_Result :=
           Guikit.Text.Build_Glyphs (Renderer, Commands, Overlay);
      begin
         Assert (Result.Status = Guikit.Draw.Text_Render_Success,
                 "the text builds");
         Assert (Natural (Result.Colour_Icons.Length) = 1,
                 "the emoji becomes one colour glyph, got"
                 & Natural'Image (Natural (Result.Colour_Icons.Length)));
         Assert (Result.Missing_Glyph_Count = 0,
                 "and nothing falls through to the missing-glyph path");

         for Icon of Result.Colour_Icons loop
            Assert (Icon.Thumbnail_Width > 0 and then Icon.Thumbnail_Height > 0,
                    "the picture has a size");
            Assert
              (Natural (Icon.Thumbnail_Pixels.Length)
                 = Icon.Thumbnail_Width * Icon.Thumbnail_Height * 4,
               "with four bytes for each of its pixels");
         end loop;
      end;
   end Test_Emoji_Becomes_A_Colour_Glyph;

   function Suite return AUnit.Test_Suites.Access_Test_Suite is
      Result : constant AUnit.Test_Suites.Access_Test_Suite :=
        new AUnit.Test_Suites.Test_Suite;
   begin
      Result.Add_Test (AUnit.Test_Cases.Test_Case_Access'(new Fonts_Test_Case));
      return Result;
   end Suite;

end Launcher_Suite.Fonts;

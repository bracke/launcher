with Ada.Command_Line;
with Ada.Strings.Unbounded;
with Ada.Text_IO;

with Glfw;
with Glfw.Input.Keys;
with Glfw.Input.Mouse;
with Glfw.Windows;

with Guikit.Command_Palette;
with Guikit.Draw;
with Guikit.Input.Pending;
with Guikit.Layout;
with Guikit.Text;
with Guikit.Utf8;
with Guikit.Vulkan;

with Launcher.Applications;
with Launcher.Fonts;
with Launcher.Messages;
with Launcher.Model;

procedure Launcher.Main is
   use Ada.Strings.Unbounded;

   Line_Height : constant Positive := 26;

   --  The window keeps its input in one ordered queue (Guikit.Input.Pending),
   --  which the main loop drains once per frame; its callbacks guard against
   --  an exception unwinding into GLFW's C code, and drop a left press that
   --  bounces. Its dirty flag starts set so the first frame draws, and the
   --  loop redraws only when it is set (or on resize), so an idle launcher
   --  stops re-presenting the same frame.
   type Launcher_Window is new Guikit.Input.Pending.Pending_Window with null record;

   type Window_Access is access all Launcher_Window;

   function As_Window (Handle : Window_Access) return Glfw.Windows.Window_Reference is
     (Glfw.Windows.Window_Reference (Handle));

   Handle       : constant Window_Access := new Launcher_Window;
   Vulkan       : Guikit.Vulkan.Vulkan_Renderer;
   Text         : Guikit.Text.Renderer;
   M            : Launcher.Model.State;
   Palette      : Guikit.Command_Palette.Palette;
   Ignore_St    : Guikit.Vulkan.Vulkan_Status;
   Ignore_Ts    : Guikit.Draw.Text_Render_Status;
   --  Track the framebuffer size so a resize (not delivered through the input
   --  callbacks) still forces a redraw under the dirty gate.
   Last_Frame_W : Glfw.Size := 0;
   Last_Frame_H : Glfw.Size := 0;
   pragma Unreferenced (Ignore_St, Ignore_Ts);

   --  Present-grace window: keep drawing every frame for a short spell after the
   --  last change (input or resize) instead of stopping the instant the dirty
   --  flag clears. Presenting every frame keeps us on the compositor's frame
   --  clock, which paces input at the display rate; once we stop, the first
   --  interaction after an idle gap stalls. ~24 frames is ~0.4s at 60fps; normal
   --  typing refills it, and a truly idle launcher still drops to no presenting.
   Present_Grace_Frames : constant := 24;
   Present_Grace : Natural := 0;

   --  What the input asked for, carried from draining it to acting on it
   --  after the frame is drawn.
   Pending_Escape : Boolean := False;
   Pending_Enter  : Boolean := False;
   Pending_Click  : Boolean := False;
   Click_X        : Integer := -1;
   Click_Y        : Integer := -1;

   --  Render one frame: bring the swapchain up, build and submit the palette,
   --  and present. The component owns the row layout (for click hit-testing).
   procedure Draw_Frame
     (Win : Window_Access;
      Vk  : in out Guikit.Vulkan.Vulkan_Renderer;
      Txt : in out Guikit.Text.Renderer;
      Pal : in out Guikit.Command_Palette.Palette)
   is
      Window_W, Window_H : Glfw.Size;
      Frame_W,  Frame_H  : Glfw.Size;
   begin
      Glfw.Windows.Get_Size (As_Window (Win), Window_W, Window_H);
      Glfw.Windows.Get_Framebuffer_Size (As_Window (Win), Frame_W, Frame_H);
      Guikit.Vulkan.Ensure_Ready (Vk, As_Window (Win), Natural (Frame_W), Natural (Frame_H));
      if not Guikit.Vulkan.Swapchain_Ready (Vk) then
         return;
      end if;

      declare
         Rects  : Guikit.Draw.Rectangle_Command_Vectors.Vector;
         Texts  : Guikit.Draw.Text_Command_Vectors.Vector;
         Icons  : Guikit.Draw.Icon_Command_Vectors.Vector;
         Nodes  : Guikit.Draw.Accessibility_Node_Vectors.Vector;
         No_Tri        : Guikit.Draw.Triangle_Command_Vectors.Vector;
         No_Overlay    : Guikit.Draw.Rectangle_Command_Vectors.Vector;
         No_Overlay_Tx : Guikit.Draw.Text_Command_Vectors.Vector;
         Metrics : constant Guikit.Draw.Layout_Metrics :=
           (Width => Natural (Window_W), Height => Natural (Window_H), Line_Height => Line_Height, others => 0);
         Glyphs  : Guikit.Draw.Text_Render_Result;
         Batch   : Guikit.Vulkan.Submission_Batch;
      begin
         Guikit.Command_Palette.Build_Frame
           (P             => Pal,
            Region_X      => 0,
            Region_Y      => 0,
            Region_Width  => Natural (Window_W),
            Region_Height => Natural (Window_H),
            Clip_Width    => Natural (Window_W),
            Clip_Height   => Natural (Window_H),
            Focused       => True,
            Hover_X       => Win.Mouse_X,
            Hover_Y       => Win.Mouse_Y,
            Rectangles    => Rects,
            Text          => Texts,
            Icons         => Icons,
            Accessibility => Nodes);
         Glyphs := Guikit.Text.Build_Glyphs (Txt, Texts, No_Overlay_Tx);
         Batch  :=
           Guikit.Vulkan.Build_Submission
             (Rects, No_Tri, Icons, No_Overlay, Metrics, Guikit.Draw.Theme_Dark, Glyphs);
         Ignore_St :=
           Guikit.Vulkan.Present_Frame (Vk, Batch, Natural (Frame_W), Natural (Frame_H));
      end;
   end Draw_Frame;

   --  Headless render check: enable framebuffer readback, render a few frames of
   --  the full app list, and confirm the window, search box and results region
   --  each hold ink. Returns True when the frame rendered as expected.
   function Smoke_Passes
     (Win : Window_Access;
      Vk  : in out Guikit.Vulkan.Vulkan_Renderer;
      Txt : in out Guikit.Text.Renderer;
      Pal : in out Guikit.Command_Palette.Palette)
      return Boolean
   is
      Frame_W, Frame_H : Glfw.Size;
   begin
      Guikit.Vulkan.Set_Readback_Enabled (Vk, True);
      for I in 1 .. 6 loop
         Draw_Frame (Win, Vk, Txt, Pal);
      end loop;

      Glfw.Windows.Get_Framebuffer_Size (As_Window (Win), Frame_W, Frame_H);
      declare
         FW : constant Natural := Natural (Frame_W);
         FH : constant Natural := Natural (Frame_H);
         Overall : constant Boolean :=
           Guikit.Vulkan.Readback_Region_Has_Ink (Vk, 0, 0, FW, FH, 0.003);
         Search  : constant Boolean :=
           Guikit.Vulkan.Readback_Region_Has_Ink (Vk, 0, FH / 40, FW, FH / 8, 0.001);
         Results : constant Boolean :=
           Guikit.Vulkan.Readback_Region_Has_Ink (Vk, 0, FH / 4, FW, FH / 2, 0.001);
         --  Left icon gutter over the results: ink here means app icons drew.
         --  Required only when some application has an icon to draw: launcher
         --  reads no icon from a Start Menu shortcut or an .app bundle, so on
         --  Windows and macOS an empty gutter is the right picture. Have_Icon is
         --  printed, so CI can require it where its fixture gives icons.
         Icon_Ink : constant Float :=
           Guikit.Vulkan.Readback_Region_Ink_Fraction (Vk, 2, FH / 4, 48, FH / 2);
         Have_Icon : constant Boolean := (for some Icon of M.Icons => Icon.Width > 0);
         Icons_Ok : constant Boolean := Icon_Ink > 0.001 or else not Have_Icon;
         --  Right edge over the results: ink means the scrollbar. Required when
         --  the applications' rows are taller than the whole window, so they
         --  must overflow the visible rows and a thumb must be present.
         Scroll_Ink : constant Float :=
           Guikit.Vulkan.Readback_Region_Ink_Fraction
             (Vk, (if FW > 14 then FW - 14 else 0), FH / 4, 14, FH / 2);
         Window_W, Window_H : Glfw.Size;
         Overflows  : Boolean;
         Scroll_Ok  : Boolean;
      begin
         Glfw.Windows.Get_Size (As_Window (Win), Window_W, Window_H);
         Overflows := Natural (M.Apps.Length) * Line_Height > Natural (Window_H);
         Scroll_Ok := Scroll_Ink > 0.0005 or else not Overflows;
         Ada.Text_IO.Put_Line
           ("launcher smoke: overall=" & Boolean'Image (Overall)
            & " search=" & Boolean'Image (Search)
            & " results=" & Boolean'Image (Results)
            & " icons=" & Boolean'Image (Icons_Ok)
            --  Whether any application had an icon to draw: without one the
            --  icon check passes vacuously, and CI says where it must not.
            & " have_icon=" & Boolean'Image (Have_Icon)
            & " scrollbar=" & Boolean'Image (Scroll_Ok)
            & " (gutter" & Float'Image (Icon_Ink)
            & " scroll" & Float'Image (Scroll_Ink) & ")");
         return Overall and then Search and then Results and then Icons_Ok and then Scroll_Ok;
      end;
   end Smoke_Passes;

begin
   Launcher.Model.Load (M);

   --  Headless diagnostic: print the discovered applications (with icon status)
   --  and exit.
   if Ada.Command_Line.Argument_Count >= 1
     and then Ada.Command_Line.Argument (1) = "--list"
   then
      declare
         With_Icon : Natural := 0;
      begin
         for I in M.Apps.First_Index .. M.Apps.Last_Index loop
            declare
               Icon_W : constant Natural := M.Icons.Element (I).Width;
               Tag    : constant String :=
                 (if Icon_W > 0 then "  [icon]" else "  [no icon]");
            begin
               if Icon_W > 0 then
                  With_Icon := With_Icon + 1;
               end if;
               Ada.Text_IO.Put_Line
                 (To_String (M.Apps.Element (I).Name) & "  ::  "
                  & To_String (M.Apps.Element (I).Exec) & Tag);
            end;
         end loop;
         Ada.Text_IO.Put_Line
           (Natural'Image (With_Icon) & " of" & Natural'Image (Natural (M.Apps.Length))
            & " applications have an icon");
      end;
      return;
   end if;

   --  Load the fonts.
   declare
      Primary : constant String := Launcher.Fonts.Primary;
   begin
      if Primary = "" then
         --  Nothing to draw text with: say so, and fail, rather than vanish --
         --  a --smoke run that exits 0 here would pass without rendering.
         Ada.Text_IO.Put_Line (Ada.Text_IO.Standard_Error, "launcher: no usable font was found");
         Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
         return;
      end if;
      Ignore_Ts :=
        Guikit.Text.Initialize
          (Text, Primary, Launcher.Fonts.Fallbacks,
           --  Sized from the line height, as files does: the font at four
           --  fifths of it, the cell at the advance guikit's widgets measure
           --  labels and carets with.
           Pixel_Size   => Line_Height * 4 / 5,
           Cell_Width   => Guikit.Layout.Caret_Advance_Width (Line_Height),
           Cell_Height  => Line_Height,
           Atlas_Width  => 1024,
           Atlas_Height => 1024);
   end;

   --  Configure the palette and load the application commands.
   Guikit.Command_Palette.Set_Configuration
     (Palette,
      (Line_Height    => Line_Height,
       Show_Icons     => True,
       Show_Shortcuts => False,
       Overlay        => False,
       Wrap_Selection => False,
       Placeholder    => To_Unbounded_String (Launcher.Messages.Text ("palette.placeholder")),
       Empty_State    => To_Unbounded_String (Launcher.Messages.Text ("palette.empty")),
       Title          => Null_Unbounded_String,
       --  Not an overlay, so no close button is drawn to be named.
       Close_Label    => <>));
   Guikit.Command_Palette.Set_Commands (Palette, Launcher.Model.Commands (M));

   --  Create the window.
   Glfw.Init;
   Guikit.Vulkan.Configure_Window_Hints;
   Glfw.Windows.Init (As_Window (Handle), Glfw.Size (900), Glfw.Size (560), "launcher");
   Glfw.Windows.Enable_Callback (As_Window (Handle), Glfw.Windows.Callbacks.Char);
   Glfw.Windows.Enable_Callback (As_Window (Handle), Glfw.Windows.Callbacks.Key);
   Glfw.Windows.Enable_Callback (As_Window (Handle), Glfw.Windows.Callbacks.Mouse_Button);
   Glfw.Windows.Enable_Callback (As_Window (Handle), Glfw.Windows.Callbacks.Mouse_Position);
   Glfw.Windows.Enable_Callback (As_Window (Handle), Glfw.Windows.Callbacks.Mouse_Scroll);
   Glfw.Windows.Show (As_Window (Handle));

   --  Headless render check: render a few frames and confirm the frame drew.
   if Ada.Command_Line.Argument_Count >= 1
     and then Ada.Command_Line.Argument (1) = "--smoke"
   then
      declare
         Passed : constant Boolean := Smoke_Passes (Handle, Vulkan, Text, Palette);
      begin
         Ada.Text_IO.Put_Line ("launcher smoke: " & (if Passed then "PASS" else "FAIL"));
         if not Passed then
            Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
         end if;
      end;
      Guikit.Vulkan.Shutdown (Vulkan);
      Glfw.Shutdown;
      return;
   end if;

   --  Main loop.
   while not Glfw.Windows.Should_Close (As_Window (Handle)) loop
      --  Launcher is fully event-driven: no animation, no background task, and
      --  GLFW delivers key auto-repeat as events. The Dirty gate below already
      --  skips the build/submit/present path for unchanged frames, so idle CPU
      --  stays near zero. Wait only a frame's worth so input is always handled
      --  promptly -- a long block let keystrokes lag when the event did not wake
      --  Wait_For_Events immediately (once we stop presenting, the compositor
      --  stops waking us, so the block was real).
      Guikit.Vulkan.Wait_For_Events (0.016);
      Guikit.Vulkan.Poll_Events;

      --  The input in the order it came: a Backspace typed between two
      --  letters deletes the first of them, not the second.
      declare
         use type Glfw.Input.Keys.Key;
         use type Glfw.Input.Mouse.Button;
         Item  : Guikit.Input.Pending.Event;
         Taken : Boolean;
      begin
         loop
            Handle.Take (Item, Taken);
            exit when not Taken;
            case Item.Kind is
               when Guikit.Input.Pending.Character_Input =>
                  Guikit.Command_Palette.Insert (Palette, Guikit.Utf8.Encode (Item.Code));
               when Guikit.Input.Pending.Key_Input =>
                  if Item.Key = Glfw.Input.Keys.Escape then
                     Pending_Escape := True;
                  elsif Item.Key = Glfw.Input.Keys.Enter or else Item.Key = Glfw.Input.Keys.Numpad_Enter then
                     Pending_Enter := True;
                  elsif Item.Key = Glfw.Input.Keys.Up then
                     Guikit.Command_Palette.Move_Selection (Palette, -1);
                  elsif Item.Key = Glfw.Input.Keys.Down then
                     Guikit.Command_Palette.Move_Selection (Palette, 1);
                  elsif Item.Key = Glfw.Input.Keys.Home then
                     Guikit.Command_Palette.Select_First (Palette);
                  elsif Item.Key = Glfw.Input.Keys.Key_End then
                     Guikit.Command_Palette.Select_Last (Palette);
                  elsif Item.Key = Glfw.Input.Keys.Backspace then
                     Guikit.Command_Palette.Backspace (Palette);
                  end if;
               when Guikit.Input.Pending.Button_Input =>
                  --  Hit-tested after the frame is drawn, against its rows,
                  --  where the button went down.
                  if Item.Button = Glfw.Input.Mouse.Left_Button and then Item.Pressed then
                     Pending_Click := True;
                     Click_X := Integer (Glfw.Input.Mouse.Coordinate'Truncation (Item.X));
                     Click_Y := Integer (Glfw.Input.Mouse.Coordinate'Truncation (Item.Y));
                  end if;
               when Guikit.Input.Pending.Scroll_Input =>
                  --  Wheel: scroll up moves the selection up, down moves it down.
                  Guikit.Command_Palette.Move_Selection (Palette, -Item.Notches);
            end case;
         end loop;
      end;
      exit when Pending_Escape;

      declare
         App : Launcher.Applications.Application;
         Frame_W, Frame_H : Glfw.Size;
      begin
         --  A resize is not delivered through the input callbacks, so detect it
         --  here and mark dirty; otherwise the resized window would not repaint.
         Glfw.Windows.Get_Framebuffer_Size (As_Window (Handle), Frame_W, Frame_H);
         if Natural (Frame_W) /= Natural (Last_Frame_W)
           or else Natural (Frame_H) /= Natural (Last_Frame_H)
         then
            Handle.Mark_Dirty;
            Last_Frame_W := Frame_W;
            Last_Frame_H := Frame_H;
         end if;

         --  A change opens the grace window; we then keep presenting every frame
         --  through it (see Present_Grace_Frames) so input stays paced to the
         --  display, and only stop once genuinely idle. The Readback_Enabled arm
         --  keeps the (separate) smoke loop presenting.
         if Handle.Dirty then
            Present_Grace := Present_Grace_Frames;
            Handle.Clear_Dirty;
         end if;
         if Present_Grace > 0 or else Guikit.Vulkan.Readback_Enabled (Vulkan) then
            Draw_Frame (Handle, Vulkan, Text, Palette);
            if Present_Grace > 0 then
               Present_Grace := Present_Grace - 1;
            end if;
         end if;

         if Pending_Click then
            Pending_Click := False;
            if Guikit.Command_Palette.Click (Palette, Click_X, Click_Y) then
               Pending_Enter := True;
            end if;
         end if;

         if Pending_Enter then
            Pending_Enter := False;
            if Launcher.Model.Application_For
                 (M, Guikit.Command_Palette.Selected_Id (Palette), App)
            then
               --  Counted only once it has started: a launch that failed is not
               --  a use, and must not float the application up.
               if Launcher.Applications.Launch (App) then
                  Launcher.Model.Record_Launch (M, App);
                  exit;
               end if;
            end if;
         end if;
      end;
   end loop;

   Guikit.Vulkan.Shutdown (Vulkan);
   Glfw.Shutdown;
end Launcher.Main;

with Ada.Command_Line;
with Ada.Strings.Unbounded;
with Ada.Text_IO;

with Glfw;
with Glfw.Input.Keys;
with Glfw.Input.Mouse;
with Glfw.Windows;

with Guikit.Command_Palette;
with Guikit.Draw;
with Guikit.Text;
with Guikit.Utf8;
with Guikit.Vulkan;

with Launcher.Applications;
with Launcher.Fonts;
with Launcher.Model;

procedure Launcher.Main is
   use Ada.Strings.Unbounded;

   Line_Height : constant Positive := 26;

   --  GLFW window subclass: the input callbacks stash events into these pending
   --  fields, which the main loop drains once per frame.
   type Launcher_Window is new Glfw.Windows.Window with record
      Pending_Text      : Unbounded_String := Null_Unbounded_String;
      Pending_Escape    : Boolean := False;
      Pending_Enter     : Boolean := False;
      Pending_Up        : Natural := 0;
      Pending_Down      : Natural := 0;
      Pending_Home      : Boolean := False;
      Pending_End       : Boolean := False;
      Pending_Backspace : Natural := 0;
      Pending_Click     : Boolean := False;
      Pending_Scroll    : Integer := 0;
      Mouse_X           : Integer := -1;
      Mouse_Y           : Integer := -1;
   end record;

   overriding procedure Character_Entered
     (Object : not null access Launcher_Window;
      Char   : Wide_Wide_Character);
   overriding procedure Key_Changed
     (Object   : not null access Launcher_Window;
      Key      : Glfw.Input.Keys.Key;
      Scancode : Glfw.Input.Keys.Scancode;
      Action   : Glfw.Input.Keys.Action;
      Mods     : Glfw.Input.Keys.Modifiers);
   overriding procedure Mouse_Button_Changed
     (Object : not null access Launcher_Window;
      Button : Glfw.Input.Mouse.Button;
      State  : Glfw.Input.Button_State;
      Mods   : Glfw.Input.Keys.Modifiers);
   overriding procedure Mouse_Position_Changed
     (Object : not null access Launcher_Window;
      X      : Glfw.Input.Mouse.Coordinate;
      Y      : Glfw.Input.Mouse.Coordinate);
   overriding procedure Mouse_Scrolled
     (Object : not null access Launcher_Window;
      X      : Glfw.Input.Mouse.Scroll_Offset;
      Y      : Glfw.Input.Mouse.Scroll_Offset);

   type Window_Access is access all Launcher_Window;

   function As_Window (Handle : Window_Access) return Glfw.Windows.Window_Reference is
     (Glfw.Windows.Window_Reference (Handle));


   --  Encode one input codepoint as UTF-8, dropping control characters.
   overriding procedure Character_Entered
     (Object : not null access Launcher_Window;
      Char   : Wide_Wide_Character)
   is
      Code : constant Natural := Wide_Wide_Character'Pos (Char);
   begin
      --  Ignore control characters; Guikit.Utf8.Encode handles the UTF-8 bytes.
      if Code >= Character'Pos (' ') then
         Append (Object.Pending_Text, Guikit.Utf8.Encode (Code));
      end if;
   end Character_Entered;

   overriding procedure Key_Changed
     (Object   : not null access Launcher_Window;
      Key      : Glfw.Input.Keys.Key;
      Scancode : Glfw.Input.Keys.Scancode;
      Action   : Glfw.Input.Keys.Action;
      Mods     : Glfw.Input.Keys.Modifiers)
   is
      use type Glfw.Input.Keys.Action;
      use type Glfw.Input.Keys.Key;
      pragma Unreferenced (Scancode, Mods);
   begin
      if Action = Glfw.Input.Keys.Release then
         return;
      end if;
      if Key = Glfw.Input.Keys.Escape then
         Object.Pending_Escape := True;
      elsif Key = Glfw.Input.Keys.Enter or else Key = Glfw.Input.Keys.Numpad_Enter then
         Object.Pending_Enter := True;
      elsif Key = Glfw.Input.Keys.Up then
         Object.Pending_Up := Object.Pending_Up + 1;
      elsif Key = Glfw.Input.Keys.Down then
         Object.Pending_Down := Object.Pending_Down + 1;
      elsif Key = Glfw.Input.Keys.Home then
         Object.Pending_Home := True;
      elsif Key = Glfw.Input.Keys.Key_End then
         Object.Pending_End := True;
      elsif Key = Glfw.Input.Keys.Backspace then
         Object.Pending_Backspace := Object.Pending_Backspace + 1;
      end if;
   end Key_Changed;

   overriding procedure Mouse_Button_Changed
     (Object : not null access Launcher_Window;
      Button : Glfw.Input.Mouse.Button;
      State  : Glfw.Input.Button_State;
      Mods   : Glfw.Input.Keys.Modifiers)
   is
      use type Glfw.Input.Mouse.Button;
      use type Glfw.Input.Button_State;
      pragma Unreferenced (Mods);
   begin
      if Button = Glfw.Input.Mouse.Left_Button and then State = Glfw.Input.Pressed then
         Object.Pending_Click := True;
      end if;
   end Mouse_Button_Changed;

   overriding procedure Mouse_Position_Changed
     (Object : not null access Launcher_Window;
      X      : Glfw.Input.Mouse.Coordinate;
      Y      : Glfw.Input.Mouse.Coordinate) is
   begin
      Object.Mouse_X := Integer (X);
      Object.Mouse_Y := Integer (Y);
   end Mouse_Position_Changed;

   overriding procedure Mouse_Scrolled
     (Object : not null access Launcher_Window;
      X      : Glfw.Input.Mouse.Scroll_Offset;
      Y      : Glfw.Input.Mouse.Scroll_Offset)
   is
      pragma Unreferenced (X);
   begin
      --  Accumulate whole wheel notches; the main loop turns them into selection
      --  movement (wheel up moves the highlight up).
      Object.Pending_Scroll := Object.Pending_Scroll + Integer (Y);
   end Mouse_Scrolled;

   Handle       : constant Window_Access := new Launcher_Window;
   Vulkan       : Guikit.Vulkan.Vulkan_Renderer;
   Text         : Guikit.Text.Renderer;
   M            : Launcher.Model.State;
   Palette      : Guikit.Command_Palette.Palette;
   Ignore_St    : Guikit.Vulkan.Vulkan_Status;
   Ignore_Ts    : Guikit.Draw.Text_Render_Status;
   pragma Unreferenced (Ignore_St, Ignore_Ts);

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
           (Width => Natural (Window_W), Height => Natural (Window_H), others => 0);
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
         Icon_Ink : constant Float :=
           Guikit.Vulkan.Readback_Region_Ink_Fraction (Vk, 2, FH / 4, 48, FH / 2);
         Icons_Ok : constant Boolean := Icon_Ink > 0.001;
         --  Right edge over the results: ink means the scrollbar (all apps
         --  overflow the visible rows, so a thumb must be present).
         Scroll_Ink : constant Float :=
           Guikit.Vulkan.Readback_Region_Ink_Fraction
             (Vk, (if FW > 14 then FW - 14 else 0), FH / 4, 14, FH / 2);
         Scroll_Ok  : constant Boolean := Scroll_Ink > 0.0005;
      begin
         Ada.Text_IO.Put_Line
           ("launcher smoke: overall=" & Boolean'Image (Overall)
            & " search=" & Boolean'Image (Search)
            & " results=" & Boolean'Image (Results)
            & " icons=" & Boolean'Image (Icons_Ok)
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
         return;
      end if;
      Ignore_Ts :=
        Guikit.Text.Initialize
          (Text, Primary, Launcher.Fonts.Fallbacks,
           Pixel_Size   => 18,
           Cell_Width   => 14,
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
       Placeholder    => To_Unbounded_String ("Type to search applications..."),
       Empty_State    => To_Unbounded_String ("No matching applications"),
       Title          => Null_Unbounded_String));
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
      Guikit.Vulkan.Wait_For_Events (0.05);
      Guikit.Vulkan.Poll_Events;

      if Length (Handle.Pending_Text) > 0 then
         Guikit.Command_Palette.Insert (Palette, To_String (Handle.Pending_Text));
         Handle.Pending_Text := Null_Unbounded_String;
      end if;
      for I in 1 .. Handle.Pending_Backspace loop
         Guikit.Command_Palette.Backspace (Palette);
      end loop;
      Handle.Pending_Backspace := 0;
      for I in 1 .. Handle.Pending_Up loop
         Guikit.Command_Palette.Move_Selection (Palette, -1);
      end loop;
      Handle.Pending_Up := 0;
      for I in 1 .. Handle.Pending_Down loop
         Guikit.Command_Palette.Move_Selection (Palette, 1);
      end loop;
      Handle.Pending_Down := 0;
      if Handle.Pending_Home then
         Guikit.Command_Palette.Select_First (Palette);
         Handle.Pending_Home := False;
      end if;
      if Handle.Pending_End then
         Guikit.Command_Palette.Select_Last (Palette);
         Handle.Pending_End := False;
      end if;
      --  Wheel: scroll up moves the selection up, down moves it down.
      if Handle.Pending_Scroll /= 0 then
         Guikit.Command_Palette.Move_Selection (Palette, -Handle.Pending_Scroll);
         Handle.Pending_Scroll := 0;
      end if;
      exit when Handle.Pending_Escape;

      declare
         App : Launcher.Applications.Application;
      begin
         Draw_Frame (Handle, Vulkan, Text, Palette);

         if Handle.Pending_Click then
            Handle.Pending_Click := False;
            if Guikit.Command_Palette.Click (Palette, Handle.Mouse_X, Handle.Mouse_Y) then
               Handle.Pending_Enter := True;
            end if;
         end if;

         if Handle.Pending_Enter then
            Handle.Pending_Enter := False;
            if Launcher.Model.Application_For
                 (M, Guikit.Command_Palette.Selected_Id (Palette), App)
            then
               Launcher.Model.Record_Launch (M, App);
               if Launcher.Applications.Launch (App) then
                  exit;
               end if;
            end if;
         end if;
      end;
   end loop;

   Guikit.Vulkan.Shutdown (Vulkan);
   Glfw.Shutdown;
end Launcher.Main;

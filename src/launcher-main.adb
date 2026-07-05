with Ada.Command_Line;
with Ada.Strings.Unbounded;
with Ada.Text_IO;

with Glfw;
with Glfw.Input.Keys;
with Glfw.Input.Mouse;
with Glfw.Windows;

with Guikit.Draw;
with Guikit.Layout;
with Guikit.Palette;
with Guikit.Text;
with Guikit.Utf8;
with Guikit.Vulkan;

with Launcher.Applications;
with Launcher.Fonts;
with Launcher.Model;
with Launcher.Render;

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
   Ignore_St    : Guikit.Vulkan.Vulkan_Status;
   Ignore_Ts    : Guikit.Draw.Text_Render_Status;
   pragma Unreferenced (Ignore_St, Ignore_Ts);
begin
   Launcher.Model.Load (M);

   --  Headless diagnostic: print the discovered applications and exit.
   if Ada.Command_Line.Argument_Count >= 1
     and then Ada.Command_Line.Argument (1) = "--list"
   then
      for App of M.Apps loop
         Ada.Text_IO.Put_Line (To_String (App.Name) & "  ::  " & To_String (App.Exec));
      end loop;
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

   --  Main loop.
   while not Glfw.Windows.Should_Close (As_Window (Handle)) loop
      Guikit.Vulkan.Wait_For_Events (0.05);
      Guikit.Vulkan.Poll_Events;

      if Length (Handle.Pending_Text) > 0 then
         Launcher.Model.Insert (M, To_String (Handle.Pending_Text));
         Handle.Pending_Text := Null_Unbounded_String;
      end if;
      for I in 1 .. Handle.Pending_Backspace loop
         Launcher.Model.Backspace (M);
      end loop;
      Handle.Pending_Backspace := 0;
      for I in 1 .. Handle.Pending_Up loop
         Launcher.Model.Move_Selection (M, -1);
      end loop;
      Handle.Pending_Up := 0;
      for I in 1 .. Handle.Pending_Down loop
         Launcher.Model.Move_Selection (M, 1);
      end loop;
      Handle.Pending_Down := 0;
      if Handle.Pending_Home then
         Launcher.Model.Select_First (M);
         Handle.Pending_Home := False;
      end if;
      if Handle.Pending_End then
         Launcher.Model.Select_Last (M);
         Handle.Pending_End := False;
      end if;
      --  Wheel: scroll up moves the selection up, down moves it down.
      if Handle.Pending_Scroll /= 0 then
         Launcher.Model.Move_Selection (M, -Handle.Pending_Scroll);
         Handle.Pending_Scroll := 0;
      end if;
      exit when Handle.Pending_Escape;

      declare
         Window_W, Window_H : Glfw.Size;
         Frame_W,  Frame_H  : Glfw.Size;
      begin
         Glfw.Windows.Get_Size (As_Window (Handle), Window_W, Window_H);
         Glfw.Windows.Get_Framebuffer_Size (As_Window (Handle), Frame_W, Frame_H);

         Guikit.Vulkan.Ensure_Ready
           (Vulkan, As_Window (Handle), Natural (Frame_W), Natural (Frame_H));

         if Guikit.Vulkan.Swapchain_Ready (Vulkan) then
            declare
               Ranked : constant Guikit.Palette.Item_Vectors.Vector := Launcher.Model.Results (M);
               Rects  : Guikit.Draw.Rectangle_Command_Vectors.Vector;
               Texts  : Guikit.Draw.Text_Command_Vectors.Vector;
               Rows   : Guikit.Layout.Palette_Result_Row_Vectors.Vector;
               No_Tri        : Guikit.Draw.Triangle_Command_Vectors.Vector;
               No_Icons      : Guikit.Draw.Icon_Command_Vectors.Vector;
               No_Overlay    : Guikit.Draw.Rectangle_Command_Vectors.Vector;
               No_Overlay_Tx : Guikit.Draw.Text_Command_Vectors.Vector;
               Metrics : constant Guikit.Draw.Layout_Metrics :=
                 (Width => Natural (Window_W), Height => Natural (Window_H), others => 0);
               Glyphs  : Guikit.Draw.Text_Render_Result;
               Batch   : Guikit.Vulkan.Submission_Batch;
               App     : Launcher.Applications.Application;
            begin
               Launcher.Render.Build_Frame
                 (M, Ranked, Natural (Window_W), Natural (Window_H), Line_Height,
                  Handle.Mouse_X, Handle.Mouse_Y, Rects, Texts, Rows);

               if Handle.Pending_Click then
                  Handle.Pending_Click := False;
                  declare
                     Hit : constant Natural :=
                       Guikit.Layout.Palette_Result_At (Rows, Handle.Mouse_X, Handle.Mouse_Y);
                  begin
                     if Hit > 0 then
                        M.Selected := Hit;
                        Handle.Pending_Enter := True;
                     end if;
                  end;
               end if;

               if Handle.Pending_Enter then
                  Handle.Pending_Enter := False;
                  if Launcher.Model.Selected_Application (M, App)
                    and then Launcher.Applications.Launch (App)
                  then
                     exit;
                  end if;
               end if;

               Glyphs := Guikit.Text.Build_Glyphs (Text, Texts, No_Overlay_Tx);
               Batch  :=
                 Guikit.Vulkan.Build_Submission
                   (Rects, No_Tri, No_Icons, No_Overlay, Metrics, Guikit.Draw.Theme_Dark, Glyphs);
               Ignore_St :=
                 Guikit.Vulkan.Present_Frame (Vulkan, Batch, Natural (Frame_W), Natural (Frame_H));
            end;
         end if;
      end;
   end loop;

   Guikit.Vulkan.Shutdown (Vulkan);
   Glfw.Shutdown;
end Launcher.Main;

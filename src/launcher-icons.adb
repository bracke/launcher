with Ada.Directories;
with Ada.Environment_Variables;

with Interfaces;
with Interfaces.C;
with Interfaces.C.Strings;

with System;

package body Launcher.Icons is

   use type System.Address;

   type Const_String_Access is access constant String;

   function Gdk_Pixbuf_New_From_File_At_Size
     (Filename : Interfaces.C.Strings.chars_ptr;
      Width    : Interfaces.C.int;
      Height   : Interfaces.C.int;
      Error    : System.Address)
      return System.Address
     with Import, Convention => C, External_Name => "gdk_pixbuf_new_from_file_at_size";

   function Gdk_Pixbuf_Get_Width (P : System.Address) return Interfaces.C.int
     with Import, Convention => C, External_Name => "gdk_pixbuf_get_width";
   function Gdk_Pixbuf_Get_Height (P : System.Address) return Interfaces.C.int
     with Import, Convention => C, External_Name => "gdk_pixbuf_get_height";
   function Gdk_Pixbuf_Get_N_Channels (P : System.Address) return Interfaces.C.int
     with Import, Convention => C, External_Name => "gdk_pixbuf_get_n_channels";
   function Gdk_Pixbuf_Get_Rowstride (P : System.Address) return Interfaces.C.int
     with Import, Convention => C, External_Name => "gdk_pixbuf_get_rowstride";
   function Gdk_Pixbuf_Get_Pixels (P : System.Address) return System.Address
     with Import, Convention => C, External_Name => "gdk_pixbuf_get_pixels";
   procedure G_Object_Unref (O : System.Address)
     with Import, Convention => C, External_Name => "g_object_unref";

   function Env (Name, Default : String) return String is
   begin
      if Ada.Environment_Variables.Exists (Name)
        and then Ada.Environment_Variables.Value (Name) /= ""
      then
         return Ada.Environment_Variables.Value (Name);
      end if;
      return Default;
   end Env;

   function Exists (Path : String) return Boolean is
   begin
      return Path /= "" and then Ada.Directories.Exists (Path);
   exception
      when others =>
         return False;
   end Exists;

   Themes : constant array (1 .. 3) of Const_String_Access :=
     (new String'("hicolor"), new String'("Adwaita"), new String'("breeze"));
   Png_Sizes : constant array (1 .. 8) of Const_String_Access :=
     (new String'("512x512"), new String'("256x256"), new String'("128x128"),
      new String'("96x96"), new String'("64x64"), new String'("48x48"),
      new String'("32x32"), new String'("24x24"));
   Pixmap_Exts : constant array (1 .. 3) of Const_String_Access :=
     (new String'(".png"), new String'(".svg"), new String'(".xpm"));
   --  KDE/breeze uses <theme>/apps/<size>/<name> (category before a bare size),
   --  the reverse of the freedesktop <theme>/<size>/apps/<name> layout.
   Kde_Sizes : constant array (1 .. 6) of Const_String_Access :=
     (new String'("64"), new String'("48"), new String'("32"),
      new String'("24"), new String'("22"), new String'("16"));

   --  Resolve an icon name to a file by scanning the XDG icon theme directories,
   --  preferring a large PNG (always decodable) then a scalable SVG.
   function Resolve (Name : String) return String is
      Home      : constant String := Env ("HOME", "");
      Data_Home : constant String :=
        Env ("XDG_DATA_HOME", (if Home = "" then "" else Home & "/.local/share"));
      Bases : constant array (1 .. 4) of Const_String_Access :=
        (new String'((if Home = "" then "" else Home & "/.icons")),
         new String'((if Data_Home = "" then "" else Data_Home & "/icons")),
         new String'("/usr/local/share/icons"),
         new String'("/usr/share/icons"));
   begin
      for Base of Bases loop
         if Base.all /= "" then
            for Theme of Themes loop
               for Size of Png_Sizes loop
                  declare
                     Png : constant String :=
                       Base.all & "/" & Theme.all & "/" & Size.all & "/apps/" & Name & ".png";
                  begin
                     if Exists (Png) then
                        return Png;
                     end if;
                  end;
               end loop;
               declare
                  Svg : constant String :=
                    Base.all & "/" & Theme.all & "/scalable/apps/" & Name & ".svg";
               begin
                  if Exists (Svg) then
                     return Svg;
                  end if;
               end;
               --  KDE/breeze layout: <theme>/apps/<size>/<name>.{svg,png}.
               for Size of Kde_Sizes loop
                  declare
                     Kde_Svg : constant String :=
                       Base.all & "/" & Theme.all & "/apps/" & Size.all & "/" & Name & ".svg";
                     Kde_Png : constant String :=
                       Base.all & "/" & Theme.all & "/apps/" & Size.all & "/" & Name & ".png";
                  begin
                     if Exists (Kde_Svg) then
                        return Kde_Svg;
                     elsif Exists (Kde_Png) then
                        return Kde_Png;
                     end if;
                  end;
               end loop;
            end loop;
         end if;
      end loop;

      --  Legacy pixmaps (flat, no theme/size structure).
      for Ext of Pixmap_Exts loop
         declare
            Pixmap : constant String := "/usr/share/pixmaps/" & Name & Ext.all;
         begin
            if Exists (Pixmap) then
               return Pixmap;
            end if;
         end;
      end loop;
      return "";
   end Resolve;

   function Load_Pixbuf (Path : String; Size : Positive) return Loaded_Icon is
      Result : Loaded_Icon;
      C_Path : Interfaces.C.Strings.chars_ptr := Interfaces.C.Strings.New_String (Path);
      Pixbuf : System.Address := System.Null_Address;
   begin
      Pixbuf :=
        Gdk_Pixbuf_New_From_File_At_Size
          (C_Path, Interfaces.C.int (Size), Interfaces.C.int (Size), System.Null_Address);
      Interfaces.C.Strings.Free (C_Path);

      if Pixbuf = System.Null_Address then
         return Result;
      end if;

      declare
         W      : constant Natural := Natural (Gdk_Pixbuf_Get_Width (Pixbuf));
         H      : constant Natural := Natural (Gdk_Pixbuf_Get_Height (Pixbuf));
         N      : constant Natural := Natural (Gdk_Pixbuf_Get_N_Channels (Pixbuf));
         Stride : constant Natural := Natural (Gdk_Pixbuf_Get_Rowstride (Pixbuf));
         Addr   : constant System.Address := Gdk_Pixbuf_Get_Pixels (Pixbuf);
         type Byte_Array is array (Natural range <>) of Interfaces.Unsigned_8;
         Src    : Byte_Array (0 .. (if H = 0 then 0 else H * Stride - 1))
           with Import, Address => Addr;
      begin
         if W > 0 and then H > 0 and then N >= 3 and then Stride >= W * N then
            for Y in 0 .. H - 1 loop
               for X in 0 .. W - 1 loop
                  declare
                     Base : constant Natural := Y * Stride + X * N;
                  begin
                     Result.Pixels.Append (Src (Base));
                     Result.Pixels.Append (Src (Base + 1));
                     Result.Pixels.Append (Src (Base + 2));
                     Result.Pixels.Append (if N >= 4 then Src (Base + 3) else 255);
                  end;
               end loop;
            end loop;
            Result.Width := W;
            Result.Height := H;
         end if;
      end;

      G_Object_Unref (Pixbuf);
      return Result;
   exception
      when others =>
         if Pixbuf /= System.Null_Address then
            G_Object_Unref (Pixbuf);
         end if;
         return (Width => 0, Height => 0, Pixels => Guikit.Draw.Byte_Vectors.Empty_Vector);
   end Load_Pixbuf;

   function Load (Icon : String; Size : Positive) return Loaded_Icon is
      Path : constant String :=
        (if Icon = "" then ""
         elsif Icon (Icon'First) = '/' then (if Exists (Icon) then Icon else "")
         else Resolve (Icon));
   begin
      if Path = "" then
         return (Width => 0, Height => 0, Pixels => Guikit.Draw.Byte_Vectors.Empty_Vector);
      end if;
      return Load_Pixbuf (Path, Size);
   end Load;

end Launcher.Icons;

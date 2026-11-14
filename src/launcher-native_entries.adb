with Ada.Strings.Equal_Case_Insensitive;
with Ada.Strings.Fixed;

package body Launcher.Native_Entries is

   Link_Suffix      : constant String := ".lnk";
   Internet_Suffix  : constant String := ".url";
   ClickOnce_Suffix : constant String := ".appref-ms";

   function Has_Suffix (Name : String; Suffix : String) return Boolean is
     (Name'Length > Suffix'Length
      and then Ada.Strings.Equal_Case_Insensitive (Name (Name'Last - Suffix'Length + 1 .. Name'Last), Suffix));

   function Shortcut_Kind_Of (Name : String) return Shortcut_Kind is
   begin
      if Has_Suffix (Name, Link_Suffix) then
         return Shell_Link;
      elsif Has_Suffix (Name, Internet_Suffix) then
         return Internet_Shortcut;
      elsif Has_Suffix (Name, ClickOnce_Suffix) then
         return ClickOnce_Reference;
      else
         return Not_A_Shortcut;
      end if;
   end Shortcut_Kind_Of;

   function Display_Name (Name : String) return String is
      Suffix_Length : Natural := 0;
   begin
      case Shortcut_Kind_Of (Name) is
         when Shell_Link =>
            Suffix_Length := Link_Suffix'Length;
         when Internet_Shortcut =>
            Suffix_Length := Internet_Suffix'Length;
         when ClickOnce_Reference =>
            Suffix_Length := ClickOnce_Suffix'Length;
         when Not_A_Shortcut =>
            null;
      end case;
      return Name (Name'First .. Name'Last - Suffix_Length);
   end Display_Name;

   function Internet_Shortcut_URL (Text : String) return String is
      use Ada.Strings.Fixed;

      Blanks : constant String := " " & ASCII.HT;
      BOM    : constant String := [Character'Val (16#EF#), Character'Val (16#BB#), Character'Val (16#BF#)];

      function Trimmed (Item : String) return String is
         First : Natural := Item'First;
         Last  : Natural := Item'Last;
      begin
         while First <= Last and then Index (Blanks, [1 => Item (First)]) > 0 loop
            First := First + 1;
         end loop;
         while Last >= First and then Index (Blanks & ASCII.CR, [1 => Item (Last)]) > 0 loop
            Last := Last - 1;
         end loop;
         return Item (First .. Last);
      end Trimmed;

      Start      : Natural := Text'First;
      Stop       : Natural;
      In_Section : Boolean := False;
   begin
      if Text'Length >= BOM'Length and then Text (Text'First .. Text'First + BOM'Length - 1) = BOM then
         Start := Text'First + BOM'Length;
      end if;

      while Start <= Text'Last loop
         Stop := Index (Text (Start .. Text'Last), [1 => ASCII.LF]);
         if Stop = 0 then
            Stop := Text'Last + 1;
         end if;

         declare
            Line   : constant String := Trimmed (Text (Start .. Stop - 1));
            Equals : constant Natural := Index (Line, "=");
         begin
            if Line'Length >= 2 and then Line (Line'First) = '[' and then Line (Line'Last) = ']' then
               In_Section :=
                 Ada.Strings.Equal_Case_Insensitive
                   (Trimmed (Line (Line'First + 1 .. Line'Last - 1)), "InternetShortcut");
            elsif In_Section
              and then Equals > 0
              and then Ada.Strings.Equal_Case_Insensitive (Trimmed (Line (Line'First .. Equals - 1)), "URL")
            then
               return Trimmed (Line (Equals + 1 .. Line'Last));
            end if;
         end;

         Start := Stop + 1;
      end loop;
      return "";
   end Internet_Shortcut_URL;

   function Is_Bundle (Name : String) return Boolean is (Has_Suffix (Name, ".app"));

   function Descend_Into (Name : String; Depth : Positive) return Boolean is
     (Depth <= Max_Bundle_Folder_Depth
      and then Name'Length > 0
      and then Name (Name'First) /= '.'
      and then not Is_Bundle (Name)
      and then not Has_Suffix (Name, ".bundle")
      and then not Has_Suffix (Name, ".framework")
      and then not Has_Suffix (Name, ".plugin")
      and then not Has_Suffix (Name, ".kext"));

end Launcher.Native_Entries;

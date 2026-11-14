with AUnit;
with AUnit.Assertions;
with AUnit.Test_Cases;

with Launcher.Native_Entries;

--  Exercises Launcher.Native_Entries on every host: the Start Menu scan once
--  compared ".lnk" with case (NOTEPAD.LNK was missed) and knew no other kind
--  of shortcut, and the bundle scan read the top of /Applications only.
package body Launcher_Suite.Native_Entries is

   use AUnit.Assertions;
   use Launcher.Native_Entries;

   type Native_Entries_Test_Case is new AUnit.Test_Cases.Test_Case with null record;

   overriding function Name (T : Native_Entries_Test_Case) return AUnit.Message_String;
   overriding procedure Register_Tests (T : in out Native_Entries_Test_Case);

   procedure Test_Shortcut_Kinds (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Internet_Shortcut_URL (T : in out AUnit.Test_Cases.Test_Case'Class);
   procedure Test_Bundle_Folders (T : in out AUnit.Test_Cases.Test_Case'Class);

   overriding function Name (T : Native_Entries_Test_Case) return AUnit.Message_String is
      pragma Unreferenced (T);
   begin
      return AUnit.Format ("launcher native application records");
   end Name;

   overriding procedure Register_Tests (T : in out Native_Entries_Test_Case) is
   begin
      AUnit.Test_Cases.Registration.Register_Routine
        (T, Test_Shortcut_Kinds'Access, "shortcut suffixes .lnk .url .appref-ms are matched without case");
      AUnit.Test_Cases.Registration.Register_Routine
        (T, Test_Internet_Shortcut_URL'Access, "an Internet shortcut's URL is read from its own section");
      AUnit.Test_Cases.Registration.Register_Routine
        (T, Test_Bundle_Folders'Access, "a bundle scan goes into plain folders, bounded, never into a bundle");
   end Register_Tests;

   procedure Test_Shortcut_Kinds (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert (Shortcut_Kind_Of ("Notepad.lnk") = Shell_Link, ".lnk is a shell link");
      Assert (Shortcut_Kind_Of ("NOTEPAD.LNK") = Shell_Link, "and so is .LNK");
      Assert (Shortcut_Kind_Of ("Game.Lnk") = Shell_Link, "and .Lnk");
      Assert (Shortcut_Kind_Of ("Some Game.url") = Internet_Shortcut, ".url is an Internet shortcut");
      Assert (Shortcut_Kind_Of ("Some Game.URL") = Internet_Shortcut, "and so is .URL");
      Assert (Shortcut_Kind_Of ("Tool.appref-ms") = ClickOnce_Reference, ".appref-ms is a ClickOnce reference");
      Assert (Shortcut_Kind_Of ("Tool.APPREF-MS") = ClickOnce_Reference, "and so is .APPREF-MS");
      Assert (Shortcut_Kind_Of ("desktop.ini") = Not_A_Shortcut, "desktop.ini is not a shortcut");
      Assert (Shortcut_Kind_Of (".lnk") = Not_A_Shortcut, "a bare suffix names nothing");
      Assert (Shortcut_Kind_Of ("readme.lnk.txt") = Not_A_Shortcut, "the suffix must end the name");
      Assert (Shortcut_Kind_Of ("") = Not_A_Shortcut, "nor is an empty name");

      Assert (Display_Name ("NOTEPAD.LNK") = "NOTEPAD", "the shown name drops .LNK");
      Assert (Display_Name ("Some Game.url") = "Some Game", "and .url");
      Assert (Display_Name ("Tool.appref-ms") = "Tool", "and .appref-ms");
      Assert (Display_Name ("desktop.ini") = "desktop.ini", "and leaves any other name alone");

      Assert (Has_Suffix ("Safari.APP", ".app"), "Has_Suffix ignores case");
      Assert (not Has_Suffix ("app", ".app"), "Has_Suffix wants more than the suffix");
   end Test_Shortcut_Kinds;

   procedure Test_Internet_Shortcut_URL (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
      CRLF : constant String := ASCII.CR & ASCII.LF;
      BOM  : constant String := [Character'Val (16#EF#), Character'Val (16#BB#), Character'Val (16#BF#)];
   begin
      Assert (Internet_Shortcut_URL ("[InternetShortcut]" & CRLF & "URL=steam://rungameid/570" & CRLF)
                = "steam://rungameid/570",
              "the URL of a CR LF file, without its CR");
      Assert (Internet_Shortcut_URL
                (BOM & "[{000214A0-0000-0000-C000-000000000046}]" & CRLF & "Prop3=19,11" & CRLF
                 & "[InternetShortcut]" & CRLF & "IDList=" & CRLF & "IconIndex=0" & CRLF
                 & "URL=https://example.org/a?b=c" & CRLF & "IconFile=C:\x.ico" & CRLF)
                = "https://example.org/a?b=c",
              "past a byte order mark and another section, and a value holding '='");
      Assert (Internet_Shortcut_URL ("[internetshortcut]" & ASCII.LF & "  url = https://example.org  " & ASCII.LF)
                = "https://example.org",
              "section and key without case, blanks trimmed, LF line ends");
      Assert (Internet_Shortcut_URL ("[Other]" & CRLF & "URL=https://wrong.example" & CRLF) = "",
              "a URL in another section is not the shortcut's");
      Assert (Internet_Shortcut_URL ("[InternetShortcut]" & CRLF & "IconIndex=0" & CRLF) = "",
              "no URL line, no URL");
      Assert (Internet_Shortcut_URL ("[InternetShortcut]" & CRLF & "URLX=https://x.example" & CRLF) = "",
              "a key that only starts with URL is not URL");
      Assert (Internet_Shortcut_URL ("") = "", "an empty file names nothing");
   end Test_Internet_Shortcut_URL;

   procedure Test_Bundle_Folders (T : in out AUnit.Test_Cases.Test_Case'Class) is
      pragma Unreferenced (T);
   begin
      Assert (Is_Bundle ("Safari.app"), "Safari.app is a bundle");
      Assert (Is_Bundle ("Odd.APP"), "a bundle's suffix is matched without case");
      Assert (not Is_Bundle ("Utilities"), "Utilities is not");

      Assert (Descend_Into ("Utilities", 1), "a plain folder in the root is scanned");
      Assert (Descend_Into ("Microsoft Office", 1), "as is a vendor's folder");
      Assert (Descend_Into ("Tools", Max_Bundle_Folder_Depth), "down to the depth bound");
      Assert (not Descend_Into ("Tools", Max_Bundle_Folder_Depth + 1), "and no further");
      Assert (not Descend_Into ("Safari.app", 1), "a bundle is not gone into");
      Assert (not Descend_Into ("Odd.APP", 1), "whatever the case of its suffix");
      Assert (not Descend_Into ("Sparkle.framework", 1), "nor is a framework");
      Assert (not Descend_Into ("Helper.bundle", 1), "nor any other package");
      Assert (not Descend_Into (".Trash", 1), "nor a hidden folder");
      Assert (not Descend_Into ("", 1), "nor a folder with no name");
   end Test_Bundle_Folders;

   function Suite return AUnit.Test_Suites.Access_Test_Suite is
      Result : constant AUnit.Test_Suites.Access_Test_Suite := new AUnit.Test_Suites.Test_Suite;
   begin
      Result.Add_Test (AUnit.Test_Cases.Test_Case_Access'(new Native_Entries_Test_Case));
      return Result;
   end Suite;

end Launcher_Suite.Native_Entries;

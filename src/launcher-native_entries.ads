--  The host-independent part of reading what Windows and macOS record about
--  their applications: which file names are shortcuts, what an Internet
--  shortcut points at, and which folders a bundle scan goes into.
--
--  The scans themselves live in each host's Launcher.Applications.Platform
--  body and run only there; these rules are plain text decisions, kept here
--  so that the test suite checks them on every host, Linux included.
package Launcher.Native_Entries is

   --  The kinds of Start Menu entry the launcher starts.
   type Shortcut_Kind is
     (
      --  Not an entry the launcher reads.
      Not_A_Shortcut,

      --  A shell link (".lnk"): the host resolves it and starts its target.
      Shell_Link,

      --  An Internet shortcut (".url"): an INI file whose
      --  [InternetShortcut] section names a URL, which the host opens. Steam
      --  and other stores install games as these.
      Internet_Shortcut,

      --  A ClickOnce application reference (".appref-ms"): the host's
      --  ClickOnce handler opens it.
      ClickOnce_Reference);

   --  Whether Name ends in Suffix, compared without regard to ASCII case, as
   --  Windows and macOS compare names ("NOTEPAD.LNK" ends in ".lnk").
   --
   --  @param Name A file name.
   --  @param Suffix The ending looked for, such as ".lnk".
   --  @return True when Name is longer than Suffix and ends in it.
   function Has_Suffix (Name : String; Suffix : String) return Boolean;

   --  What kind of Start Menu entry the file Name is, by its suffix.
   --
   --  @param Name A file name.
   --  @return Its kind, or Not_A_Shortcut.
   function Shortcut_Kind_Of (Name : String) return Shortcut_Kind;

   --  The name a Start Menu entry is shown under: its file name without the
   --  shortcut suffix ("Notepad.LNK" is "Notepad").
   --
   --  @param Name A file name.
   --  @return Name less its shortcut suffix; Name itself when it has none.
   function Display_Name (Name : String) return String;

   --  The URL an Internet shortcut opens: the URL= value of its
   --  [InternetShortcut] section. Section and key are matched without regard
   --  to case, lines may end in CR LF, a UTF-8 byte order mark is skipped,
   --  and the value is trimmed of surrounding blanks. A URL= line in any
   --  other section is not the shortcut's.
   --
   --  @param Text The shortcut file's contents.
   --  @return The URL, or "" when the file names none.
   function Internet_Shortcut_URL (Text : String) return String;

   --  How many folders below /Applications (or ~/Applications) a bundle
   --  scan goes: vendors put their bundles in folders of their own
   --  ("/Applications/Microsoft Office/Word.app"), seldom deeper.
   Max_Bundle_Folder_Depth : constant := 3;

   --  Whether the folder Name is an application bundle (".app").
   --
   --  @param Name A folder's name.
   --  @return True for a bundle.
   function Is_Bundle (Name : String) return Boolean;

   --  Whether a bundle scan goes into the folder Name, met Depth folders
   --  below the scan's root: a plain folder, not hidden, not a package of
   --  any kind (".app", ".bundle", ".framework", ".plugin", ".kext" -- a
   --  package is one thing, and its insides are not the user's
   --  applications), and not past Max_Bundle_Folder_Depth.
   --
   --  @param Name The folder's name.
   --  @param Depth How many folders below the root it is (1 for a folder in the root).
   --  @return True to scan it.
   function Descend_Into (Name : String; Depth : Positive) return Boolean;

end Launcher.Native_Entries;

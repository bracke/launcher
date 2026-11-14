with AUnit.Test_Suites;

package Launcher_Suite.Native_Entries is

   --  Tests for the host-independent rules of reading Windows shortcuts and
   --  macOS bundle folders: suffixes without case, Internet shortcut URLs, and
   --  which folders a bundle scan goes into.
   --
   --  @return Test suite for Launcher.Native_Entries.
   function Suite return AUnit.Test_Suites.Access_Test_Suite;

end Launcher_Suite.Native_Entries;

with AUnit.Test_Suites;

package Launcher_Suite.Applications is

   --  Tests for reading Desktop Entry files: string escapes, Exec splitting and
   --  field codes, TryExec, OnlyShowIn/NotShowIn, terminals and subfolder ids.
   --
   --  @return Test suite for Launcher.Applications.
   function Suite return AUnit.Test_Suites.Access_Test_Suite;

end Launcher_Suite.Applications;

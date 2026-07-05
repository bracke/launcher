with AUnit.Test_Suites;

package Launcher_Suite.Model is

   --  Tests for the launcher model: query editing, selection movement, and the
   --  mapping from a highlighted result back to an application.
   --
   --  @return Test suite for Launcher.Model.
   function Suite return AUnit.Test_Suites.Access_Test_Suite;

end Launcher_Suite.Model;

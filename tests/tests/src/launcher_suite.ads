with AUnit.Test_Suites;

package Launcher_Suite is

   --  Return the complete launcher AUnit suite.
   --
   --  @return Test suite containing the launcher unit tests.
   function Suite return AUnit.Test_Suites.Access_Test_Suite;

end Launcher_Suite;

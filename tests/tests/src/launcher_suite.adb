with Launcher_Suite.Applications;
with Launcher_Suite.Model;
with Launcher_Suite.Usage;

package body Launcher_Suite is

   function Suite return AUnit.Test_Suites.Access_Test_Suite is
      Result : constant AUnit.Test_Suites.Access_Test_Suite := new AUnit.Test_Suites.Test_Suite;
   begin
      Result.Add_Test (Launcher_Suite.Applications.Suite);
      Result.Add_Test (Launcher_Suite.Model.Suite);
      Result.Add_Test (Launcher_Suite.Usage.Suite);
      return Result;
   end Suite;

end Launcher_Suite;

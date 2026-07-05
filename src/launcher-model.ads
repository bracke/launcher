with Guikit.Palette;

with Launcher.Applications;

--  The launcher's state and the pure operations over it: the installed
--  applications, the search query, the highlighted result and the scroll
--  offset. Filtering/ranking is delegated to Guikit.Palette; the model just
--  turns the app list into palette items and maps a result back to an app.
package Launcher.Model is

   type State is record
      Apps     : Applications.Application_Vectors.Vector;
      Query    : UString;
      Selected : Natural := 1;  --  1-based index into the current results; 0 = none
      Offset   : Natural := 0;  --  result rows scrolled off the top
   end record;

   --  Populate the state with the installed applications.
   procedure Load (M : in out State);

   --  The applications matching the current query, ranked best-first (an empty
   --  query lists them all in name order). Each item's Id is the one-based index
   --  of the application in M.Apps.
   --
   --  @param M Launcher state.
   --  @return Ranked palette items for the current query.
   function Results (M : State) return Guikit.Palette.Item_Vectors.Vector;

   --  Append typed text to the query and reset the selection to the top.
   procedure Insert (M : in out State; Text : String);

   --  Delete the last query character (UTF-8 aware) and reset the selection.
   procedure Backspace (M : in out State);

   --  Move the highlighted result by Delta_Rows, clamped to the result range.
   procedure Move_Selection (M : in out State; Delta_Rows : Integer);

   --  The application the current selection points at.
   --
   --  @param M Launcher state.
   --  @param App The selected application (valid only when the result is True).
   --  @return True when a selectable result is highlighted.
   function Selected_Application
     (M   : State;
      App : out Applications.Application)
      return Boolean;

end Launcher.Model;

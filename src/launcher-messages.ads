package Launcher.Messages is
   --  Return the localized text for a catalog Key (for example
   --  "palette.placeholder" or "app.name"), rendered through the messages crate
   --  against share/launcher.catalog. Falls back to Key when it is absent from
   --  the catalog.
   function Text (Key : String) return String;
end Launcher.Messages;

{**
license: Apache-2.0
copyright: Copyright 2026 Liam Seamus Coughlin
---
The fpcunit console runner (plan story S00, task 00.4)
@br
The runner executes every registered test case with a plain-text report.
}
program YamlPuller.RunTests;

{$mode delphi}{$H+}

uses
  SysUtils, Classes, consoletestrunner, YamlPuller.Compliance.Test,
  YamlPuller.Schema.Test, YamlPuller.Parse.Test, YamlPuller.Streaming.Test,
  YamlPuller.Section.Test;

var
  App: TTestRunner;

begin
  App := TTestRunner.Create(nil);
  try
    App.Initialize;
    App.Title := 'YamlPuller test suite';
    App.Run;
  finally
    App.Free;
  end;
end.

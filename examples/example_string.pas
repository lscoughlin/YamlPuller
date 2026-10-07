{**
license: Apache-2.0
copyright: Copyright 2026 Liam Seamus Coughlin
---
Example: parse a UTF-8 string (plan story S15).
@br
The program creates a puller from a string with the FromString method. The
program parses the stream and writes the JSON value.
}
program example_string;

{$mode delphi}{$H+}

uses
  SysUtils, fpjson, YamlPuller;

var
  Puller: TYamlPuller;
  Data: TJSONData;

begin
  Puller := TYamlPullerFactory.FromString(
    'name: example' + #10 +
    'count: 3' + #10 +
    'enabled: true' + #10);
  try
    Data := Puller.Parse;
    try
      WriteLn(Data.AsJSON);
    finally
      Data.Free;
    end;
  finally
    Puller.Free;
  end;
end.

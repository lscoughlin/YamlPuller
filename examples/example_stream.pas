{**
license: Apache-2.0
copyright: Copyright 2026 Liam Seamus Coughlin
---
Example: parse a stream (plan story S15).
@br
The program creates a puller from a TMemoryStream with the FromStream method.
The program parses the stream and writes the JSON value.
}
program example_stream;

{$mode delphi}{$H+}

uses
  SysUtils, Classes, fpjson, YamlPuller;

var
  Source: TMemoryStream;
  Puller: TYamlPuller;
  Data: TJSONData;
  S: UTF8String;

begin
  S := 'items:' + #10 + '  - one' + #10 + '  - two' + #10;
  Source := TMemoryStream.Create;
  try
    Source.Write(S[1], Length(S));
    Source.Position := 0;
    Puller := TYamlPullerFactory.FromStream(Source);
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
  finally
    Source.Free;
  end;
end.

{**
license: Apache-2.0
copyright: Copyright 2026 Liam Seamus Coughlin
---
Example: parse one subsection of the stream.
@br
The example reads the events until the value of the member server, then
parses that value alone with Parse(event, data).
}
program example_section;

{$mode delphi}{$H+}

uses
  SysUtils, fpjson, YamlPuller, YamlPuller.Events;

var
  Puller: TYamlPuller;
  Event, Found: TYamlEvent;
  Data: TJSONData;

begin
  Puller := TYamlPullerFactory.FromString(
    'server:' + LineEnding +
    '  host: localhost' + LineEnding +
    '  port: 8080' + LineEnding);
  try
    Found := Default(TYamlEvent);
    while Puller.HasNext do
    begin
      Event := Puller.Next;
      if (Event.EventType = yetMappingStart) and (Event.Line = 2) then
      begin
        Found := Event;
        Break;
      end;
    end;
    if Found.EventType = yetMappingStart then
    begin
      Puller.Parse(Found, Data);
      try
        WriteLn(Data.AsJSON);
      finally
        Data.Free;
      end;
    end;
  finally
    Puller.Free;
  end;
end.

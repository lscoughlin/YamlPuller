{**
license: Apache-2.0
copyright: Copyright 2026 Liam Seamus Coughlin
---
Example: read the event stream (plan story S15).
@br
The program creates a puller from a string and walks the events with the Next
call. The program writes the event type, the event text, the position, and the
nest level. The program stops at the first mapping end event.
}
program example_events;

{$mode delphi}{$H+}

uses
  SysUtils, YamlPuller, YamlPuller.Events;

var
  Puller: TYamlPuller;
  Event: TYamlEvent;

begin
  Puller := TYamlPullerFactory.FromString(
    'list:' + #10 + '  - one' + #10 + '  - two' + #10);
  try
    while Puller.HasNext do
    begin
      Event := Puller.Next;
      WriteLn(YamlEventTypeName[Event.EventType], ' [', Event.EventText,
        '] line=', Event.Line, ' col=', Event.Column,
        ' level=', Event.NestLevel);
    end;
  finally
    Puller.Free;
  end;
end.

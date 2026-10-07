{**
license: Apache-2.0
copyright: Copyright 2026 Liam Seamus Coughlin
---
The public API (plan story S10).
@br
TYamlPullerFactory selects the source and returns a puller. TYamlPuller reads
the event stream or builds the JSON value. The README holds the public
contract. The factory returns a TYamlPuller for each of the four data sources.
}
unit YamlPuller;

{$mode delphi}{$H+}

interface

uses
  SysUtils, Classes, fpjson, YamlPuller.Events, YamlPuller.Errors,
  YamlPuller.Input, YamlPuller.Scanner.Core, YamlPuller.Scanner,
  YamlPuller.Parser, YamlPuller.JSON;

type
  /// the puller
  TYamlPuller = class
  private
    FInput: TYamlInput;
    FOwnsInput: Boolean;
    FEvents: array of TYamlEventEx;
    FIndex: Integer;
    function FindEventIndex(const AEvent: TYamlEvent): Integer;
  public
    /// create a puller from a source. The puller releases the source when
    /// AOwnsInput is true.
    constructor Create(AInput: TYamlInput; AOwnsInput: Boolean = True);
    destructor Destroy; override;
    /// read the next event
    function Next: TYamlEvent;
    /// true while an event remains
    function HasNext: Boolean;
    /// parse the whole source into an FCL JSON value. The caller releases
    /// the result.
    function Parse: TJSONData; overload;
    /// parse the value that starts at AEvent. The caller releases AData.
    ///
    /// AData is the value of the node when AEvent is a mapping start, a
    /// sequence start, a scalar, or an alias. AData is the value of the
    /// whole document when AEvent is a document start. AData is nil when
    /// AEvent is a stream start or an end event, because such an event
    /// starts no value.
    ///
    /// An alias inside the value resolves to an anchor that is complete
    /// before AEvent, in the same document. The event identifies the start
    /// by its value, so AEvent must come from this puller.
    procedure Parse(const AEvent: TYamlEvent; out AData: TJSONData); overload;
  end;

  /// the source factory. Each method returns a ready puller.
  TYamlPullerFactory = class
  public
    class function FromFile(const AFile: THandle): TYamlPuller;
    class function FromStream(AStream: TStream): TYamlPuller;
    class function FromBytes(const ABytes: TBytes): TYamlPuller;
    class function FromString(const AText: UTF8String): TYamlPuller;
  end;

/// a short name for each event type
function EventTypeName(AType: TYamlEventType): string;

implementation

function EventTypeName(AType: TYamlEventType): string;
begin
  Result := YamlEventTypeName[AType];
end;

{ TYamlPuller }

constructor TYamlPuller.Create(AInput: TYamlInput; AOwnsInput: Boolean);
var
  Scanner: TYamlScanner;
  Parser: TYamlParser;
begin
  inherited Create;
  FInput := AInput;
  FOwnsInput := AOwnsInput;
  Scanner := TYamlScanner.Create(FInput);
  try
    Parser := TYamlParser.Create;
    try
      FEvents := Parser.Parse(Scanner.Scan);
    finally
      Parser.Free;
    end;
  finally
    Scanner.Free;
  end;
  FIndex := 0;
end;

destructor TYamlPuller.Destroy;
begin
  if FOwnsInput then
    FInput.Free;
  inherited Destroy;
end;

function TYamlPuller.Next: TYamlEvent;
begin
  if FIndex <= High(FEvents) then
  begin
    Result := PublicEvent(FEvents[FIndex]);
    Inc(FIndex);
  end
  else
    Result := PublicEvent(MakeEvent(yetStreamEnd, '', 0, 0, 0));
end;

function TYamlPuller.HasNext: Boolean;
begin
  Result := FIndex <= High(FEvents);
end;

function TYamlPuller.Parse: TJSONData;
var
  Builder: TYamlJsonBuilder;
begin
  Builder := TYamlJsonBuilder.Create;
  try
    Result := Builder.Build(FEvents);
  finally
    Builder.Free;
  end;
end;

function TYamlPuller.FindEventIndex(const AEvent: TYamlEvent): Integer;
var
  I: Integer;
begin
  for I := 0 to High(FEvents) do
    if (FEvents[I].EventType = AEvent.EventType)
      and (FEvents[I].Line = AEvent.Line)
      and (FEvents[I].Column = AEvent.Column)
      and (FEvents[I].NestLevel = AEvent.NestLevel)
      and (FEvents[I].EventText = AEvent.EventText) then
      Exit(I);
  Result := -1;
end;

procedure TYamlPuller.Parse(const AEvent: TYamlEvent; out AData: TJSONData);
var
  Builder: TYamlJsonBuilder;
  Index: Integer;
begin
  AData := nil;
  Index := FindEventIndex(AEvent);
  if Index < 0 then
    raise EYamlParserError.Create('The event is not part of this stream');
  Builder := TYamlJsonBuilder.Create;
  try
    // BuildSection returns false when the event starts no value, so AData
    // stays nil in that case.
    Builder.BuildSection(FEvents, Index, AData);
  finally
    Builder.Free;
  end;
end;

{ TYamlPullerFactory }

class function TYamlPullerFactory.FromFile(const AFile: THandle): TYamlPuller;
begin
  Result := TYamlPuller.Create(TYamlInput.FromFile(AFile));
end;

class function TYamlPullerFactory.FromStream(AStream: TStream): TYamlPuller;
begin
  Result := TYamlPuller.Create(TYamlInput.FromStream(AStream));
end;

class function TYamlPullerFactory.FromBytes(const ABytes: TBytes): TYamlPuller;
begin
  Result := TYamlPuller.Create(TYamlInput.FromBytes(ABytes));
end;

class function TYamlPullerFactory.FromString(const AText: UTF8String): TYamlPuller;
begin
  Result := TYamlPuller.Create(TYamlInput.FromString(AText));
end;

end.

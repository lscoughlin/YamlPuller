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
  public
    /// create a puller from a source. The puller releases the source when
    /// AOwnsInput is true.
    constructor Create(AInput: TYamlInput; AOwnsInput: Boolean = True);
    destructor Destroy; override;
    /// read the next event
    function Next: TYamlEvent;
    /// true while an event remains
    function HasNext: Boolean;
    /// parse the whole source into an FCL JSON value
    function Parse: TJSONData;
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

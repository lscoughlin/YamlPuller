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
    FScanner: TYamlScanner;
    FParser: TYamlParser;
    FEvents: TArray<TYamlEventEx>;
    FIndex: Integer;
    FStreamDone: Boolean;
    FLog: TArray<TYamlEventEx>;
    FDocEnds: TArray<Integer>;
    function FindEventIndex(const AEvents: TArray<TYamlEventEx>;
      const AEvent: TYamlEvent): Integer;
    function BuildLog: TArray<TYamlEventEx>;
    /// fetch events until the event at AIndex has its node end in the log.
    /// AData is the value of the node. The result is true when the node end
    /// is in the log. The result is false when the stream ends first.
    function BuildSectionFromLog(AIndex: Integer;
      out AData: TJSONData): Boolean;
    function NextEvent: TYamlEventEx;
    function GetDocumentsRead: Integer;
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
    /// the number of document regions that the puller has read
    property DocumentsRead: Integer read GetDocumentsRead;
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
begin
  inherited Create;
  FInput := AInput;
  FOwnsInput := AOwnsInput;
  FScanner := TYamlScanner.Create(FInput);
  FParser := TYamlParser.Create;
  SetLength(FEvents, 0);
  FIndex := 0;
  FStreamDone := False;
  SetLength(FLog, 0);
  SetLength(FDocEnds, 0);
end;

destructor TYamlPuller.Destroy;
begin
  FParser.Free;
  FScanner.Free;
  if FOwnsInput then
    FInput.Free;
  inherited Destroy;
end;

function TYamlPuller.BuildLog: TArray<TYamlEventEx>;
var
  Tokens: TArray<TYamlToken>;
  Part: TArray<TYamlEventEx>;
  I: Integer;
begin
  // drain the rest of the stream into the log. A document region is read
  // and parsed only when the caller asks for its events. Every event is
  // appended once, so the log holds the stream in order.
  while not FStreamDone do
  begin
    if FScanner.Done then
    begin
      Part := FParser.ParseStreamEnd;
      FStreamDone := True;
    end
    else
    begin
      Tokens := FScanner.NextDocumentTokens;
      Part := FParser.ParseDocumentTokens(Tokens);
    end;
    for I := 0 to High(Part) do
    begin
      SetLength(FLog, Length(FLog) + 1);
      FLog[High(FLog)] := Part[I];
    end;
  end;
  Result := FLog;
end;

function TYamlPuller.GetDocumentsRead: Integer;
begin
  Result := FScanner.DocumentsRead;
end;

function TYamlPuller.NextEvent: TYamlEventEx;
var
  Tokens: TArray<TYamlToken>;
  Part: TArray<TYamlEventEx>;
  I: Integer;
begin
  if FIndex <= High(FEvents) then
  begin
    Result := FEvents[FIndex];
    Inc(FIndex);
    Exit;
  end;
  while True do
  begin
    if FScanner.Done then
    begin
      Part := FParser.ParseStreamEnd;
      FStreamDone := True;
    end
    else
    begin
      Tokens := FScanner.NextDocumentTokens;
      Part := FParser.ParseDocumentTokens(Tokens);
    end;
    if Length(Part) > 0 then
    begin
      FEvents := Part;
      FIndex := 0;
      // the fetched events join the log at the fetch point
      for I := 0 to High(Part) do
      begin
        SetLength(FLog, Length(FLog) + 1);
        FLog[High(FLog)] := Part[I];
        // record where each document ends, so the section operation can
        // stop reading at a document boundary
        if Part[I].EventType = yetDocumentEnd then
        begin
          SetLength(FDocEnds, Length(FDocEnds) + 1);
          FDocEnds[High(FDocEnds)] := High(FLog);
        end;
      end;
      Result := FEvents[FIndex];
      Inc(FIndex);
      Exit;
    end;
    if FStreamDone then
      Exit(MakeEvent(yetStreamEnd, '', 0, 0, 0));
  end;
end;

function TYamlPuller.Next: TYamlEvent;
begin
  Result := PublicEvent(NextEvent);
end;

function TYamlPuller.HasNext: Boolean;
begin
  Result := (FIndex <= High(FEvents)) or (not FStreamDone);
end;

function TYamlPuller.Parse: TJSONData;
var
  Builder: TYamlJsonBuilder;
  All: TArray<TYamlEventEx>;
begin
  Builder := TYamlJsonBuilder.Create;
  try
    All := BuildLog;
    Result := Builder.Build(All);
  finally
    Builder.Free;
  end;
end;
function TYamlPuller.FindEventIndex(const AEvents: TArray<TYamlEventEx>;
  const AEvent: TYamlEvent): Integer;
var
  I: Integer;
begin
  for I := 0 to High(AEvents) do
    if (AEvents[I].EventType = AEvent.EventType)
      and (AEvents[I].Line = AEvent.Line)
      and (AEvents[I].Column = AEvent.Column)
      and (AEvents[I].NestLevel = AEvent.NestLevel)
      and (AEvents[I].EventText = AEvent.EventText) then
      Exit(I);
  Result := -1;
end;

procedure TYamlPuller.Parse(const AEvent: TYamlEvent; out AData: TJSONData);
var
  Index: Integer;
  Ready: Boolean;
begin
  AData := nil;
  Index := FindEventIndex(FLog, AEvent);
  // the event can be in a document that the puller has not read. Read
  // forward one document at a time until the event is in the log, or the
  // stream ends. The value needs only the events up to the node end, so
  // the read stops at that point.
  while (Index < 0) and (not FStreamDone) do
  begin
    NextEvent;
    Index := FindEventIndex(FLog, AEvent);
  end;
  if Index < 0 then
    raise EYamlParserError.Create('The event is not part of this stream');
  // BuildSectionFromLog returns false when the event starts no value, so
  // AData stays nil in that case.
  Ready := BuildSectionFromLog(Index, AData);
  if not Ready then
    AData.Free;
end;

function TYamlPuller.BuildSectionFromLog(AIndex: Integer;
  out AData: TJSONData): Boolean;
var
  Builder: TYamlJsonBuilder;
  Need, EndIndex, K: Integer;
begin
  AData := nil;
  Need := AIndex + 1;
  if (FLog[AIndex].EventType = yetMappingStart)
    or (FLog[AIndex].EventType = yetSequenceStart) then
  begin
    // the node needs its own matching end event
    EndIndex := TYamlJsonBuilder.FindNodeEnd(FLog, AIndex);
    while (EndIndex > High(FLog)) and (not FStreamDone) do
    begin
      NextEvent;
      EndIndex := TYamlJsonBuilder.FindNodeEnd(FLog, AIndex);
    end;
    if EndIndex > High(FLog) then
      Exit(False);
    Need := EndIndex + 1;
  end;
  if FLog[AIndex].EventType = yetDocumentStart then
  begin
    // the document needs the first document end event after the start
    EndIndex := -1;
    while True do
    begin
      for K := 0 to High(FDocEnds) do
        if FDocEnds[K] > AIndex then
        begin
          EndIndex := FDocEnds[K];
          Break;
        end;
      if (EndIndex >= 0) or FStreamDone then
        Break;
      NextEvent;
    end;
    if EndIndex < 0 then
      Exit(False);
    Need := EndIndex + 1;
  end;
  Builder := TYamlJsonBuilder.Create;
  try
    AData := Builder.BuildSection(Copy(FLog, 0, Need), AIndex);
    Result := AData <> nil;
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

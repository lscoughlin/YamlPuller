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
  YamlPuller.Parser, YamlPuller.JSON, YamlPuller.Schema;

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
    FKeepLog: Boolean;
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
    procedure ParseWindow(const AEvent: TYamlEvent; out AData: TJSONData);
    procedure MoveCursorPast(const AEvent: TYamlEvent);
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
    /// true while the puller keeps a log of every event. The initial value is
    /// true. With false, Parse(event, data) accepts only the event that Next
    /// returned last, and the memory follows the size of one document. The
    /// property is set before the first call of Next.
    property KeepEventLog: Boolean read FKeepLog write FKeepLog;
  end;

  /// the source factory. Each method returns a ready puller.
  TYamlPullerFactory = class
  public
    class function FromFile(const AFile: THandle): TYamlPuller;
    class function FromStream(AStream: TStream): TYamlPuller;
    class function FromBytes(const ABytes: TBytes): TYamlPuller;
    class function FromString(const AText: UTF8String): TYamlPuller;
  end;

/// the member name of a scalar event that is a mapping key. A string key is
/// its text. A key of another core type is its canonical core-schema text.
/// This is the name that Parse gives to the member.
function YamlMemberName(const AEvent: TYamlEvent): UTF8String;

/// a short name for each event type
function EventTypeName(AType: TYamlEventType): string;

/// the library version
const
  YAML_PULLER_VERSION = '0.2.0';

implementation

function EventTypeName(AType: TYamlEventType): string;
begin
  Result := YamlEventTypeName[AType];
end;

function YamlMemberName(const AEvent: TYamlEvent): UTF8String;
var
  Resolver: TYamlSchemaResolver;
begin
  case AEvent.ScalarType of
    ystNull, ystBool, ystInt, ystFloat:
      begin
        Resolver := TYamlSchemaResolver.Create;
        try
          Result := Resolver.Canonical(AEvent.EventText, AEvent.ScalarType);
        finally
          Resolver.Free;
        end;
      end;
  else
    Result := AEvent.EventText;
  end;
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
  FKeepLog := True;
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
      if FKeepLog then
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
  if (not FKeepLog) and ((FIndex > 0) or (Length(FEvents) > 0)) then
    raise EYamlParserError.Create(
      'The event log is off. The puller already returned an event');
  Builder := TYamlJsonBuilder.Create;
  try
    All := BuildLog;
    Result := Builder.Build(All);
  finally
    Builder.Free;
    if not FKeepLog then
      SetLength(FLog, 0);
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
  if not FKeepLog then
  begin
    ParseWindow(AEvent, AData);
    Exit;
  end;
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
    AData.Free
  else
    MoveCursorPast(AEvent);
end;

function SameEvent(const A: TYamlEventEx; const B: TYamlEvent): Boolean;
begin
  Result := (A.EventType = B.EventType) and (A.Line = B.Line)
    and (A.Column = B.Column) and (A.NestLevel = B.NestLevel)
    and (A.EventText = B.EventText);
end;

procedure TYamlPuller.MoveCursorPast(const AEvent: TYamlEvent);
var
  EndIndex: Integer;
begin
  // the cursor moves only for the event that Next returned last, and only
  // for a collection. A scalar and an alias end at their own event.
  if (FIndex < 1) or (FIndex > Length(FEvents)) then
    Exit;
  if not SameEvent(FEvents[FIndex - 1], AEvent) then
    Exit;
  if (AEvent.EventType <> yetMappingStart)
    and (AEvent.EventType <> yetSequenceStart) then
    Exit;
  EndIndex := TYamlJsonBuilder.FindNodeEnd(FEvents, FIndex - 1);
  if EndIndex <= High(FEvents) then
    FIndex := EndIndex + 1;
end;

procedure TYamlPuller.ParseWindow(const AEvent: TYamlEvent;
  out AData: TJSONData);
var
  Index, Need, EndIndex, K: Integer;
  Builder: TYamlJsonBuilder;
begin
  AData := nil;
  case AEvent.EventType of
    yetStreamStart, yetStreamEnd, yetMappingEnd, yetSequenceEnd,
    yetDocumentEnd:
      Exit;
  end;
  // the events of the current document are in FEvents. The event must be
  // the event that Next returned last.
  if (FIndex < 1) or (FIndex > Length(FEvents))
    or (not SameEvent(FEvents[FIndex - 1], AEvent)) then
    raise EYamlParserError.Create(
      'The event log is off. The event is not the last event of the puller',
      AEvent.Line, AEvent.Column);
  Index := FIndex - 1;
  Need := Index + 1;
  if (AEvent.EventType = yetMappingStart)
    or (AEvent.EventType = yetSequenceStart) then
    Need := TYamlJsonBuilder.FindNodeEnd(FEvents, Index) + 1
  else if AEvent.EventType = yetDocumentStart then
  begin
    Need := Length(FEvents);
    for K := Index + 1 to High(FEvents) do
      if FEvents[K].EventType = yetDocumentEnd then
      begin
        Need := K + 1;
        Break;
      end;
  end;
  if Need > Length(FEvents) then
    Need := Length(FEvents);
  Builder := TYamlJsonBuilder.Create;
  try
    AData := Builder.BuildSection(Copy(FEvents, 0, Need), Index);
  finally
    Builder.Free;
  end;
  if AData <> nil then
    MoveCursorPast(AEvent);
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

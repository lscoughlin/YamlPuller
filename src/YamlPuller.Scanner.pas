{**
license: Apache-2.0
copyright: Copyright 2026 Liam Seamus Coughlin
---
Scanner driver: indentation and simple keys (plan story S03).
@br
The driver reads the physical lines and produces the token list. The family
units supply the scalar, block, flow, and comment functions.
The driver reads one document region at a time through TYamlLineReader. The
puller therefore reads only the lines of the regions that it requests.
}
unit YamlPuller.Scanner;

{$mode delphi}{$H+}

interface

uses
  SysUtils, YamlPuller.Errors, YamlPuller.Input, YamlPuller.Scanner.Core,
  YamlPuller.Scanner.Comments, YamlPuller.Scanner.Scalar,
  YamlPuller.Scanner.Block, YamlPuller.Scanner.Flow;

type
  /// the scanner. One instance scans one document source.
  TYamlScanner = class
  private
    FInput: TYamlInput;
  public
    constructor Create(AInput: TYamlInput);
    /// scan the whole source and return the token list
    function Scan: TArray<TYamlToken>;
  end;

function FindKeyColon(const ALine: UnicodeString): Integer;
function IsMappingBody(const ABody: UnicodeString): Boolean;
function IsExplicitKey(const ABody: UnicodeString): Boolean;
function IsFlowStart(const ABody: UnicodeString): Boolean;
function StartsWithDash(const ALine: UnicodeString): Boolean;

implementation

type
  TScanContext = record
    Lines: array of TYamlLine;
    Index: Integer;
    State: TYamlScanState;
  end;

procedure ScanBlockNode(var Ctx: TScanContext; AParentIndent: Integer); forward;
procedure ScanInlineNode(var Ctx: TScanContext; const AText: UnicodeString;
  ALine, AColumn: Integer); forward;
procedure ScanBlockMap(var Ctx: TScanContext; AIndent: Integer); forward;
procedure ScanBlockSeq(var Ctx: TScanContext; AIndent: Integer); forward;

{ helper functions }

function StartsWithDash(const ALine: UnicodeString): Boolean;
var
  S: UnicodeString;
begin
  S := Trim(ALine);
  Result := (S = '-') or ((Length(S) >= 2) and (S[1] = '-') and (S[2] = ' '));
end;

function IsMappingBody(const ABody: UnicodeString): Boolean;
begin
  if IsFlowStart(ABody) then
    Exit(False);
  Result := FindKeyColon(ABody) > 0;
end;

function IsExplicitKey(const ABody: UnicodeString): Boolean;
begin
  Result := (ABody = '?') or ((Length(ABody) >= 2) and (ABody[1] = '?')
    and (ABody[2] = ' '));
end;

function IsFlowStart(const ABody: UnicodeString): Boolean;
var
  S: UnicodeString;
begin
  S := Trim(ABody);
  Result := (Length(S) > 0) and ((S[1] = '{') or (S[1] = '['));
end;

function FindKeyColon(const ALine: UnicodeString): Integer;
var
  I: Integer;
  InSingle, InDouble: Boolean;
begin
  Result := 0;
  InSingle := False;
  InDouble := False;
  for I := 1 to Length(ALine) do
  begin
    if ALine[I] = '''' then
      InSingle := not InSingle
    else if ALine[I] = '"' then
      InDouble := not InDouble
    else if (ALine[I] = ':') and not InSingle and not InDouble then
      if (I = Length(ALine)) or (ALine[I + 1] = ' ') then
        Exit(I);
  end;
end;

procedure AddRegionLine(var Ctx: TScanContext; const AText: UnicodeString;
  ANumber: Integer);
var
  Clean: UnicodeString;
begin
  Clean := StripComment(AText);
  SetLength(Ctx.Lines, Length(Ctx.Lines) + 1);
  Ctx.Lines[High(Ctx.Lines)].Text := Clean;
  Ctx.Lines[High(Ctx.Lines)].Indent := IndentOf(Clean);
  Ctx.Lines[High(Ctx.Lines)].LineNo := ANumber;
end;

procedure LoadRegion(var Ctx: TScanContext; AReader: TYamlLineReader);
var
  S: UnicodeString;
  N: Integer;
begin
  // read the lines of one document region: the lines up to the next
  // document start marker. A marker that starts the region is included. A
  // later marker belongs to the next region, so the reader keeps it. A
  // document marker has no indentation: an indented "---" is content, not
  // a marker.
  SetLength(Ctx.Lines, 0);
  while AReader.NextLine(S, N) do
  begin
    if (IndentOf(S) = 0) and IsDocumentStart(S)
      and (Length(Ctx.Lines) > 0) then
    begin
      AReader.PushBack(S, N);
      Break;
    end;
    AddRegionLine(Ctx, S, N);
  end;
end;

procedure SkipBlank(var Ctx: TScanContext);
begin
  while (Ctx.Index <= High(Ctx.Lines)) and IsBlank(Ctx.Lines[Ctx.Index].Text) do
    Inc(Ctx.Index);
end;

function BodyOf(const ALine: UnicodeString): UnicodeString;
var
  Ind: Integer;
begin
  Ind := IndentOf(ALine);
  Result := Copy(ALine, Ind + 1, Length(ALine));
end;

/// the array index of the physical line with the number ALineNo
function LineIndexOf(const ALines: array of TYamlLine; ALineNo: Integer): Integer;
var
  I: Integer;
begin
  for I := 0 to High(ALines) do
    if ALines[I].LineNo = ALineNo then
      Exit(I);
  Result := High(ALines);
end;

{ block scalar }

procedure ScanBlockScalarNode(var Ctx: TScanContext; AIndicator: WideChar;
  const AHeader: UnicodeString; ALine: Integer);
var
  Text: UnicodeString;
  Last: Integer;
  Style: TYamlScalarStyle;
begin
  if (ALine < 0) or (ALine > High(Ctx.Lines)) then
  begin
    // the indicator has no content line in this region
    Ctx.Index := High(Ctx.Lines) + 1;
    Exit;
  end;
  ScanBlockScalar(AIndicator, AHeader, Ctx.Lines, ALine,
    Ctx.Lines[ALine].Indent, Text, Last);
  if AIndicator = '|' then
    Style := yssLiteral
  else
    Style := yssFolded;
  Ctx.State.Add(NewScalarToken(Text, Style, Ctx.Lines[ALine].LineNo, 1));
  Ctx.Index := Last + 1;
end;

{ flow collections }

procedure ScanFlowCollection(var Ctx: TScanContext; const AText: UnicodeString;
  ALine, AColumn: Integer);
var
  C: TYamlScanCursor;
  Ch, CloseCh: WideChar;
  Depth: Integer;
  Buf: UnicodeString;
  Entries: TArray<UnicodeString>;
  I, P: Integer;
  Entry: UnicodeString;
begin
  CursorInit(C, AText, ALine);
  Ch := CursorChar(C);
  if Ch = '[' then
  begin
    Ctx.State.AddSimple(ytkFlowSeqStart, '', ALine, AColumn);
    CloseCh := ']';
  end
  else
  begin
    Ctx.State.AddSimple(ytkFlowMapStart, '', ALine, AColumn);
    CloseCh := '}';
  end;
  CursorAdvance(C);
  Depth := 1;
  Buf := '';
  while (not CursorAtEnd(C)) and (Depth > 0) do
  begin
    Ch := CursorChar(C);
    if IsFlowIndicator(Ch) then
    begin
      case Ch of
        '[', '{': Inc(Depth);
        ']', '}': Dec(Depth);
      end;
      if Depth = 0 then
        Break;
    end;
    Buf := Buf + Ch;
    CursorAdvance(C);
  end;
  SplitFlowEntries(Buf, Entries);
  for I := 0 to High(Entries) do
  begin
    Entry := Trim(Entries[I]);
    if Entry = '' then
      Continue;
    if CloseCh = ']' then
    begin
      Ctx.State.AddSimple(ytkFlowEntry, '', ALine, AColumn);
      ScanInlineNode(Ctx, Entry, ALine, 1);
    end
    else
    begin
      P := FindKeyColon(Entry);
      if P > 0 then
      begin
        Ctx.State.AddSimple(ytkKey, '', ALine, 1);
        ScanInlineNode(Ctx, Trim(Copy(Entry, 1, P - 1)), ALine, 1);
        Ctx.State.AddSimple(ytkValue, '', ALine, 1);
        ScanInlineNode(Ctx, Trim(Copy(Entry, P + 1, Length(Entry))), ALine, 1);
      end
      else
      begin
        Ctx.State.AddSimple(ytkKey, '', ALine, 1);
        ScanInlineNode(Ctx, Entry, ALine, 1);
        Ctx.State.AddSimple(ytkValue, '', ALine, 1);
        Ctx.State.Add(NewScalarToken('', yssPlain, ALine, 1));
      end;
    end;
  end;
  if CloseCh = ']' then
    Ctx.State.AddSimple(ytkFlowSeqEnd, '', ALine, AColumn)
  else
    Ctx.State.AddSimple(ytkFlowMapEnd, '', ALine, AColumn);
end;

{ inline node: a scalar, an alias, a flow collection, or a block scalar }

procedure ScanInlineNode(var Ctx: TScanContext; const AText: UnicodeString;
  ALine, AColumn: Integer);
var
  C: TYamlScanCursor;
  Text, Name, Tag: UnicodeString;
  Col: Integer;
begin
  CursorInit(C, AText, ALine);
  C.Col := AColumn;
  CursorSkipSpaces(C);
  Col := AColumn + (C.Pos - 1);
  // properties
  if CursorChar(C) = '&' then
  begin
    ScanAnchor(C, Name);
    Ctx.State.AddSimple(ytkAnchor, Name, ALine, Col);
    CursorSkipSpaces(C);
  end;
  if CursorChar(C) = '!' then
  begin
    ScanTag(C, Tag);
    Ctx.State.AddSimple(ytkTag, Tag, ALine, Col);
    CursorSkipSpaces(C);
  end;
  if CursorAtEnd(C) then
    Exit;
  Col := AColumn + (C.Pos - 1);
  if CursorChar(C) = '*' then
  begin
    ScanAlias(C, Name);
    Ctx.State.AddSimple(ytkAlias, Name, ALine, Col);
    Exit;
  end;
  if (CursorChar(C) = '[') or (CursorChar(C) = '{') then
  begin
    ScanFlowCollection(Ctx, Copy(C.S, C.Pos, Length(C.S)), ALine, Col);
    Exit;
  end;
  if CursorChar(C) = '|' then
  begin
    ScanBlockScalarNode(Ctx, '|', Copy(C.S, C.Pos + 1, Length(C.S)),
      LineIndexOf(Ctx.Lines, ALine));
    Exit;
  end;
  if CursorChar(C) = '>' then
  begin
    ScanBlockScalarNode(Ctx, '>', Copy(C.S, C.Pos + 1, Length(C.S)),
      LineIndexOf(Ctx.Lines, ALine));
    Exit;
  end;
  if CursorChar(C) = '''' then
  begin
    ScanSingleQuoted(C, Text);
    Ctx.State.Add(NewScalarToken(Text, yssSingle, ALine, Col));
    Exit;
  end;
  if CursorChar(C) = '"' then
  begin
    ScanDoubleQuoted(C, Text);
    Ctx.State.Add(NewScalarToken(Text, yssDouble, ALine, Col));
    Exit;
  end;
  ScanPlain(C, False, Text);
  Ctx.State.Add(NewScalarToken(Text, yssPlain, ALine, Col));
end;

{ the value part of a mapping entry }

procedure ScanValueNode(var Ctx: TScanContext; const ARest: UnicodeString;
  AParentIndent, ALine: Integer);
begin
  if Trim(ARest) = '' then
  begin
    Inc(Ctx.Index);
    ScanBlockNode(Ctx, AParentIndent);
    Exit;
  end;
  ScanInlineNode(Ctx, ARest, ALine, 1);
  // a property alone on the line, with a nested block below
  if (Ctx.State.LastKind = ytkAnchor) or (Ctx.State.LastKind = ytkTag) then
  begin
    Inc(Ctx.Index);
    ScanBlockNode(Ctx, AParentIndent);
    Exit;
  end;
  Inc(Ctx.Index);
end;

{ block mapping }

procedure ScanBlockMap(var Ctx: TScanContext; AIndent: Integer);
var
  Line: TYamlLine;
  Body, Body2, Rest: UnicodeString;
  Ind, P, LineNo: Integer;
begin
  Ctx.State.AddSimple(ytkMapStart, '', Ctx.Lines[Ctx.Index].LineNo, AIndent + 1);
  while Ctx.Index <= High(Ctx.Lines) do
  begin
    SkipBlank(Ctx);
    if Ctx.Index > High(Ctx.Lines) then
      Break;
    Line := Ctx.Lines[Ctx.Index];
    Ind := Line.Indent;
    if (Ind <> AIndent) or StartsWithDash(Line.Text) then
      Break;
    Body := BodyOf(Line.Text);
    // an explicit key: "? key" on this line, ": value" below
    if (Body = '?') or ((Length(Body) >= 2) and (Body[1] = '?')
      and (Body[2] = ' ')) then
    begin
      LineNo := Line.LineNo;
      Ctx.State.AddSimple(ytkKey, '', LineNo, Ind + 1);
      ScanInlineNode(Ctx, Trim(Copy(Body, 2, Length(Body))), LineNo, Ind + 2);
      Inc(Ctx.Index);
      SkipBlank(Ctx);
      if Ctx.Index <= High(Ctx.Lines) then
      begin
        Body2 := BodyOf(Ctx.Lines[Ctx.Index].Text);
        if (Body2 = ':') or ((Length(Body2) >= 2) and (Body2[1] = ':')
          and (Body2[2] = ' ')) then
        begin
          LineNo := Ctx.Lines[Ctx.Index].LineNo;
          Ctx.State.AddSimple(ytkValue, '', LineNo, Ind + 1);
          Rest := Trim(Copy(Body2, 2, Length(Body2)));
          if Rest = '' then
          begin
            Inc(Ctx.Index);
            ScanBlockNode(Ctx, AIndent);
          end
          else
            ScanValueNode(Ctx, Rest, AIndent, LineNo);
        end;
      end;
      Continue;
    end;
    P := FindKeyColon(Body);
    if P <= 0 then
      Break;
    LineNo := Line.LineNo;
    Ctx.State.AddSimple(ytkKey, '', LineNo, Ind + 1);
    ScanInlineNode(Ctx, Copy(Body, 1, P - 1), LineNo, Ind + 1);
    // a nested block in a key: the key node sits on the lines below
    if Ctx.Index > High(Ctx.Lines) then
      Break;
    Ctx.State.AddSimple(ytkValue, '', LineNo, Ind + 1);
    Rest := Copy(Body, P + 1, Length(Body));
    while (Length(Rest) > 0) and (Rest[1] = ' ') do
      Delete(Rest, 1, 1);
    if Rest = '' then
    begin
      Inc(Ctx.Index);
      ScanBlockNode(Ctx, AIndent);
    end
    else
      ScanValueNode(Ctx, Rest, AIndent, LineNo);
  end;
  if Ctx.Index > 0 then
    Ctx.State.AddSimple(ytkMapEnd, '', Ctx.Lines[Ctx.Index - 1].LineNo, AIndent + 1)
  else
    Ctx.State.AddSimple(ytkMapEnd, '', 1, AIndent + 1);
end;

{ inline mapping after a sequence dash: "- key: value" }

procedure ScanDashMap(var Ctx: TScanContext; AIndent: Integer;
  const ARest: UnicodeString);
var
  Body, Rest: UnicodeString;
  P, LineNo, MapIndent: Integer;
begin
  MapIndent := AIndent + 2;
  LineNo := Ctx.Lines[Ctx.Index].LineNo;
  Ctx.State.AddSimple(ytkMapStart, '', LineNo, MapIndent + 1);
  Body := ARest;
  P := FindKeyColon(Body);
  if P > 0 then
  begin
    Ctx.State.AddSimple(ytkKey, '', LineNo, MapIndent + 1);
    ScanInlineNode(Ctx, Copy(Body, 1, P - 1), LineNo, MapIndent + 1);
    Ctx.State.AddSimple(ytkValue, '', LineNo, MapIndent + 1);
    Rest := Copy(Body, P + 1, Length(Body));
    while (Length(Rest) > 0) and (Rest[1] = ' ') do
      Delete(Rest, 1, 1);
    if Rest = '' then
    begin
      Inc(Ctx.Index);
      ScanBlockNode(Ctx, MapIndent);
    end
    else
      ScanValueNode(Ctx, Rest, MapIndent, LineNo);
  end;
  // continue the mapping on the following lines at the same indent
  while Ctx.Index <= High(Ctx.Lines) do
  begin
    SkipBlank(Ctx);
    if Ctx.Index > High(Ctx.Lines) then
      Break;
    if Ctx.Lines[Ctx.Index].Indent <> MapIndent then
      Break;
    Body := BodyOf(Ctx.Lines[Ctx.Index].Text);
    P := FindKeyColon(Body);
    if P <= 0 then
      Break;
    LineNo := Ctx.Lines[Ctx.Index].LineNo;
    Ctx.State.AddSimple(ytkKey, '', LineNo, MapIndent + 1);
    ScanInlineNode(Ctx, Copy(Body, 1, P - 1), LineNo, MapIndent + 1);
    Ctx.State.AddSimple(ytkValue, '', LineNo, MapIndent + 1);
    Rest := Copy(Body, P + 1, Length(Body));
    while (Length(Rest) > 0) and (Rest[1] = ' ') do
      Delete(Rest, 1, 1);
    if Rest = '' then
    begin
      Inc(Ctx.Index);
      ScanBlockNode(Ctx, MapIndent);
    end
    else
      ScanValueNode(Ctx, Rest, MapIndent, LineNo);
  end;
  Ctx.State.AddSimple(ytkMapEnd, '', LineNo, MapIndent + 1);
end;

{ block sequence }

procedure ScanBlockSeq(var Ctx: TScanContext; AIndent: Integer);
var
  Line: TYamlLine;
  Rest: UnicodeString;
  Ind, LineNo: Integer;
begin
  Ctx.State.AddSimple(ytkSeqStart, '', Ctx.Lines[Ctx.Index].LineNo, AIndent + 1);
  while Ctx.Index <= High(Ctx.Lines) do
  begin
    SkipBlank(Ctx);
    if Ctx.Index > High(Ctx.Lines) then
      Break;
    Line := Ctx.Lines[Ctx.Index];
    Ind := Line.Indent;
    if (Ind <> AIndent) or not StartsWithDash(Line.Text) then
      Break;
    if IsDocumentStart(Line.Text) or IsDocumentEnd(Line.Text) then
      Break;
    LineNo := Line.LineNo;
    Ctx.State.AddSimple(ytkEntry, '', LineNo, Ind + 1);
    Rest := Copy(BodyOf(Line.Text), 2, Length(BodyOf(Line.Text)));
    while (Length(Rest) > 0) and (Rest[1] = ' ') do
      Delete(Rest, 1, 1);
    if Rest = '' then
    begin
      Inc(Ctx.Index);
      ScanBlockNode(Ctx, AIndent);
      Continue;
    end;
    if IsMappingBody(Rest) then
      ScanDashMap(Ctx, AIndent, Rest)
    else
      ScanValueNode(Ctx, Rest, AIndent, LineNo);
  end;
  if Ctx.Index > 0 then
    Ctx.State.AddSimple(ytkSeqEnd, '', Ctx.Lines[Ctx.Index - 1].LineNo, AIndent + 1)
  else
    Ctx.State.AddSimple(ytkSeqEnd, '', 1, AIndent + 1);
end;

{ block node entry }

procedure ScanBlockNode(var Ctx: TScanContext; AParentIndent: Integer);
var
  Line: TYamlLine;
  Body: UnicodeString;
  Ind: Integer;
begin
  SkipBlank(Ctx);
  if Ctx.Index > High(Ctx.Lines) then
    Exit;
  Line := Ctx.Lines[Ctx.Index];
  if IsDocumentStart(Line.Text) or IsDocumentEnd(Line.Text) then
    Exit;
  Ind := Line.Indent;
  if Ind <= AParentIndent then
    Exit;
  Body := BodyOf(Line.Text);
  if StartsWithDash(Line.Text) then
    ScanBlockSeq(Ctx, Ind)
  else if IsMappingBody(Body) or IsExplicitKey(Body) then
    ScanBlockMap(Ctx, Ind)
  else
  begin
    ScanInlineNode(Ctx, Body, Line.LineNo, Ind + 1);
    Inc(Ctx.Index);
  end;
end;

{ document }

procedure ScanDocument(var Ctx: TScanContext);
var
  Line: TYamlLine;
  Body: UnicodeString;
begin
  SkipBlank(Ctx);
  if Ctx.Index > High(Ctx.Lines) then
    Exit;
  Line := Ctx.Lines[Ctx.Index];
  Ctx.State.AddSimple(ytkDocumentStart, '', Line.LineNo, 1);
  if IsDocumentStart(Line.Text) then
  begin
    Body := Trim(Copy(Line.Text, 4, Length(Line.Text)));
    if Body = '' then
    begin
      Inc(Ctx.Index);
      ScanBlockNode(Ctx, -1);
    end
    else
    begin
      ScanInlineNode(Ctx, Body, Line.LineNo, 4);
      Inc(Ctx.Index);
    end;
  end
  else
    ScanBlockNode(Ctx, -1);
end;

{ TYamlScanner }

constructor TYamlScanner.Create(AInput: TYamlInput);
begin
  inherited Create;
  FInput := AInput;
end;

function TYamlScanner.Scan: TArray<TYamlToken>;
var
  Ctx: TScanContext;
  State: TYamlScanState;
  Reader: TYamlLineReader;
begin
  State := TYamlScanState.Create;
  Ctx.State := State;
  Ctx.Index := 0;
  SetLength(Ctx.Lines, 0);
  Reader := TYamlLineReader.Create(FInput);
  try
    FInput.Reset;
    while True do
    begin
      // read the lines of one document region, then scan them. The next
      // region is read only when the caller asks for its tokens.
      LoadRegion(Ctx, Reader);
      if Length(Ctx.Lines) = 0 then
        Break;
      Ctx.Index := 0;
      while Ctx.Index <= High(Ctx.Lines) do
      begin
        SkipBlank(Ctx);
        if Ctx.Index > High(Ctx.Lines) then
          Break;
        // a marker at column 0 that is not the first line of the region
        // starts the next region. The reader kept it for the next call.
        if (IndentOf(Ctx.Lines[Ctx.Index].Text) = 0)
          and IsDocumentStart(Ctx.Lines[Ctx.Index].Text)
          and (Ctx.Index > 0) then
          Break;
        if IsDirective(Ctx.Lines[Ctx.Index].Text) then
        begin
          State.AddSimple(ytkDirective, Trim(Ctx.Lines[Ctx.Index].Text),
            Ctx.Lines[Ctx.Index].LineNo, 1);
          Inc(Ctx.Index);
          Continue;
        end;
        ScanDocument(Ctx);
        SkipBlank(Ctx);
        if (Ctx.Index <= High(Ctx.Lines))
          and IsDocumentEnd(Ctx.Lines[Ctx.Index].Text) then
          Inc(Ctx.Index);
      end;
    end;
  finally
    Reader.Free;
  end;
  Result := State.Tokens;
end;

end.

{**
license: Apache-2.0
copyright: Copyright 2026 Liam Seamus Coughlin
---
Scanner core: token model, character cursor, and shared scanner state.
@br
This unit holds the token record, the token kind enumeration, the
  character cursor, and the state record. It depends on no other scanner
  unit, so the scanner family units do not form a cycle.
}
unit YamlPuller.Scanner.Core;

{$mode delphi}{$H+}

interface

uses
  SysUtils;

type
  /// one token kind
  TYamlTokenKind = (
    ytkDocumentStart,
    ytkDocumentEnd,
    ytkDirective,
    ytkMapStart,
    ytkMapEnd,
    ytkSeqStart,
    ytkSeqEnd,
    ytkEntry,
    ytkKey,
    ytkValue,
    ytkScalar,
    ytkAnchor,
    ytkAlias,
    ytkTag,
    ytkFlowSeqStart,
    ytkFlowSeqEnd,
    ytkFlowMapStart,
    ytkFlowMapEnd,
    ytkFlowEntry);

  /// the style of a scalar token
  TYamlScalarStyle = (yssPlain, yssSingle, yssDouble, yssLiteral, yssFolded);

  /// one scanner token
  TYamlToken = record
    Kind: TYamlTokenKind;
    Text: UnicodeString;
    ScalarStyle: TYamlScalarStyle;
    Line: Integer;
    Column: Integer;
  end;

  /// one physical input line
  TYamlLine = record
    Indent: Integer;
    Text: UnicodeString;
    LineNo: Integer;
    HasDash: Boolean;
  end;

  /// a character cursor over one string
  TYamlScanCursor = record
    S: UnicodeString;
    Pos: Integer;
    Line: Integer;
    Col: Integer;
  end;

  /// the scanner state. The driver fills the token list. `Parse` reads the
  /// token list.
  TYamlScanState = class
  public
    Tokens: array of TYamlToken;
    procedure Add(const AToken: TYamlToken);
    procedure AddSimple(AKind: TYamlTokenKind; const AText: UnicodeString;
      ALine, AColumn: Integer);
    function LastKind: TYamlTokenKind;
    function Empty: Boolean;
  end;

const
  YamlTokenKindName: array[TYamlTokenKind] of string = (
    'document-start', 'document-end', 'directive',
    'map-start', 'map-end', 'seq-start', 'seq-end',
    'entry', 'key', 'value', 'scalar', 'anchor', 'alias', 'tag',
    'flow-seq-start', 'flow-seq-end', 'flow-map-start', 'flow-map-end',
    'flow-entry');

function NewToken(AKind: TYamlTokenKind; const AText: UnicodeString;
  ALine, AColumn: Integer): TYamlToken;
function NewScalarToken(const AText: UnicodeString; AStyle: TYamlScalarStyle;
  ALine, AColumn: Integer): TYamlToken;

procedure CursorInit(var C: TYamlScanCursor; const AText: UnicodeString;
  ALine: Integer);
function CursorChar(const C: TYamlScanCursor): WideChar;
function CursorPeek(const C: TYamlScanCursor; AOffset: Integer): WideChar;
function CursorAtEnd(const C: TYamlScanCursor): Boolean;
procedure CursorAdvance(var C: TYamlScanCursor);
procedure CursorAdvanceN(var C: TYamlScanCursor; N: Integer);
procedure CursorSkipSpaces(var C: TYamlScanCursor);
function IsFlowIndicator(Ch: WideChar): Boolean;
function IsBlankOrComment(const S: UnicodeString): Boolean;

implementation

function NewToken(AKind: TYamlTokenKind; const AText: UnicodeString;
  ALine, AColumn: Integer): TYamlToken;
begin
  FillChar(Result, SizeOf(Result), 0);
  Result.Kind := AKind;
  Result.Text := AText;
  Result.ScalarStyle := yssPlain;
  Result.Line := ALine;
  Result.Column := AColumn;
end;

function NewScalarToken(const AText: UnicodeString; AStyle: TYamlScalarStyle;
  ALine, AColumn: Integer): TYamlToken;
begin
  Result := NewToken(ytkScalar, AText, ALine, AColumn);
  Result.ScalarStyle := AStyle;
end;

procedure TYamlScanState.Add(const AToken: TYamlToken);
begin
  SetLength(Tokens, Length(Tokens) + 1);
  Tokens[High(Tokens)] := AToken;
end;

procedure TYamlScanState.AddSimple(AKind: TYamlTokenKind;
  const AText: UnicodeString; ALine, AColumn: Integer);
begin
  Add(NewToken(AKind, AText, ALine, AColumn));
end;

function TYamlScanState.LastKind: TYamlTokenKind;
begin
  Result := Tokens[High(Tokens)].Kind;
end;

function TYamlScanState.Empty: Boolean;
begin
  Result := Length(Tokens) = 0;
end;

procedure CursorInit(var C: TYamlScanCursor; const AText: UnicodeString;
  ALine: Integer);
begin
  C.S := AText;
  C.Pos := 1;
  C.Line := ALine;
  C.Col := 1;
end;

function CursorChar(const C: TYamlScanCursor): WideChar;
begin
  if (C.Pos >= 1) and (C.Pos <= Length(C.S)) then
    Result := C.S[C.Pos]
  else
    Result := #0;
end;

function CursorPeek(const C: TYamlScanCursor; AOffset: Integer): WideChar;
var
  P: Integer;
begin
  P := C.Pos + AOffset;
  if (P >= 1) and (P <= Length(C.S)) then
    Result := C.S[P]
  else
    Result := #0;
end;

function CursorAtEnd(const C: TYamlScanCursor): Boolean;
begin
  Result := C.Pos > Length(C.S);
end;

procedure CursorAdvance(var C: TYamlScanCursor);
begin
  if not CursorAtEnd(C) then
  begin
    Inc(C.Pos);
    Inc(C.Col);
  end;
end;

procedure CursorAdvanceN(var C: TYamlScanCursor; N: Integer);
var
  I: Integer;
begin
  for I := 1 to N do
    CursorAdvance(C);
end;

procedure CursorSkipSpaces(var C: TYamlScanCursor);
begin
  while (not CursorAtEnd(C)) and (CursorChar(C) = ' ') do
    CursorAdvance(C);
end;

function IsFlowIndicator(Ch: WideChar): Boolean;
begin
  Result := (Ch = ',') or (Ch = '[') or (Ch = ']') or (Ch = '{') or (Ch = '}');
end;

function IsBlankOrComment(const S: UnicodeString): Boolean;
var
  I: Integer;
begin
  I := 1;
  while (I <= Length(S)) and (S[I] = ' ') do
    Inc(I);
  Result := (I > Length(S)) or (S[I] = '#');
end;

end.

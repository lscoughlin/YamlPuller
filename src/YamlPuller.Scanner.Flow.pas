{**
license: Apache-2.0
copyright: Copyright 2026 Liam Seamus Coughlin
---
Scanner: flow collections and properties (plan story S07).
@br
The property scanners for a tag, an anchor, and an alias. The flow split
  reads the top-level entries of a flow collection.
}
unit YamlPuller.Scanner.Flow;

{$mode delphi}{$H+}

interface

uses
  SysUtils, YamlPuller.Scanner.Core;

/// read a tag from C. A "!" or a "!<...>" form. The handle is the part before
/// the suffix. The result is the tag text.
function ScanTag(var C: TYamlScanCursor; out ATag: UnicodeString): Boolean;

/// read an anchor name from C, after the "&"
function ScanAnchor(var C: TYamlScanCursor; out AName: UnicodeString): Boolean;

/// read an alias name from C, after the "*"
function ScanAlias(var C: TYamlScanCursor; out AName: UnicodeString): Boolean;

/// true when the character at AIndex opens a quoted scalar. A quote opens a
/// scalar only at the start of the text, or after a space, a tab, a flow
/// indicator, or a colon. A quote inside a plain scalar is a normal character.
function IsQuoteStart(const AText: UnicodeString; AIndex: Integer): Boolean;

/// the index of the closing quote of the quoted scalar that opens at AIndex.
/// A double-quoted scalar skips a backslash escape. A single-quoted scalar
/// reads two quotes as one. The result is Length(AText) when the scalar is
/// not closed.
function QuotedEnd(const AText: UnicodeString; AIndex: Integer): Integer;

/// the position of the colon that ends the key of a flow mapping entry, or 0.
/// A colon follows a quoted key without a space. For a plain key, a space or
/// the end of the entry follows the colon.
function FindFlowKeyColon(const AEntry: UnicodeString): Integer;

/// split a flow collection body on the top-level commas. The nested brackets
/// and the quoted text do not count.
procedure SplitFlowEntries(const ABody: UnicodeString;
  out AEntries: TArray<UnicodeString>);

implementation

function IsQuoteStart(const AText: UnicodeString; AIndex: Integer): Boolean;
begin
  Result := (AIndex >= 1) and (AIndex <= Length(AText))
    and ((AText[AIndex] = '"') or (AText[AIndex] = ''''));
  if Result and (AIndex > 1) then
    Result := AText[AIndex - 1] in [' ', #9, '[', '{', ',', ':'];
end;

function QuotedEnd(const AText: UnicodeString; AIndex: Integer): Integer;
var
  Q: WideChar;
  I: Integer;
begin
  Q := AText[AIndex];
  I := AIndex + 1;
  while I <= Length(AText) do
  begin
    if (Q = '"') and (AText[I] = '\') then
      Inc(I)
    else if AText[I] = Q then
    begin
      if (Q = '''') and (I < Length(AText)) and (AText[I + 1] = '''') then
        Inc(I)
      else
        Exit(I);
    end;
    Inc(I);
  end;
  Result := Length(AText);
end;

function FindFlowKeyColon(const AEntry: UnicodeString): Integer;
var
  I, LastQuoteEnd: Integer;
begin
  Result := 0;
  LastQuoteEnd := 0;
  I := 1;
  while I <= Length(AEntry) do
  begin
    if IsQuoteStart(AEntry, I) then
    begin
      I := QuotedEnd(AEntry, I);
      LastQuoteEnd := I;
    end
    else if AEntry[I] = ':' then
    begin
      if (I = Length(AEntry)) or (AEntry[I + 1] = ' ') then
        Exit(I);
      // a quoted key needs no space after the colon
      if (LastQuoteEnd > 0) and (Trim(Copy(AEntry, LastQuoteEnd + 1,
        I - LastQuoteEnd - 1)) = '') then
        Exit(I);
    end;
    Inc(I);
  end;
end;

function IsNameChar(Ch: WideChar): Boolean;
begin
  Result := (Ch <> #0) and (Ch <> ' ') and (Ch <> #9)
    and (Ch <> ',') and (Ch <> '[') and (Ch <> ']')
    and (Ch <> '{') and (Ch <> '}') and (Ch <> ':')
    and (Ch <> '#');
end;

function ScanTag(var C: TYamlScanCursor; out ATag: UnicodeString): Boolean;
var
  Buf: UnicodeString;
begin
  ATag := '';
  if CursorChar(C) <> '!' then
    Exit(False);
  Buf := '!';
  CursorAdvance(C);
  if CursorChar(C) = '<' then
  begin
    CursorAdvance(C);
    while (not CursorAtEnd(C)) and (CursorChar(C) <> '>') do
    begin
      Buf := Buf + CursorChar(C);
      CursorAdvance(C);
    end;
    if CursorChar(C) = '>' then
    begin
      Buf := Buf + '>';
      CursorAdvance(C);
    end;
  end
  else
  begin
    if CursorChar(C) = '!' then
    begin
      Buf := Buf + '!';
      CursorAdvance(C);
    end;
    while (not CursorAtEnd(C)) and IsNameChar(CursorChar(C)) do
    begin
      Buf := Buf + CursorChar(C);
      CursorAdvance(C);
    end;
  end;
  ATag := Buf;
  Result := True;
end;

function ScanAnchor(var C: TYamlScanCursor; out AName: UnicodeString): Boolean;
var
  Buf: UnicodeString;
begin
  AName := '';
  if CursorChar(C) <> '&' then
    Exit(False);
  CursorAdvance(C);
  while (not CursorAtEnd(C)) and IsNameChar(CursorChar(C)) do
  begin
    Buf := Buf + CursorChar(C);
    CursorAdvance(C);
  end;
  AName := Buf;
  Result := True;
end;

function ScanAlias(var C: TYamlScanCursor; out AName: UnicodeString): Boolean;
var
  Buf: UnicodeString;
begin
  AName := '';
  if CursorChar(C) <> '*' then
    Exit(False);
  CursorAdvance(C);
  while (not CursorAtEnd(C)) and IsNameChar(CursorChar(C)) do
  begin
    Buf := Buf + CursorChar(C);
    CursorAdvance(C);
  end;
  AName := Buf;
  Result := True;
end;

procedure SplitFlowEntries(const ABody: UnicodeString;
  out AEntries: TArray<UnicodeString>);
var
  I, Depth, Start: Integer;
  Ch: WideChar;
begin
  SetLength(AEntries, 0);
  Depth := 0;
  Start := 1;
  I := 1;
  while I <= Length(ABody) + 1 do
  begin
    if I <= Length(ABody) then
      Ch := ABody[I]
    else
      Ch := ',';
    if (I <= Length(ABody)) and IsQuoteStart(ABody, I) then
    begin
      I := QuotedEnd(ABody, I) + 1;
      Continue;
    end;
    case Ch of
      '[', '{': Inc(Depth);
      ']', '}': Dec(Depth);
      ',':
        if Depth = 0 then
        begin
          SetLength(AEntries, Length(AEntries) + 1);
          AEntries[High(AEntries)] := Trim(Copy(ABody, Start, I - Start));
          Start := I + 1;
        end;
    end;
    Inc(I);
  end;
end;

end.

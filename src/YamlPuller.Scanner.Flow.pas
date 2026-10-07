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

/// split a flow collection body on the top-level commas. The nested brackets
/// and the quoted text do not count.
procedure SplitFlowEntries(const ABody: UnicodeString;
  out AEntries: TArray<UnicodeString>);

implementation

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
  InSingle, InDouble: Boolean;
  Ch: WideChar;
begin
  SetLength(AEntries, 0);
  Depth := 0;
  Start := 1;
  InSingle := False;
  InDouble := False;
  for I := 1 to Length(ABody) + 1 do
  begin
    if I <= Length(ABody) then
      Ch := ABody[I]
    else
      Ch := ',';
    if InSingle then
    begin
      if Ch = '''' then
        InSingle := False;
      Continue;
    end;
    if InDouble then
    begin
      if Ch = '"' then
        InDouble := False;
      Continue;
    end;
    case Ch of
      '''': InSingle := True;
      '"': InDouble := True;
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
  end;
end;

end.

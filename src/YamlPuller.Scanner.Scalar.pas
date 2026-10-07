{**
license: Apache-2.0
copyright: Copyright 2026 Liam Seamus Coughlin
---
Scanner: plain and quoted scalars (plan story S05).
@br
The functions read one scalar from a cursor. A plain scalar stops at a
  comment, at the end of the text, and at a flow indicator in a flow
  context. The quoted forms decode the escape sequences.
}
unit YamlPuller.Scanner.Scalar;

{$mode delphi}{$H+}

interface

uses
  SysUtils, YamlPuller.Scanner.Core;

type
  TYamlScalarState = (yssStart, yssBody, yssQuote, yssEnd);

/// read a plain scalar from C. Stop at a comment, at end of text, or at a
/// flow indicator when AInFlow is true.
procedure ScanPlain(var C: TYamlScanCursor; AInFlow: Boolean;
  out AText: UnicodeString);

/// read a single-quoted scalar. A doubled quote is one quote character.
procedure ScanSingleQuoted(var C: TYamlScanCursor; out AText: UnicodeString);

/// read a double-quoted scalar. The function decodes the escape sequences.
procedure ScanDoubleQuoted(var C: TYamlScanCursor; out AText: UnicodeString);

implementation

function HexValue(Ch: WideChar): Integer;
begin
  case Ch of
    '0'..'9': Result := Ord(Ch) - Ord('0');
    'a'..'f': Result := Ord(Ch) - Ord('a') + 10;
    'A'..'F': Result := Ord(Ch) - Ord('A') + 10;
  else
    Result := -1;
  end;
end;

procedure ScanPlain(var C: TYamlScanCursor; AInFlow: Boolean;
  out AText: UnicodeString);
var
  Buf: UnicodeString;
  Ch: WideChar;
  N: Integer;
  Pending: UnicodeString;
begin
  Buf := '';
  Pending := '';
  while not CursorAtEnd(C) do
  begin
    Ch := CursorChar(C);
    if Ch = #9 then
    begin
      Pending := Pending + ' ';
      CursorAdvance(C);
      Continue;
    end;
    if Ch = ' ' then
    begin
      Pending := Pending + ' ';
      CursorAdvance(C);
      Continue;
    end;
    if Ch = '#' then
    begin
      if (Pending <> '') then
      begin
        // a comment needs a preceding space
        Break;
      end;
      Break;
    end;
    if AInFlow and IsFlowIndicator(Ch) then
      Break;
    if (Ch = ':') and not AInFlow then
    begin
      // a colon followed by space or end closes a plain scalar in a block
      if (CursorPeek(C, 1) = #0) or (CursorPeek(C, 1) = ' ')
        or (CursorPeek(C, 1) = #9) then
        Break;
    end;
    Buf := Buf + Pending + Ch;
    Pending := '';
    CursorAdvance(C);
  end;
  // a trailing space before a stop character is not part of the scalar
  N := Length(Buf);
  while (N > 0) and (Buf[N] = ' ') do
    Dec(N);
  AText := Copy(Buf, 1, N);
end;

procedure ScanSingleQuoted(var C: TYamlScanCursor; out AText: UnicodeString);
var
  Buf: UnicodeString;
  Ch: WideChar;
begin
  Buf := '';
  if CursorChar(C) = '''' then
    CursorAdvance(C);
  while not CursorAtEnd(C) do
  begin
    Ch := CursorChar(C);
    if Ch = '''' then
    begin
      CursorAdvance(C);
      if CursorChar(C) = '''' then
      begin
        Buf := Buf + '''';
        CursorAdvance(C);
        Continue;
      end;
      Break;
    end;
    Buf := Buf + Ch;
    CursorAdvance(C);
  end;
  AText := Buf;
end;

procedure ScanDoubleQuoted(var C: TYamlScanCursor; out AText: UnicodeString);
var
  Buf: UnicodeString;
  Ch: WideChar;
  Code, I, N: Integer;
begin
  Buf := '';
  if CursorChar(C) = '"' then
    CursorAdvance(C);
  while not CursorAtEnd(C) do
  begin
    Ch := CursorChar(C);
    if Ch = '"' then
    begin
      CursorAdvance(C);
      Break;
    end;
    if Ch = '\' then
    begin
      CursorAdvance(C);
      Ch := CursorChar(C);
      case Ch of
        '0': Buf := Buf + #0;
        'a': Buf := Buf + #7;
        'b': Buf := Buf + #8;
        't', #9: Buf := Buf + #9;
        'n': Buf := Buf + #10;
        'v': Buf := Buf + #11;
        'f': Buf := Buf + #12;
        'r': Buf := Buf + #13;
        'e': Buf := Buf + #27;
        ' ': Buf := Buf + ' ';
        '"': Buf := Buf + '"';
        '/': Buf := Buf + '/';
        '\': Buf := Buf + '\';
        'N': Buf := Buf + #$85;
        '_': Buf := Buf + #$A0;
        'L': Buf := Buf + #$2028;
        'P': Buf := Buf + #$2029;
        'x', 'u', 'U':
          begin
            if Ch = 'x' then N := 2
            else if Ch = 'u' then N := 4
            else N := 8;
            Code := 0;
            for I := 1 to N do
            begin
              CursorAdvance(C);
              if HexValue(CursorChar(C)) < 0 then
                Break;
              Code := Code * 16 + HexValue(CursorChar(C));
            end;
            if Code <= $FFFF then
              Buf := Buf + WideChar(Code)
            else
            begin
              Code := Code - $10000;
              Buf := Buf + WideChar($D800 or (Code shr 10));
              Buf := Buf + WideChar($DC00 or (Code and $3FF));
            end;
          end;
      else
        Buf := Buf + Ch;
      end;
      CursorAdvance(C);
      Continue;
    end;
    Buf := Buf + Ch;
    CursorAdvance(C);
  end;
  AText := Buf;
end;

end.

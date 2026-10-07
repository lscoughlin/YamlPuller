{**
license: Apache-2.0
copyright: Copyright 2026 Liam Seamus Coughlin
---
Scanner: block scalars (plan story S06).
@br
The literal style and the folded style, with the three chomping modes and
  an explicit indentation indicator.
}
unit YamlPuller.Scanner.Block;

{$mode delphi}{$H+}

interface

uses
  SysUtils, YamlPuller.Scanner.Core;

/// read a block scalar that starts at line AStartLine. AParentIndent is the
/// indentation of the parent context. AIndicator is "|" or ">". AHeader is
/// the text between the indicator and the end of the header line.
///
/// ALines holds the physical lines. The first content line is AStartLine + 1.
/// The function returns the text and the index of the last consumed line.
procedure ScanBlockScalar(const AIndicator: WideChar;
  const AHeader: UnicodeString; const ALines: array of TYamlLine;
  AStartLine, AParentIndent: Integer;
  out AText: UnicodeString; out ALastLine: Integer);

implementation

function LeadingSpaces(const S: UnicodeString): Integer;
var
  I: Integer;
begin
  Result := 0;
  for I := 1 to Length(S) do
    if S[I] = ' ' then
      Inc(Result)
    else
      Break;
end;

function IsBlankLine(const S: UnicodeString): Boolean;
var
  I: Integer;
begin
  I := 1;
  while (I <= Length(S)) and (S[I] = ' ') do
    Inc(I);
  Result := I > Length(S);
end;

procedure ScanBlockScalar(const AIndicator: WideChar;
  const AHeader: UnicodeString; const ALines: array of TYamlLine;
  AStartLine, AParentIndent: Integer;
  out AText: UnicodeString; out ALastLine: Integer);
var
  Chomp: Char;
  Explicit, I, J, L, MinIndent, FirstContent: Integer;
  Raw: array of UnicodeString;
  Body: UnicodeString;
  S: UnicodeString;
begin
  Chomp := #0;
  Explicit := 0;
  for I := 1 to Length(AHeader) do
    if (AHeader[I] = '-') or (AHeader[I] = '+') then
      Chomp := AHeader[I]
    else if (AHeader[I] >= '1') and (AHeader[I] <= '9') then
      Explicit := Ord(AHeader[I]) - Ord('0');

  // collect content lines: a non-empty line with an indent greater than the
  // parent indent, or a blank line between two such lines.
  SetLength(Raw, 0);
  FirstContent := -1;
  I := AStartLine + 1;
  while I <= High(ALines) do
  begin
    S := ALines[I].Text;
    if IsBlankLine(S) then
    begin
      SetLength(Raw, Length(Raw) + 1);
      Raw[High(Raw)] := '';
      Inc(I);
      Continue;
    end;
    L := LeadingSpaces(S);
    if L <= AParentIndent then
      Break;
    if FirstContent < 0 then
      FirstContent := Length(Raw);
    SetLength(Raw, Length(Raw) + 1);
    Raw[High(Raw)] := S;
    Inc(I);
  end;
  ALastLine := I - 1;

  if FirstContent < 0 then
  begin
    AText := '';
    Exit;
  end;
  // trim trailing blank lines that follow the last content line
  while (Length(Raw) > FirstContent) and (Raw[High(Raw)] = '') do
    SetLength(Raw, Length(Raw) - 1);

  if Explicit > 0 then
    MinIndent := AParentIndent + Explicit
  else
    MinIndent := LeadingSpaces(Raw[FirstContent]);

  for J := 0 to High(Raw) do
    if Raw[J] <> '' then
      Raw[J] := Copy(Raw[J], MinIndent + 1, Length(Raw[J]) - MinIndent);

  Body := '';
  if AIndicator = '|' then
  begin
    for J := 0 to High(Raw) do
      Body := Body + Raw[J] + #10;
  end
  else
  begin
    for J := 0 to High(Raw) do
    begin
      if J = 0 then
        Body := Raw[J]
      else if (Raw[J] = '') or (Raw[J - 1] = '') then
        Body := Body + #10 + Raw[J]
      else if (Raw[J] <> '') and (LeadingSpaces(Raw[J]) > 0) then
        Body := Body + #10 + Raw[J]
      else
        Body := Body + ' ' + Raw[J];
    end;
    Body := Body + #10;
  end;

  case Chomp of
    '-':
      while (Length(Body) > 0) and (Body[Length(Body)] = #10) do
        Delete(Body, Length(Body), 1);
    '+':
      ; // keep every line break
  else
    while (Length(Body) > 1) and (Body[Length(Body)] = #10)
      and (Body[Length(Body) - 1] = #10) do
      Delete(Body, Length(Body), 1);
  end;

  AText := Body;
end;

end.

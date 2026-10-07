{**
license: Apache-2.0
copyright: Copyright 2026 Liam Seamus Coughlin
---
Scanner: comments, whitespace, directives (plan story S04).
@br
The comment strip, the blank-line test, the document marker test, and the
  directive parse.
}
unit YamlPuller.Scanner.Comments;

{$mode delphi}{$H+}

interface

uses
  SysUtils, YamlPuller.Scanner.Core;

/// remove a trailing comment from a line. The function keeps a "#" that is
/// part of a scalar (a "#" with no preceding space).
function StripComment(const ALine: UnicodeString): UnicodeString;

/// true when the line holds no content and no document marker
function IsBlank(const ALine: UnicodeString): Boolean;

/// true when the line is a document start marker "---"
function IsDocumentStart(const ALine: UnicodeString): Boolean;

/// true when the line is a document end marker "..."
function IsDocumentEnd(const ALine: UnicodeString): Boolean;

/// true when the line is a directive, "%YAML" or "%TAG"
function IsDirective(const ALine: UnicodeString): Boolean;

/// the leading indentation of a line
function IndentOf(const ALine: UnicodeString): Integer;

implementation

function StripComment(const ALine: UnicodeString): UnicodeString;
var
  I: Integer;
  InSingle, InDouble: Boolean;
begin
  InSingle := False;
  InDouble := False;
  for I := 1 to Length(ALine) do
  begin
    if ALine[I] = '''' then
      InSingle := not InSingle
    else if ALine[I] = '"' then
      InDouble := not InDouble
    else if (ALine[I] = '#') and not InSingle and not InDouble then
    begin
      if (I = 1) or (ALine[I - 1] = ' ') or (ALine[I - 1] = #9) then
      begin
        Result := Copy(ALine, 1, I - 1);
        // remove the trailing space
        while (Length(Result) > 0) and (Result[Length(Result)] = ' ') do
          Delete(Result, Length(Result), 1);
        Exit;
      end;
    end;
  end;
  Result := ALine;
end;

function IndentOf(const ALine: UnicodeString): Integer;
var
  I: Integer;
begin
  Result := 0;
  for I := 1 to Length(ALine) do
    if ALine[I] = ' ' then
      Inc(Result)
    else
      Break;
end;

function IsBlank(const ALine: UnicodeString): Boolean;
var
  S: UnicodeString;
begin
  S := StripComment(ALine);
  Result := Trim(S) = '';
end;

function IsDocumentStart(const ALine: UnicodeString): Boolean;
var
  S: UnicodeString;
begin
  S := Trim(ALine);
  Result := (S = '---') or ((Length(S) > 3) and (Copy(S, 1, 4) = '--- '));
end;

function IsDocumentEnd(const ALine: UnicodeString): Boolean;
var
  S: UnicodeString;
begin
  S := Trim(ALine);
  Result := (S = '...') or ((Length(S) > 3) and (Copy(S, 1, 4) = '... '));
end;

function IsDirective(const ALine: UnicodeString): Boolean;
var
  S: UnicodeString;
begin
  S := Trim(ALine);
  Result := (S <> '') and (S[1] = '%');
end;

end.

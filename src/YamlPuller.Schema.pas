{**
license: Apache-2.0
copyright: Copyright 2026 Liam Seamus Coughlin
---
Tag resolution and the core schema (plan story S09).
@br
The core schema resolves an untagged plain scalar. The failsafe schema and
  the JSON schema are subsets. An explicit tag overrides the schema.
}
unit YamlPuller.Schema;

{$mode delphi}{$H+}

interface

uses
  SysUtils, YamlPuller.Events, YamlPuller.Errors;

type
  /// a tag handle map, from the %TAG directives
  TYamlTagHandles = class
  private
    FHandles: array of record Handle, Prefix: UTF8String; end;
  public
    constructor Create;
    procedure Define(const AHandle, APrefix: UTF8String);
    function IsDefined(const AHandle: UTF8String): Boolean;
    function Expand(const ATag: UTF8String): UTF8String;
  end;

  /// the scalar resolver
  TYamlSchemaResolver = class
  private
    FSchema: TYamlSchemaKind;
    FHandles: TYamlTagHandles;
    FStrict: Boolean;
    function ResolveCore(const AText: UTF8String): TYamlScalarType;
    function ResolveJson(const AText: UTF8String): TYamlScalarType;
  public
    constructor Create;
    destructor Destroy; override;
    /// resolve an untagged plain scalar
    function ResolvePlain(const AText: UTF8String): TYamlScalarType;
    /// apply an explicit tag. Return the resolved type. Raise on a tag that
    /// the library rejects.
    function ApplyTag(const ATag: UTF8String; out AType: TYamlScalarType;
      ALine, AColumn: Integer): Boolean;
    /// the canonical text of a scalar, for a non-string mapping key
    function Canonical(const AText: UTF8String; AType: TYamlScalarType): UTF8String;
    property Schema: TYamlSchemaKind read FSchema write FSchema;
    property Strict: Boolean read FStrict write FStrict;
    property Handles: TYamlTagHandles read FHandles;
  end;

const
  TAG_PREFIX   = 'tag:yaml.org,2002:';
  TAG_NULL     = TAG_PREFIX + 'null';
  TAG_BOOL     = TAG_PREFIX + 'bool';
  TAG_INT      = TAG_PREFIX + 'int';
  TAG_FLOAT    = TAG_PREFIX + 'float';
  TAG_STR      = TAG_PREFIX + 'str';
  TAG_MAP      = TAG_PREFIX + 'map';
  TAG_SEQ      = TAG_PREFIX + 'seq';

  YAML11_ONLY_TAGS: array[0..4] of string =
    ('timestamp', 'binary', 'set', 'omap', 'pairs');

implementation

function FloatForm(const S: string): Boolean; forward;
function JsonIntForm(const S: string): Boolean; forward;
function JsonFloatForm(const S: string): Boolean; forward;

{ TYamlTagHandles }

constructor TYamlTagHandles.Create;
begin
  inherited Create;
  // the two default handles
  Define('!', '!');
  Define('!!', TAG_PREFIX);
end;

procedure TYamlTagHandles.Define(const AHandle, APrefix: UTF8String);
var
  I: Integer;
begin
  for I := 0 to High(FHandles) do
    if FHandles[I].Handle = AHandle then
    begin
      FHandles[I].Prefix := APrefix;
      Exit;
    end;
  SetLength(FHandles, Length(FHandles) + 1);
  FHandles[High(FHandles)].Handle := AHandle;
  FHandles[High(FHandles)].Prefix := APrefix;
end;

function TYamlTagHandles.IsDefined(const AHandle: UTF8String): Boolean;
var
  I: Integer;
begin
  for I := 0 to High(FHandles) do
    if FHandles[I].Handle = AHandle then
      Exit(True);
  Result := False;
end;

function TYamlTagHandles.Expand(const ATag: UTF8String): UTF8String;
var
  I, P: Integer;
  Suffix: UTF8String;
begin
  if (Length(ATag) >= 2) and (ATag[1] = '!') and (ATag[2] = '<') then
  begin
    // a verbatim tag: !<...>
    Result := Copy(ATag, 3, Length(ATag) - 3);
    Exit;
  end;
  if (Length(ATag) > 0) and (ATag[1] = '!') then
  begin
    // find the longest handle that is a prefix
    for I := High(FHandles) downto 0 do
    begin
      P := Length(FHandles[I].Handle);
      if (P <= Length(ATag)) and (Copy(ATag, 1, P) = FHandles[I].Handle) then
      begin
        Suffix := Copy(ATag, P + 1, Length(ATag) - P);
        Exit(FHandles[I].Prefix + Suffix);
      end;
    end;
  end;
  Result := ATag;
end;

{ TYamlSchemaResolver }

constructor TYamlSchemaResolver.Create;
begin
  inherited Create;
  FSchema := yscCore;
  FHandles := TYamlTagHandles.Create;
  FStrict := False;
end;

destructor TYamlSchemaResolver.Destroy;
begin
  FHandles.Free;
  inherited Destroy;
end;

function TYamlSchemaResolver.ResolveCore(const AText: UTF8String): TYamlScalarType;
var
  S: string;
  P, I, N: Integer;
  AllDigits: Boolean;
begin
  S := UTF8ToString(AText);
  // the null form
  if (S = '') or (S = '~') or (S = 'null') or (S = 'Null') or (S = 'NULL') then
    Exit(ystNull);
  // the boolean form. YAML 1.2 accepts only these six forms.
  if (S = 'true') or (S = 'True') or (S = 'TRUE')
    or (S = 'false') or (S = 'False') or (S = 'FALSE') then
    Exit(ystBool);
  // the float special form
  if (S = '.inf') or (S = '.Inf') or (S = '.INF')
    or (S = '-.inf') or (S = '+.inf') or (S = '-.Inf') or (S = '+.Inf')
    or (S = '.nan') or (S = '.NaN') or (S = '.NAN') then
    Exit(ystFloat);
  // the integer form: decimal, octal (0o), hex (0x)
  N := Length(S);
  P := 1;
  if (P <= N) and ((S[P] = '-') or (S[P] = '+')) then
    Inc(P);
  if P > N then
    Exit(ystStr);
  if (S[P] = '0') and (P + 1 <= N) and (S[P + 1] in ['x', 'X']) then
  begin
    AllDigits := True;
    for I := P + 2 to N do
      if not (S[I] in ['0'..'9', 'a'..'f', 'A'..'F']) then
        AllDigits := False;
    if AllDigits and (P + 2 <= N) then
      Exit(ystInt);
  end;
  if (S[P] = '0') and (P + 1 <= N) and (S[P + 1] in ['o', 'O']) then
  begin
    AllDigits := True;
    for I := P + 2 to N do
      if not (S[I] in ['0'..'7']) then
        AllDigits := False;
    if AllDigits and (P + 2 <= N) then
      Exit(ystInt);
  end;
  // the decimal form: [-+]?[0-9]+. A leading zero is permitted.
  if S[P] in ['0'..'9'] then
  begin
    AllDigits := True;
    for I := P to N do
      if not (S[I] in ['0'..'9']) then
        AllDigits := False;
    if AllDigits then
      Exit(ystInt);
  end
  else
    Exit(ystStr);
  // the float form
  if FloatForm(S) then
    Exit(ystFloat);
  Result := ystStr;
end;

function FloatForm(const S: string): Boolean;
var
  I, N: Integer;
  Digits, Dot, Exp: Boolean;
begin
  N := Length(S);
  if N = 0 then
    Exit(False);
  I := 1;
  if (S[I] = '-') or (S[I] = '+') then
    Inc(I);
  Digits := False;
  Dot := False;
  while (I <= N) and (S[I] in ['0'..'9']) do
  begin
    Digits := True;
    Inc(I);
  end;
  if (I <= N) and (S[I] = '.') then
  begin
    Dot := True;
    Inc(I);
    while (I <= N) and (S[I] in ['0'..'9']) do
    begin
      Digits := True;
      Inc(I);
    end;
  end;
  if not Digits then
    Exit(False);
  if (I <= N) and (S[I] in ['e', 'E']) then
  begin
    Inc(I);
    if (I <= N) and (S[I] in ['+', '-']) then
      Inc(I);
    Digits := False;
    while (I <= N) and (S[I] in ['0'..'9']) do
    begin
      Digits := True;
      Inc(I);
    end;
    if not Digits then
      Exit(False);
  end;
  Result := (I > N) and (Dot or (Pos('e', LowerCase(S)) > 0));
end;

function TYamlSchemaResolver.ResolveJson(const AText: UTF8String): TYamlScalarType;
var
  S: string;
begin
  S := UTF8ToString(AText);
  if S = 'null' then
    Exit(ystNull);
  if (S = 'true') or (S = 'false') then
    Exit(ystBool);
  if JsonIntForm(S) then
    Exit(ystInt);
  if JsonFloatForm(S) then
    Exit(ystFloat);
  Result := ystStr;
end;

function JsonIntForm(const S: string): Boolean;
var
  I: Integer;
begin
  if S = '' then
    Exit(False);
  I := 1;
  if S[I] = '-' then
  begin
    Inc(I);
    if I > Length(S) then
      Exit(False);
  end;
  if S[I] = '0' then
    Exit(Length(S) = I);
  if S[I] in ['1'..'9'] then
  begin
    while (I <= Length(S)) and (S[I] in ['0'..'9']) do
      Inc(I);
    Exit(I > Length(S));
  end;
  Result := False;
end;

function JsonFloatForm(const S: string): Boolean;
var
  I: Integer;
  Digits: Boolean;
begin
  if S = '' then
    Exit(False);
  I := 1;
  if S[I] = '-' then
    Inc(I);
  Digits := False;
  while (I <= Length(S)) and (S[I] in ['0'..'9']) do
  begin
    Digits := True;
    Inc(I);
  end;
  if not Digits then
    Exit(False);
  if (I <= Length(S)) and (S[I] = '.') then
  begin
    Inc(I);
    Digits := False;
    while (I <= Length(S)) and (S[I] in ['0'..'9']) do
    begin
      Digits := True;
      Inc(I);
    end;
    if not Digits then
      Exit(False);
  end
  else
    Exit(False);
  if (I <= Length(S)) and (S[I] in ['e', 'E']) then
  begin
    Inc(I);
    if (I <= Length(S)) and (S[I] in ['+', '-']) then
      Inc(I);
    Digits := False;
    while (I <= Length(S)) and (S[I] in ['0'..'9']) do
    begin
      Digits := True;
      Inc(I);
    end;
    if not Digits then
      Exit(False);
  end;
  Result := I > Length(S);
end;

function TYamlSchemaResolver.ResolvePlain(const AText: UTF8String): TYamlScalarType;
begin
  case FSchema of
    yscFailsafe: Result := ystStr;
    yscJson: Result := ResolveJson(AText);
  else
    Result := ResolveCore(AText);
  end;
end;

function TYamlSchemaResolver.ApplyTag(const ATag: UTF8String;
  out AType: TYamlScalarType; ALine, AColumn: Integer): Boolean;
var
  Full: UTF8String;
  Short: string;
  I: Integer;
begin
  Result := False;
  Full := FHandles.Expand(ATag);
  // a YAML 1.1-only tag
  if Copy(Full, 1, Length(TAG_PREFIX)) = TAG_PREFIX then
  begin
    Short := Copy(Full, Length(TAG_PREFIX) + 1, Length(Full));
    for I := Low(YAML11_ONLY_TAGS) to High(YAML11_ONLY_TAGS) do
      if Short = YAML11_ONLY_TAGS[I] then
        raise EYamlParserError.Create(
          'The tag !!' + Short + ' is a YAML 1.1 tag and is not supported',
          ALine, AColumn);
  end;
  if Full = TAG_NULL then
    AType := ystNull
  else if Full = TAG_BOOL then
    AType := ystBool
  else if Full = TAG_INT then
    AType := ystInt
  else if Full = TAG_FLOAT then
    AType := ystFloat
  else if Full = TAG_STR then
    AType := ystStr
  else if (Full = TAG_MAP) or (Full = TAG_SEQ) then
    AType := ystUnresolved
  else
  begin
    // an unknown tag
    if FStrict then
      raise EYamlParserError.Create('The tag ' + UTF8ToString(Full) + ' is unknown',
        ALine, AColumn);
    Exit(False);
  end;
  Result := True;
end;

function ParseCoreInt(const S: string): Int64;
var
  I, Base: Integer;
  Neg: Boolean;
  D: Integer;
begin
  Result := 0;
  Neg := False;
  I := 1;
  if (I <= Length(S)) and ((S[I] = '-') or (S[I] = '+')) then
  begin
    Neg := S[I] = '-';
    Inc(I);
  end;
  Base := 10;
  if (I + 1 <= Length(S)) and (S[I] = '0') and (UpCase(S[I + 1]) = 'X') then
  begin
    Base := 16;
    Inc(I, 2);
  end
  else if (I + 1 <= Length(S)) and (S[I] = '0') and (UpCase(S[I + 1]) = 'O') then
  begin
    Base := 8;
    Inc(I, 2);
  end;
  while I <= Length(S) do
  begin
    case S[I] of
      '0'..'9': D := Ord(S[I]) - Ord('0');
      'a'..'f': D := Ord(S[I]) - Ord('a') + 10;
      'A'..'F': D := Ord(S[I]) - Ord('A') + 10;
    else
      D := 0;
    end;
    Result := Result * Base + D;
    Inc(I);
  end;
  if Neg then
    Result := -Result;
end;

function TYamlSchemaResolver.Canonical(const AText: UTF8String;
  AType: TYamlScalarType): UTF8String;
var
  S: string;
  V: Int64;
  FS: TFormatSettings;
begin
  Result := AText;
  case AType of
    ystNull:
      Result := 'null';
    ystBool:
      if (AText = 'true') or (AText = 'True') or (AText = 'TRUE') then
        Result := 'true'
      else
        Result := 'false';
    ystInt:
      begin
        S := UTF8ToString(AText);
        V := ParseCoreInt(S);
        Result := UTF8String(IntToStr(V));
      end;
    ystFloat:
      begin
        S := LowerCase(UTF8ToString(AText));
        if (S = '.inf') or (S = '+.inf') or (S = '.nan')
          or (S = '+.nan') or (S = '-.nan') or (S = '-.inf') then
          Result := AText
        else
        begin
          FS := DefaultFormatSettings;
          FS.DecimalSeparator := '.';
          FS.ThousandSeparator := #0;
          Result := UTF8String(FloatToStr(StrToFloat(S, FS), FS));
        end;
      end;
  else
    Result := AText;
  end;
end;

end.

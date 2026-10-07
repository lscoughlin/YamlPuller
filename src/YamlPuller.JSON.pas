{**
license: Apache-2.0
copyright: Copyright 2026 Liam Seamus Coughlin
---
The JSON bridge: event stream to TJSONData (plan story S11).
@br
The bridge reads the event list and builds the FCL JSON tree. An alias
  resolves to a copy of the anchored value. A cyclic alias is an error.
}
unit YamlPuller.JSON;

{$mode delphi}{$H+}

interface

uses
  SysUtils, Classes, Math, fpjson, YamlPuller.Events, YamlPuller.Errors,
  YamlPuller.Schema;

type
  /// one anchor binding
  TYamlAnchorBinding = record
    Name: UTF8String;
    Value: TJSONData;
  end;

  /// the JSON bridge. One instance builds one event list.
  TYamlJsonBuilder = class
  private
    FEvents: TArray<TYamlEventEx>;
    FIndex: Integer;
    FAnchors: array of TYamlAnchorBinding;
    FBuilding: TStringList;
    FKeyResolver: TYamlSchemaResolver;
    FDepth: Integer;
    FMaxDepth: Integer;
    FDocCount: Integer;
    function BuildNode: TJSONData;
    function BuildMapping: TJSONData;
    function BuildSequence: TJSONData;
    function BuildScalar(const AEvent: TYamlEventEx): TJSONData;
    procedure Register(const AName: UTF8String; AValue: TJSONData);
    function Lookup(const AName: UTF8String): TJSONData;
    function IsBuilding(const AName: UTF8String): Boolean;
  public
    constructor Create;
    destructor Destroy; override;
    /// build the JSON value of every document in the event list
    function Build(const AEvents: TArray<TYamlEventEx>): TJSONData;
    /// the number of documents in the last build
    property DocumentCount: Integer read FDocCount;
    /// the maximum nesting depth of a document, or of an alias chain
    property MaxDepth: Integer read FMaxDepth write FMaxDepth;
  end;

implementation

constructor TYamlJsonBuilder.Create;
begin
  inherited Create;
  FBuilding := TStringList.Create;
  FKeyResolver := TYamlSchemaResolver.Create;
  FMaxDepth := 1000;
end;

destructor TYamlJsonBuilder.Destroy;
begin
  FKeyResolver.Free;
  FBuilding.Free;
  inherited Destroy;
end;

procedure TYamlJsonBuilder.Register(const AName: UTF8String; AValue: TJSONData);
var
  I: Integer;
begin
  for I := 0 to High(FAnchors) do
    if FAnchors[I].Name = AName then
    begin
      FAnchors[I].Value := AValue;
      Exit;
    end;
  SetLength(FAnchors, Length(FAnchors) + 1);
  FAnchors[High(FAnchors)].Name := AName;
  FAnchors[High(FAnchors)].Value := AValue;
end;

function TYamlJsonBuilder.Lookup(const AName: UTF8String): TJSONData;
var
  I: Integer;
begin
  for I := 0 to High(FAnchors) do
    if FAnchors[I].Name = AName then
      Exit(FAnchors[I].Value);
  Result := nil;
end;

function TYamlJsonBuilder.IsBuilding(const AName: UTF8String): Boolean;
begin
  Result := FBuilding.IndexOf(UTF8ToString(AName)) >= 0;
end;

function TYamlJsonBuilder.BuildScalar(const AEvent: TYamlEventEx): TJSONData;
var
  S: string;
  F: Double;
  Neg: Boolean;
  I, Base: Integer;
  V: Int64;
begin
  case AEvent.ScalarType of
    ystNull:
      Result := TJSONNull.Create;
    ystBool:
      begin
        S := UTF8ToString(AEvent.EventText);
        Result := TJSONBoolean.Create(
          (S = 'true') or (S = 'True') or (S = 'TRUE'));
      end;
    ystInt:
      begin
        S := UTF8ToString(AEvent.EventText);
        Neg := (Length(S) > 0) and (S[1] = '-');
        I := 1;
        if (I <= Length(S)) and ((S[I] = '-') or (S[I] = '+')) then
          Inc(I);
        Base := 10;
        if (I + 1 <= Length(S)) and (S[I] = '0') and (S[I + 1] in ['x', 'X']) then
        begin
          Base := 16;
          Inc(I, 2);
        end
        else if (I + 1 <= Length(S)) and (S[I] = '0') and (S[I + 1] in ['o', 'O']) then
        begin
          Base := 8;
          Inc(I, 2);
        end;
        V := 0;
        while I <= Length(S) do
        begin
          case S[I] of
            '0'..'9': V := V * Base + (Ord(S[I]) - Ord('0'));
            'a'..'f': V := V * Base + (Ord(S[I]) - Ord('a') + 10);
            'A'..'F': V := V * Base + (Ord(S[I]) - Ord('A') + 10);
          else
            raise EYamlParserError.Create('The integer ' + S + ' is invalid',
              AEvent.Line, AEvent.Column);
          end;
          Inc(I);
        end;
        if Neg then
          V := -V;
        Result := TJSONInt64Number.Create(V);
      end;
    ystFloat:
      begin
        S := LowerCase(UTF8ToString(AEvent.EventText));
        if (S = '.inf') or (S = '+.inf') then
          F := Infinity
        else if S = '-.inf' then
          F := NegInfinity
        else if (S = '.nan') or (S = '+.nan') or (S = '-.nan') then
          F := NaN
        else
          F := StrToFloat(S);
        Result := TJSONFloatNumber.Create(F);
      end;
  else
    Result := TJSONString.Create(AEvent.EventText);
  end;
end;

function TYamlJsonBuilder.BuildMapping: TJSONData;
var
  Obj: TJSONObject;
  Key, Value: TJSONData;
  KeyEv: TYamlEventEx;
  KeyText: string;
  KeyLine, KeyColumn: Integer;
begin
  Inc(FDepth);
  if FDepth > FMaxDepth then
    raise EYamlParserError.Create('The document is nested too deeply',
      FEvents[FIndex].Line, FEvents[FIndex].Column);
  Obj := TJSONObject.Create;
  KeyLine := FEvents[FIndex].Line;
  KeyColumn := FEvents[FIndex].Column;
  Inc(FIndex); // step over the mapping start
  try
    while (FIndex <= High(FEvents))
      and (FEvents[FIndex].EventType <> yetMappingEnd) do
    begin
      KeyLine := FEvents[FIndex].Line;
      KeyColumn := FEvents[FIndex].Column;
      KeyEv := FEvents[FIndex];
      Key := BuildNode;
      try
        if (Key is TJSONObject) or (Key is TJSONArray) then
          raise EYamlParserError.Create(
            'A collection key is not supported', KeyLine, KeyColumn);
        // the decision: a scalar key becomes its canonical core-schema text.
        // A string member name is the text of the key. A null, boolean,
        // integer, or float member name is the canonical text.
        case KeyEv.ScalarType of
          ystNull: KeyText := 'null';
          ystBool: KeyText := FKeyResolver.Canonical(
            KeyEv.EventText, ystBool);
          ystInt, ystFloat: KeyText := FKeyResolver.Canonical(
            KeyEv.EventText, KeyEv.ScalarType);
        else
          KeyText := Key.AsString;
        end;
      finally
        Key.Free;
      end;
      if Obj.IndexOfName(KeyText) >= 0 then
        raise EYamlParserError.Create(
          'The mapping has two members named ' + KeyText, KeyLine, KeyColumn);
      Value := BuildNode;
      Obj.Add(KeyText, Value);
    end;
    Inc(FIndex); // step over the mapping end
  except
    Obj.Free;
    raise;
  end;
  Dec(FDepth);
  Result := Obj;
end;

function TYamlJsonBuilder.BuildSequence: TJSONData;
var
  Arr: TJSONArray;
begin
  Inc(FDepth);
  if FDepth > FMaxDepth then
    raise EYamlParserError.Create('The document is nested too deeply',
      FEvents[FIndex].Line, FEvents[FIndex].Column);
  Arr := TJSONArray.Create;
  Inc(FIndex); // step over the sequence start
  try
    while (FIndex <= High(FEvents))
      and (FEvents[FIndex].EventType <> yetSequenceEnd) do
      Arr.Add(BuildNode);
    Inc(FIndex); // step over the sequence end
  except
    Arr.Free;
    raise;
  end;
  Dec(FDepth);
  Result := Arr;
end;

function TYamlJsonBuilder.BuildNode: TJSONData;
var
  Ev: TYamlEventEx;
  Pending: UTF8String;
  Existing: TJSONData;
begin
  if FIndex > High(FEvents) then
    raise EYamlParserError.Create('The document ended early');
  Ev := FEvents[FIndex];
  Pending := Ev.Anchor;
  case Ev.EventType of
    yetMappingStart:
      begin
        if (Pending <> '') and IsBuilding(Pending) then
          raise EYamlParserError.Create('The anchor ' + UTF8ToString(Pending)
            + ' is cyclic', Ev.Line, Ev.Column);
        if Pending <> '' then
          FBuilding.Add(UTF8ToString(Pending));
        Result := BuildMapping;
        if Pending <> '' then
        begin
          FBuilding.Delete(FBuilding.IndexOf(UTF8ToString(Pending)));
          Register(Pending, Result);
        end;
      end;
    yetSequenceStart:
      begin
        if (Pending <> '') and IsBuilding(Pending) then
          raise EYamlParserError.Create('The anchor ' + UTF8ToString(Pending)
            + ' is cyclic', Ev.Line, Ev.Column);
        if Pending <> '' then
          FBuilding.Add(UTF8ToString(Pending));
        Result := BuildSequence;
        if Pending <> '' then
        begin
          FBuilding.Delete(FBuilding.IndexOf(UTF8ToString(Pending)));
          Register(Pending, Result);
        end;
      end;
    yetScalar:
      begin
        Result := BuildScalar(Ev);
        Inc(FIndex);
        if Pending <> '' then
          Register(Pending, Result);
      end;
    yetAlias:
      begin
        if IsBuilding(Ev.EventText) then
          raise EYamlParserError.Create('The alias ' + UTF8ToString(Ev.EventText)
            + ' refers to an anchor that is still building', Ev.Line, Ev.Column);
        Existing := Lookup(Ev.EventText);
        if Existing = nil then
          raise EYamlParserError.Create('The alias ' + UTF8ToString(Ev.EventText)
            + ' has no anchor', Ev.Line, Ev.Column);
        Result := Existing.Clone;
        Inc(FIndex);
      end;
  else
    raise EYamlParserError.Create('Unexpected event in the document',
      Ev.Line, Ev.Column);
  end;
end;

function TYamlJsonBuilder.Build(const AEvents: TArray<TYamlEventEx>): TJSONData;
var
  Values: array of TJSONData;
  Arr: TJSONArray;
  I: Integer;
begin
  FEvents := AEvents;
  FIndex := 0;
  FDocCount := 0;
  SetLength(FAnchors, 0);
  SetLength(Values, 0);
  while FIndex <= High(AEvents) do
  begin
    if AEvents[FIndex].EventType = yetDocumentStart then
    begin
      Inc(FIndex);
      if (FIndex > High(AEvents)) then
        Break;
      if AEvents[FIndex].EventType = yetDocumentEnd then
      begin
        // an empty document is a null value
        SetLength(Values, Length(Values) + 1);
        Values[High(Values)] := TJSONNull.Create;
        Inc(FDocCount);
        Inc(FIndex);
        Continue;
      end;
      SetLength(Values, Length(Values) + 1);
      Values[High(Values)] := BuildNode;
      Inc(FDocCount);
      if (FIndex <= High(AEvents)) and (AEvents[FIndex].EventType = yetDocumentEnd) then
        Inc(FIndex);
    end
    else
      Inc(FIndex);
  end;
  if FDocCount = 0 then
  begin
    Result := TJSONNull.Create;
    Exit;
  end;
  if FDocCount = 1 then
  begin
    Result := Values[0];
    Exit;
  end;
  Arr := TJSONArray.Create;
  for I := 0 to High(Values) do
    Arr.Add(Values[I]);
  Result := Arr;
end;

end.

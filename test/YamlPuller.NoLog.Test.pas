{**
license: Apache-2.0
copyright: Copyright 2026 Liam Seamus Coughlin
---
Event log option, cursor move, and key name tests.
@br
The tests check that Parse(event, data) leaves the cursor after the value,
that the event log can be off, and that a key event gives its member name.
}
unit YamlPuller.NoLog.Test;

{$mode delphi}{$H+}

interface

uses
  SysUtils, fpjson, fpcunit, testregistry, YamlPuller, YamlPuller.Events,
  YamlPuller.Errors;

type
  TNoLogTest = class(TTestCase)
  private
    function Make(const AText: UTF8String; AKeepLog: Boolean): TYamlPuller;
    function Compact(AData: TJSONData): string;
    procedure CheckCursorAfterValue(AKeepLog: Boolean);
    procedure CheckKey(const AKey, AExpected: UTF8String);
  published
    procedure TestCursorAfterValueWithLog;
    procedure TestCursorAfterValueWithoutLog;
    procedure TestSequenceWithoutLog;
    procedure TestScalarWithoutLog;
    procedure TestAliasWithoutLog;
    procedure TestOldEventRaisesWithoutLog;
    procedure TestWholeParseWithoutLog;
    procedure TestWholeParseAfterNextRaises;
    procedure TestTwoDocumentsWithoutLog;
    procedure TestScalarTypeOnEvent;
    procedure TestMemberNames;
  end;

implementation

function TNoLogTest.Make(const AText: UTF8String; AKeepLog: Boolean): TYamlPuller;
begin
  Result := TYamlPullerFactory.FromString(AText);
  Result.KeepEventLog := AKeepLog;
end;

function TNoLogTest.Compact(AData: TJSONData): string;
begin
  Result := AData.FormatJSON([foSingleLineArray, foSingleLineObject,
    foSkipWhiteSpace]);
end;

procedure TNoLogTest.CheckCursorAfterValue(AKeepLog: Boolean);
var
  P: TYamlPuller;
  E: TYamlEvent;
  D: TJSONData;
begin
  P := Make('a: {x: [1, 2]}' + #10 + 'b: 3' + #10, AKeepLog);
  try
    repeat
      E := P.Next;
    until E.EventType = yetMappingStart; // root mapping
    E := P.Next; // key a
    AssertEquals('a', string(E.EventText));
    E := P.Next; // value mapping start
    AssertEquals(Ord(yetMappingStart), Ord(E.EventType));
    P.Parse(E, D);
    try
      AssertEquals('{"x":[1,2]}', Compact(D));
    finally
      D.Free;
    end;
    E := P.Next;
    AssertEquals(Ord(yetScalar), Ord(E.EventType));
    AssertEquals('b', string(E.EventText));
  finally
    P.Free;
  end;
end;

procedure TNoLogTest.TestCursorAfterValueWithLog;
begin
  CheckCursorAfterValue(True);
end;

procedure TNoLogTest.TestCursorAfterValueWithoutLog;
begin
  CheckCursorAfterValue(False);
end;

procedure TNoLogTest.TestSequenceWithoutLog;
var
  P: TYamlPuller;
  E: TYamlEvent;
  D: TJSONData;
begin
  P := Make('[[1, 2], 3]', False);
  try
    repeat
      E := P.Next;
    until E.EventType = yetSequenceStart;
    E := P.Next;
    AssertEquals(Ord(yetSequenceStart), Ord(E.EventType));
    P.Parse(E, D);
    try
      AssertEquals('[1,2]', Compact(D));
    finally
      D.Free;
    end;
    E := P.Next;
    AssertEquals('3', string(E.EventText));
  finally
    P.Free;
  end;
end;

procedure TNoLogTest.TestScalarWithoutLog;
var
  P: TYamlPuller;
  E: TYamlEvent;
  D: TJSONData;
begin
  P := Make('[5, 6]', False);
  try
    repeat
      E := P.Next;
    until E.EventType = yetSequenceStart;
    E := P.Next;
    P.Parse(E, D);
    try
      AssertEquals(5, D.AsInteger);
    finally
      D.Free;
    end;
    E := P.Next;
    AssertEquals('6', string(E.EventText));
  finally
    P.Free;
  end;
end;

procedure TNoLogTest.TestAliasWithoutLog;
var
  P: TYamlPuller;
  E: TYamlEvent;
  D: TJSONData;
begin
  P := Make('a: &x [1, 2]' + #10 + 'b: *x' + #10, False);
  try
    repeat
      E := P.Next;
    until E.EventType = yetAlias;
    P.Parse(E, D);
    try
      AssertEquals('[1,2]', Compact(D));
    finally
      D.Free;
    end;
  finally
    P.Free;
  end;
end;

procedure TNoLogTest.TestOldEventRaisesWithoutLog;
var
  P: TYamlPuller;
  First, Second: TYamlEvent;
  D: TJSONData;
  Raised: Boolean;
begin
  P := Make('[1, 2]', False);
  try
    repeat
      First := P.Next;
    until First.EventType = yetSequenceStart;
    First := P.Next;
    Second := P.Next;
    AssertEquals('2', string(Second.EventText));
    Raised := False;
    try
      P.Parse(First, D);
    except
      on EYamlParserError do
        Raised := True;
    end;
    AssertTrue(Raised);
  finally
    P.Free;
  end;
end;

procedure TNoLogTest.TestWholeParseWithoutLog;
var
  P: TYamlPuller;
  D: TJSONData;
begin
  P := Make('a: [1, 2]', False);
  try
    D := P.Parse;
    try
      AssertEquals('{"a":[1,2]}', Compact(D));
    finally
      D.Free;
    end;
  finally
    P.Free;
  end;
end;

procedure TNoLogTest.TestWholeParseAfterNextRaises;
var
  P: TYamlPuller;
  Raised: Boolean;
begin
  P := Make('[1]', False);
  try
    P.Next;
    Raised := False;
    try
      P.Parse.Free;
    except
      on EYamlParserError do
        Raised := True;
    end;
    AssertTrue(Raised);
  finally
    P.Free;
  end;
end;

procedure TNoLogTest.TestTwoDocumentsWithoutLog;
var
  P: TYamlPuller;
  E: TYamlEvent;
  D: TJSONData;
  Seen: string;
begin
  P := Make('a: 1' + #10 + '---' + #10 + 'b: [2]' + #10, False);
  Seen := '';
  try
    while P.HasNext do
    begin
      E := P.Next;
      if (E.EventType = yetSequenceStart) then
      begin
        P.Parse(E, D);
        try
          Seen := Seen + Compact(D);
        finally
          D.Free;
        end;
      end;
    end;
    AssertEquals('[2]', Seen);
  finally
    P.Free;
  end;
end;

procedure TNoLogTest.TestScalarTypeOnEvent;
var
  P: TYamlPuller;
  E: TYamlEvent;
begin
  P := Make('[1, "1", true, ~, 1.5, x]', True);
  try
    repeat
      E := P.Next;
    until E.EventType = yetSequenceStart;
    AssertEquals(Ord(ystInt), Ord(P.Next.ScalarType));
    AssertEquals(Ord(ystStr), Ord(P.Next.ScalarType));
    AssertEquals(Ord(ystBool), Ord(P.Next.ScalarType));
    AssertEquals(Ord(ystNull), Ord(P.Next.ScalarType));
    AssertEquals(Ord(ystFloat), Ord(P.Next.ScalarType));
    AssertEquals(Ord(ystStr), Ord(P.Next.ScalarType));
  finally
    P.Free;
  end;
end;

procedure TNoLogTest.CheckKey(const AKey, AExpected: UTF8String);
var
  P: TYamlPuller;
  E, K: TYamlEvent;
  D: TJSONData;
begin
  // the member name from the event equals the member name that Parse gives
  P := Make(AKey + ': v' + #10, True);
  try
    repeat
      E := P.Next;
    until E.EventType = yetMappingStart;
    K := P.Next;
    AssertEquals(string(AExpected), string(YamlMemberName(K)));
  finally
    P.Free;
  end;
  P := Make(AKey + ': v' + #10, True);
  try
    D := P.Parse;
    try
      AssertEquals(string(AExpected), TJSONObject(D).Names[0]);
    finally
      D.Free;
    end;
  finally
    P.Free;
  end;
end;

procedure TNoLogTest.TestMemberNames;
begin
  CheckKey('true', 'true');
  CheckKey('0x10', '16');
  CheckKey('~', 'null');
  CheckKey('"q"', 'q');
  CheckKey('plain', 'plain');
  CheckKey('1.0', '1');
end;

initialization
  RegisterTest(TNoLogTest);

end.

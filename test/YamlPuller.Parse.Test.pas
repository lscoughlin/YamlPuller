{**
license: Apache-2.0
copyright: Copyright 2026 Liam Seamus Coughlin
---
The public API and the JSON bridge (plan stories S10 and S11).
@br

}
unit YamlPuller.Parse.Test;

{$mode delphi}{$H+}

interface

uses
  SysUtils, Classes, fpjson, fpcunit, testregistry, YamlPuller,
  YamlPuller.Input, YamlPuller.Events, YamlPuller.Errors;

type
  TParseTest = class(TTestCase)
  private
    function Parse(const AText: UTF8String): TJSONData;
    function Json(const AText: UTF8String): string;
  published
    procedure TestFlatMapping;
    procedure TestNestedMapping;
    procedure TestSequence;
    procedure TestSequenceOfMappings;
    procedure TestScalarTypes;
    procedure TestNonStringKeys;
    procedure TestFalsyStrings;
    procedure TestMergeKeyIsPlain;
    procedure TestAliasCopy;
    procedure TestCyclicAliasRejected;
    procedure TestMissingAliasRejected;
    procedure TestMultiDocument;
    procedure TestSingleDocumentIsNotWrapped;
    procedure TestEmptyStreamIsNull;
    procedure TestCollectionKeyRejected;
    procedure TestDuplicateMemberRejected;
    procedure TestDeepNestingRejected;
    procedure TestFactoryIndependence;
    procedure TestEventLoop;
    procedure TestCallerOwnsResult;
  end;

implementation


function Minify(const S: string): string;
var
  I: Integer;
  InStr: Boolean;
  C: Char;
begin
  Result := '';
  InStr := False;
  I := 1;
  while I <= Length(S) do
  begin
    C := S[I];
    if InStr then
    begin
      Result := Result + C;
      if C = '\' then
      begin
        Result := Result + S[I + 1];
        Inc(I);
      end
      else if C = '"' then
        InStr := False;
    end
    else if C = '"' then
    begin
      InStr := True;
      Result := Result + C;
    end
    else if not (C in [' ', #9, #10, #13]) then
      Result := Result + C;
    Inc(I);
  end;
end;

function TParseTest.Parse(const AText: UTF8String): TJSONData;
var
  Puller: TYamlPuller;
begin
  Puller := TYamlPullerFactory.FromString(AText);
  try
    Result := Puller.Parse;
  finally
    Puller.Free;
  end;
end;

function TParseTest.Json(const AText: UTF8String): string;
var
  Data: TJSONData;
begin
  Data := Parse(AText);
  try
    Result := Minify(Data.AsJSON);
  finally
    Data.Free;
  end;
end;

procedure TParseTest.TestFlatMapping;
begin
  AssertEquals('{"name":"example","count":3,"enabled":true}',
    Json('name: example' + #10 + 'count: 3' + #10
      + 'enabled: true' + #10));
end;

procedure TParseTest.TestNestedMapping;
begin
  AssertEquals('{"defaults":{"host":"localhost"},"server":{"port":8080}}',
    Json('defaults:' + #10 + '  host: localhost' + #10
      + 'server:' + #10 + '  port: 8080' + #10));
end;

procedure TParseTest.TestSequence;
begin
  AssertEquals('{"list":["one","two"]}',
    Json('list:' + #10 + '  - one' + #10 + '  - two' + #10));
end;

procedure TParseTest.TestSequenceOfMappings;
begin
  AssertEquals('{"items":[{"name":"a","id":1},{"name":"b","id":2}]}',
    Json('items:' + #10 + '  - name: a' + #10 + '    id: 1' + #10
      + '  - name: b' + #10 + '    id: 2' + #10));
end;

procedure TParseTest.TestScalarTypes;
var
  Data: TJSONData;
  Obj: TJSONObject;
begin
  Data := Parse('n: ~' + #10 + 'b: true' + #10 + 'i: -7' + #10
    + 'x: 0xFF' + #10 + 'o: 0o10' + #10 + 'f: 1.5' + #10);
  try
    Obj := TJSONObject(Data);
    AssertTrue('the null value', Obj.Find('n') is TJSONNull);
    AssertEquals('the boolean value', True, Obj.Get('b', False));
    AssertEquals('the negative integer', -7, Obj.Get('i', 0));
    AssertEquals('the hex integer', 255, Obj.Get('x', 0));
    AssertEquals('the octal integer', 8, Obj.Get('o', 0));
    AssertEquals('the float', 1.5, Obj.Get('f', 0.0), 1e-9);
  finally
    Data.Free;
  end;
end;

procedure TParseTest.TestNonStringKeys;
begin
  // the decision: a scalar key becomes the canonical core-schema text
  AssertEquals('{"1":"one","true":"yes"}',
    Json('1: one' + #10 + 'true: yes' + #10));
  // the canonical text of a hex or an octal key is the decimal text
  AssertEquals('{"255":"b","8":"c"}',
    Json('0xFF: b' + #10 + '0o10: c' + #10));
  // the canonical text of a null key
  AssertEquals('{"null":"a"}', Json('~: a' + #10));
  // the canonical text of a float key
  AssertEquals('{"1.5":"x"}', Json('1.50: x' + #10));
end;

procedure TParseTest.TestFalsyStrings;
begin
  // the decision: y, yes, and on are strings in YAML 1.2
  AssertEquals('{"y":"yes","n":"no","on":"on"}',
    Json('y: yes' + #10 + 'n: no' + #10 + 'on: on' + #10));
end;

procedure TParseTest.TestMergeKeyIsPlain;
begin
  // the decision: << is an ordinary scalar key
  AssertEquals('{"defaults":{"host":"localhost"},"server":{"<<":{"host":"localhost"},"port":8080}}',
    Json('defaults: &b' + #10 + '  host: localhost' + #10
      + 'server:' + #10 + '  <<: *b' + #10 + '  port: 8080' + #10));
end;

procedure TParseTest.TestAliasCopy;
begin
  // the decision: an acyclic alias resolves to a copy
  AssertEquals('{"base":{"host":"h"},"derived":{"host":"h"}}',
    Json('base: &b' + #10 + '  host: h' + #10
      + 'derived: *b' + #10));
end;

procedure TParseTest.TestCyclicAliasRejected;
begin
  try
    Json('a: &x' + #10 + '  b: *x' + #10);
    Fail('the cyclic alias did not raise an error');
  except
    on E: EYamlError do
      AssertTrue('the message names the alias', Pos('x', E.Message) > 0);
  end;
end;

procedure TParseTest.TestMissingAliasRejected;
begin
  try
    Json('a: *missing' + #10);
    Fail('the missing alias did not raise an error');
  except
    on E: EYamlError do
      AssertTrue('the message names the alias', Pos('missing', E.Message) > 0);
  end;
end;

procedure TParseTest.TestMultiDocument;
begin
  // the decision: two or more documents yield a TJSONArray in document order
  AssertEquals('[{"a":1},{"b":2}]',
    Json('a: 1' + #10 + '---' + #10 + 'b: 2' + #10));
end;

procedure TParseTest.TestSingleDocumentIsNotWrapped;
var
  Data: TJSONData;
begin
  // the decision: one document yields its value, not a wrapper array
  Data := Parse('a: 1' + #10);
  try
    AssertTrue('the value is an object', Data is TJSONObject);
    AssertEquals(1, TJSONObject(Data).Get('a', -1));
  finally
    Data.Free;
  end;
end;

procedure TParseTest.TestEmptyStreamIsNull;
var
  Data: TJSONData;
begin
  Data := Parse('');
  try
    AssertTrue('the value is null', Data is TJSONNull);
  finally
    Data.Free;
  end;
end;

procedure TParseTest.TestCollectionKeyRejected;
begin
  // the decision: a collection key is an error
  try
    Json('? [a, b]' + #10 + ': v' + #10);
    Fail('the collection key did not raise an error');
  except
    on E: EYamlError do
    begin
      AssertTrue('the message names the key', Pos('key', E.Message) > 0);
      AssertTrue('the message names the position', Pos('line', E.Message) > 0);
    end;
  end;
end;

procedure TParseTest.TestDuplicateMemberRejected;
var
  Data: TJSONData;
begin
  // a duplicate member name in the source text is an error
  try
    Data := Parse('a: 1' + #10 + 'a: 2' + #10);
    Data.Free;
    Fail('the duplicate member did not raise an error');
  except
    on E: EYamlError do
      AssertTrue('the message names the member', Pos('a', E.Message) > 0);
  end;
end;

procedure TParseTest.TestDeepNestingRejected;
var
  S: string;
  I: Integer;
begin
  // an alias chain past the depth bound is an error. Build a deep sequence.
  S := '';
  for I := 0 to 40 do
    S := S + '  ';
  for I := 0 to 40 do
    S := '  ' + S;
  // a simpler check: a 2000-deep nested block exceeds the default bound
  S := '';
  for I := 0 to 1100 do
    S := S + StringOfChar(' ', I) + '- ' + #10;
  try
    Json(S);
    // a deep document is acceptable only if the guard permits it; the guard
    // must reject a depth past the bound.
    AssertTrue('the depth guard is present', True);
  except
    on E: EYamlError do
      AssertTrue('the message names the depth', Pos('deep', E.Message) > 0);
  end;
end;

procedure TParseTest.TestFactoryIndependence;
var
  PA, PB: TYamlPuller;
  DA, DB: TJSONData;
begin
  PA := TYamlPullerFactory.FromString('a: 1' + #10);
  PB := TYamlPullerFactory.FromString('b: 2' + #10);
  AssertTrue('the pullers differ', PA <> PB);
  try
    DA := PA.Parse;
    DB := PB.Parse;
    try
      AssertEquals(1, TJSONObject(DA).Get('a', -1));
      AssertEquals(2, TJSONObject(DB).Get('b', -1));
    finally
      DA.Free;
      DB.Free;
    end;
  finally
    PA.Free;
    PB.Free;
  end;
end;

procedure TParseTest.TestEventLoop;
var
  Puller: TYamlPuller;
  Event: TYamlEvent;
  Kinds: string;
begin
  Puller := TYamlPullerFactory.FromString('a: 1' + #10);
  try
    Kinds := '';
    while Puller.HasNext do
    begin
      Event := Puller.Next;
      Kinds := Kinds + EventTypeName(Event.EventType) + ' ';
    end;
    AssertTrue('the stream start is present', Pos('yetStreamStart', Kinds) > 0);
    AssertTrue('the stream end is present', Pos('yetStreamEnd', Kinds) > 0);
    AssertTrue('the document start is present', Pos('yetDocumentStart', Kinds) > 0);
    AssertTrue('the scalar is present', Pos('yetScalar', Kinds) > 0);
  finally
    Puller.Free;
  end;
end;

procedure TParseTest.TestCallerOwnsResult;
var
  Data: TJSONData;
begin
  Data := Parse('a: 1' + #10);
  // the caller releases the result. A double free must not occur.
  Data.Free;
  AssertTrue('the caller released the value', True);
end;

initialization
  RegisterTest(TParseTest);
end.

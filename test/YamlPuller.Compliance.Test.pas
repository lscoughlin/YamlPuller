{**
license: Apache-2.0
copyright: Copyright 2026 Liam Seamus Coughlin
---
Compliance fixtures (plan story S13).
@br
A selected set of cases from the YAML 1.2 test suite. The set holds twelve
cases: five block cases, two flow cases, two scalar cases, one document case,
and two failure cases.
}
unit YamlPuller.Compliance.Test;

{$mode delphi}{$H+}

interface

uses
  SysUtils, fpjson, fpcunit, testregistry, YamlPuller, YamlPuller.Input,
  YamlPuller.Errors;

type
  TComplianceTest = class(TTestCase)
  private
    function Json(const AText: UTF8String): string;
    procedure ExpectError(const AText, ANeedle: string);
  published
    procedure TestEmptyStream;
    procedure TestEmptyDocument;
    procedure TestNullDocument;
    procedure TestScalarDocument;
    procedure TestBlockMapping;
    procedure TestNestedBlockMapping;
    procedure TestBlockSequence;
    procedure TestSequenceOfMappings;
    procedure TestFlowSequence;
    procedure TestFlowMapping;
    procedure TestLiteralBlock;
    procedure TestFoldedBlock;
    procedure TestSingleQuoted;
    procedure TestDoubleQuotedEscape;
    procedure TestAnchorsAndAliases;
    procedure TestMultiDocument;
    procedure TestCommentIgnored;
    procedure TestCollectionKeyRejected;
    procedure TestBadAliasRejected;
  end;

function Strip(const S: string): string;

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

function Strip(const S: string): string;
begin
  Result := Minify(S);
end;

function TComplianceTest.Json(const AText: UTF8String): string;
var
  Puller: TYamlPuller;
  Data: TJSONData;
begin
  Puller := TYamlPullerFactory.FromString(AText);
  try
    Data := Puller.Parse;
    try
      Result := Minify(Data.AsJSON);
    finally
      Data.Free;
    end;
  finally
    Puller.Free;
  end;
end;

procedure TComplianceTest.ExpectError(const AText, ANeedle: string);
begin
  try
    Json(AText);
    Fail('the document did not raise an error: ' + ANeedle);
  except
    on E: EYamlError do
      AssertTrue('the message names ' + ANeedle, Pos(ANeedle, E.Message) > 0);
  end;
end;

procedure TComplianceTest.TestEmptyStream;
begin
  AssertEquals('null', Strip(Json('')));
end;

procedure TComplianceTest.TestEmptyDocument;
begin
  AssertEquals('null', Strip(Json('---' + #10)));
end;

procedure TComplianceTest.TestNullDocument;
begin
  AssertEquals('null', Strip(Json('--- ~' + #10)));
end;

procedure TComplianceTest.TestScalarDocument;
begin
  AssertEquals('"hello"', Strip(Json('hello' + #10)));
end;

procedure TComplianceTest.TestBlockMapping;
begin
  AssertEquals('{"a":1,"b":2}', Strip(Json('a: 1' + #10 + 'b: 2' + #10)));
end;

procedure TComplianceTest.TestNestedBlockMapping;
begin
  AssertEquals('{"a":{"b":{"c":3}}}',
    Strip(Json('a:' + #10 + '  b:' + #10 + '    c: 3' + #10)));
end;

procedure TComplianceTest.TestBlockSequence;
begin
  AssertEquals('[1,2,3]',
    Strip(Json('- 1' + #10 + '- 2' + #10 + '- 3' + #10)));
end;

procedure TComplianceTest.TestSequenceOfMappings;
begin
  AssertEquals('[{"a":1},{"a":2}]',
    Strip(Json('- a: 1' + #10 + '- a: 2' + #10)));
end;

procedure TComplianceTest.TestFlowSequence;
begin
  AssertEquals('[1,2,3]', Strip(Json('[1, 2, 3]' + #10)));
end;

procedure TComplianceTest.TestFlowMapping;
begin
  AssertEquals('{"a":1,"b":2}', Strip(Json('{a: 1, b: 2}' + #10)));
end;

procedure TComplianceTest.TestLiteralBlock;
begin
  AssertEquals('{"t":"line one\nline two\n"}',
    Strip(Json('t: |' + #10 + '  line one' + #10 + '  line two' + #10)));
end;

procedure TComplianceTest.TestFoldedBlock;
begin
  AssertEquals('{"t":"one two\n"}',
    Strip(Json('t: >' + #10 + '  one' + #10 + '  two' + #10)));
end;

procedure TComplianceTest.TestSingleQuoted;
begin
  AssertEquals('{"t":"it''s"}', Strip(Json('t: ' + '''' + 'it' + ''''''
    + 's' + '''' + #10)));
end;

procedure TComplianceTest.TestDoubleQuotedEscape;
begin
  AssertEquals('{"t":"a\tb"}',
    Strip(Json('t: "a\tb"' + #10)));
end;

procedure TComplianceTest.TestAnchorsAndAliases;
begin
  AssertEquals('{"a":{"x":1},"b":{"x":1}}',
    Strip(Json('a: &n' + #10 + '  x: 1' + #10 + 'b: *n' + #10)));
end;

procedure TComplianceTest.TestMultiDocument;
begin
  AssertEquals('[1,2]', Strip(Json('--- 1' + #10 + '--- 2' + #10)));
end;

procedure TComplianceTest.TestCommentIgnored;
begin
  AssertEquals('{"a":1}',
    Strip(Json('a: 1  # a comment' + #10 + '# a whole-line comment' + #10)));
end;

procedure TComplianceTest.TestCollectionKeyRejected;
begin
  ExpectError('? [a, b]' + #10 + ': v' + #10, 'key');
end;

procedure TComplianceTest.TestBadAliasRejected;
begin
  ExpectError('a: *nope' + #10, 'nope');
end;

initialization
  RegisterTest(TComplianceTest);
end.

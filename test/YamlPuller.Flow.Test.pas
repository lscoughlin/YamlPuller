{**
license: Apache-2.0
copyright: Copyright 2026 Liam Seamus Coughlin
---
Flow collection tests with quoted scalars.
@br
The tests check that a quoted key needs no space after the colon, that a
quoted scalar can hold flow indicators, quotes, and escapes, and that an
apostrophe inside a plain scalar is a normal character.
}
unit YamlPuller.Flow.Test;

{$mode delphi}{$H+}

interface

uses
  SysUtils, fpjson, fpcunit, testregistry, YamlPuller;

type
  TFlowTest = class(TTestCase)
  private
    function Json(const AText: UTF8String): string;
  published
    procedure TestJsonStyleMapping;
    procedure TestNestedJsonStyle;
    procedure TestBracketsInQuotes;
    procedure TestQuoteInsideQuote;
    procedure TestEscapedQuoteKey;
    procedure TestEscapedBackslash;
    procedure TestSingleQuotedEscape;
    procedure TestApostropheInPlainKey;
    procedure TestPlainKeyNeedsSpace;
    procedure TestBlockKeyWithQuotes;
  end;

implementation

function TFlowTest.Json(const AText: UTF8String): string;
var
  P: TYamlPuller;
  D: TJSONData;
begin
  P := TYamlPullerFactory.FromString(AText);
  try
    D := P.Parse;
    try
      Result := D.FormatJSON([foSingleLineArray, foSingleLineObject,
        foSkipWhiteSpace]);
    finally
      D.Free;
    end;
  finally
    P.Free;
  end;
end;

procedure TFlowTest.TestJsonStyleMapping;
begin
  AssertEquals('{"a":1,"b":"x"}', Json('{"a":1,"b":"x"}'));
  AssertEquals('{"a":"x"}', Json('{"a":"x"}'));
end;

procedure TFlowTest.TestNestedJsonStyle;
begin
  AssertEquals('{"a":{"a":1}}', Json('{"a":{"a":1}}'));
  AssertEquals('{"a":[1,{"b":2}]}', Json('{"a":[1,{"b":2}]}'));
end;

procedure TFlowTest.TestBracketsInQuotes;
begin
  AssertEquals('["a[b","c]d","e{f","g}h"]', Json('["a[b","c]d","e{f","g}h"]'));
  AssertEquals('{"k":"[x"}', Json('{"k":"[x"}'));
end;

procedure TFlowTest.TestQuoteInsideQuote;
begin
  AssertEquals('{"a''":"A","b":"B"}', Json('{"a''":"A","b":"B"}'));
  AssertEquals('{"a":"it''s"}', Json('{"a": "it''s"}'));
end;

procedure TFlowTest.TestEscapedQuoteKey;
begin
  AssertEquals('{"\"":"A"}', Json('{"\"":"A"}'));
  AssertEquals('{"a":"x\"y"}', Json('{"a":"x\"y"}'));
end;

procedure TFlowTest.TestEscapedBackslash;
begin
  AssertEquals('{"a\\":"b"}', Json('{"a\\":"b"}'));
end;

procedure TFlowTest.TestSingleQuotedEscape;
begin
  AssertEquals('{"it''s":1}', Json('{''it''''s'': 1}'));
end;

procedure TFlowTest.TestApostropheInPlainKey;
begin
  AssertEquals('{"don''t":1}', Json('don''t: 1' + #10));
end;

procedure TFlowTest.TestPlainKeyNeedsSpace;
begin
  // a plain key keeps the colon rule: no space, no mapping
  AssertEquals('{"a:b":1}', Json('{a:b: 1}'));
end;

procedure TFlowTest.TestBlockKeyWithQuotes;
begin
  AssertEquals('{"a: b":1}', Json('"a: b": 1' + #10));
  AssertEquals('{"x":"it''s: ok"}', Json('x: "it''s: ok"' + #10));
end;

initialization
  RegisterTest(TFlowTest);

end.

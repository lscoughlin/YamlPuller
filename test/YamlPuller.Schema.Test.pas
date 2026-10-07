{**
license: Apache-2.0
copyright: Copyright 2026 Liam Seamus Coughlin
---
Tag resolution and the core schema (plan story S09).
@br
The tests check the core schema, the failsafe schema, the JSON schema, the
explicit tag, the %TAG handle, and the tag failure cases.
}
unit YamlPuller.Schema.Test;

{$mode delphi}{$H+}

interface

uses
  SysUtils, fpcunit, testregistry, YamlPuller.Events, YamlPuller.Schema,
  YamlPuller.Errors;

type
  TSchemaTest = class(TTestCase)
  private
    FResolver: TYamlSchemaResolver;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestNullForms;
    procedure TestBoolForms;
    procedure TestIntForms;
    procedure TestCanonicalInt;
    procedure TestFloatForms;
    procedure TestStringForms;
    procedure TestYaml12BoolOnly;
    procedure TestFailsafeSchema;
    procedure TestJsonSchema;
    procedure TestExplicitTagOverride;
    procedure TestTagHandleExpansion;
    procedure TestUnknownTagKeepsType;
    procedure TestStrictUnknownTagRejected;
    procedure TestYaml11TagRejected;
  end;

implementation

procedure TSchemaTest.SetUp;
begin
  FResolver := TYamlSchemaResolver.Create;
end;

procedure TSchemaTest.TearDown;
begin
  FResolver.Free;
end;

procedure TSchemaTest.TestNullForms;
begin
  AssertEquals(Ord(ystNull), Ord(FResolver.ResolvePlain('')));
  AssertEquals(Ord(ystNull), Ord(FResolver.ResolvePlain('~')));
  AssertEquals(Ord(ystNull), Ord(FResolver.ResolvePlain('null')));
  AssertEquals(Ord(ystNull), Ord(FResolver.ResolvePlain('Null')));
  AssertEquals(Ord(ystNull), Ord(FResolver.ResolvePlain('NULL')));
end;

procedure TSchemaTest.TestBoolForms;
begin
  AssertEquals(Ord(ystBool), Ord(FResolver.ResolvePlain('true')));
  AssertEquals(Ord(ystBool), Ord(FResolver.ResolvePlain('True')));
  AssertEquals(Ord(ystBool), Ord(FResolver.ResolvePlain('TRUE')));
  AssertEquals(Ord(ystBool), Ord(FResolver.ResolvePlain('false')));
end;

procedure TSchemaTest.TestIntForms;
begin
  AssertEquals(Ord(ystInt), Ord(FResolver.ResolvePlain('0')));
  AssertEquals(Ord(ystInt), Ord(FResolver.ResolvePlain('42')));
  AssertEquals(Ord(ystInt), Ord(FResolver.ResolvePlain('-7')));
  AssertEquals(Ord(ystInt), Ord(FResolver.ResolvePlain('+9')));
  AssertEquals(Ord(ystInt), Ord(FResolver.ResolvePlain('0xFF')));
  AssertEquals(Ord(ystInt), Ord(FResolver.ResolvePlain('0o17')));
  // the core schema form [-+]?[0-9]+ permits a leading zero
  AssertEquals(Ord(ystInt), Ord(FResolver.ResolvePlain('007')));
  AssertEquals(Ord(ystInt), Ord(FResolver.ResolvePlain('-007')));
end;

procedure TSchemaTest.TestCanonicalInt;
begin
  // a non-string key uses the canonical decimal text
  AssertEquals('255', string(FResolver.Canonical('0xFF', ystInt)));
  AssertEquals('8', string(FResolver.Canonical('0o10', ystInt)));
  AssertEquals('7', string(FResolver.Canonical('007', ystInt)));
  AssertEquals('-7', string(FResolver.Canonical('-7', ystInt)));
  AssertEquals('null', string(FResolver.Canonical('~', ystNull)));
  AssertEquals('true', string(FResolver.Canonical('TRUE', ystBool)));
end;

procedure TSchemaTest.TestFloatForms;
begin
  AssertEquals(Ord(ystFloat), Ord(FResolver.ResolvePlain('1.5')));
  AssertEquals(Ord(ystFloat), Ord(FResolver.ResolvePlain('-0.25')));
  AssertEquals(Ord(ystFloat), Ord(FResolver.ResolvePlain('1e3')));
  AssertEquals(Ord(ystFloat), Ord(FResolver.ResolvePlain('1.0E-4')));
  AssertEquals(Ord(ystFloat), Ord(FResolver.ResolvePlain('.inf')));
  AssertEquals(Ord(ystFloat), Ord(FResolver.ResolvePlain('-.inf')));
  AssertEquals(Ord(ystFloat), Ord(FResolver.ResolvePlain('.nan')));
end;

procedure TSchemaTest.TestStringForms;
begin
  AssertEquals(Ord(ystStr), Ord(FResolver.ResolvePlain('hello')));
  AssertEquals(Ord(ystStr), Ord(FResolver.ResolvePlain('12abc')));
  AssertEquals(Ord(ystStr), Ord(FResolver.ResolvePlain('1.2.3')));
  AssertEquals(Ord(ystStr), Ord(FResolver.ResolvePlain('0x')));
end;

procedure TSchemaTest.TestYaml12BoolOnly;
begin
  // the decision: y, yes, and on are strings in YAML 1.2
  AssertEquals(Ord(ystStr), Ord(FResolver.ResolvePlain('y')));
  AssertEquals(Ord(ystStr), Ord(FResolver.ResolvePlain('yes')));
  AssertEquals(Ord(ystStr), Ord(FResolver.ResolvePlain('on')));
  AssertEquals(Ord(ystStr), Ord(FResolver.ResolvePlain('n')));
  AssertEquals(Ord(ystStr), Ord(FResolver.ResolvePlain('no')));
  AssertEquals(Ord(ystStr), Ord(FResolver.ResolvePlain('off')));
end;

procedure TSchemaTest.TestFailsafeSchema;
begin
  // the decision: the failsafe schema resolves every plain scalar to a string
  FResolver.Schema := yscFailsafe;
  AssertEquals(Ord(ystStr), Ord(FResolver.ResolvePlain('42')));
  AssertEquals(Ord(ystStr), Ord(FResolver.ResolvePlain('true')));
  AssertEquals(Ord(ystStr), Ord(FResolver.ResolvePlain('~')));
end;

procedure TSchemaTest.TestJsonSchema;
begin
  // the decision: the JSON schema is a subset of the core schema
  FResolver.Schema := yscJson;
  AssertEquals(Ord(ystNull), Ord(FResolver.ResolvePlain('null')));
  AssertEquals(Ord(ystBool), Ord(FResolver.ResolvePlain('true')));
  AssertEquals(Ord(ystInt), Ord(FResolver.ResolvePlain('42')));
  AssertEquals(Ord(ystFloat), Ord(FResolver.ResolvePlain('1.5')));
  // a JSON form that the core schema accepts is not a JSON form here
  AssertEquals(Ord(ystStr), Ord(FResolver.ResolvePlain('0xFF')));
  AssertEquals(Ord(ystStr), Ord(FResolver.ResolvePlain('True')));
end;

procedure TSchemaTest.TestExplicitTagOverride;
var
  T: TYamlScalarType;
begin
  // the decision: an explicit tag overrides the schema
  AssertTrue('the str tag applies', FResolver.ApplyTag('!!str', T, 1, 1));
  AssertEquals(Ord(ystStr), Ord(T));
  AssertTrue('the int tag applies', FResolver.ApplyTag('!!int', T, 1, 1));
  AssertEquals(Ord(ystInt), Ord(T));
  AssertTrue('the null tag applies', FResolver.ApplyTag('!!null', T, 1, 1));
  AssertEquals(Ord(ystNull), Ord(T));
end;

procedure TSchemaTest.TestTagHandleExpansion;
var
  T: TYamlScalarType;
begin
  // the decision: %TAG expands a handle before the comparison
  AssertEquals('tag:yaml.org,2002:int', FResolver.Handles.Expand('!!int'));
  AssertEquals('!foo', FResolver.Handles.Expand('!foo'));
  FResolver.Handles.Define('!e!', 'tag:example.com,2026:');
  AssertEquals('tag:example.com,2026:thing',
    FResolver.Handles.Expand('!e!thing'));
  // the new prefix is not a core tag, so the tag is not known
  AssertFalse('the new tag is not known',
    FResolver.ApplyTag('!e!thing', T, 1, 1));
end;

procedure TSchemaTest.TestUnknownTagKeepsType;
var
  T: TYamlScalarType;
begin
  // the decision: an unknown local tag keeps the underlying node type
  AssertFalse('the tag is not known',
    FResolver.ApplyTag('!foo', T, 1, 1));
end;

procedure TSchemaTest.TestStrictUnknownTagRejected;
var
  T: TYamlScalarType;
begin
  FResolver.Strict := True;
  try
    FResolver.ApplyTag('!foo', T, 3, 5);
    Fail('the unknown tag did not raise an error');
  except
    on E: EYamlError do
    begin
      AssertEquals('the line is reported', 3, E.Line);
      AssertEquals('the column is reported', 5, E.Column);
    end;
  end;
end;

procedure TSchemaTest.TestYaml11TagRejected;
var
  T: TYamlScalarType;
begin
  // the decision: a YAML 1.1-only tag raises an error
  try
    FResolver.ApplyTag('!!timestamp', T, 4, 2);
    Fail('the YAML 1.1 tag did not raise an error');
  except
    on E: EYamlError do
    begin
      AssertTrue('the message names the tag', Pos('timestamp', E.Message) > 0);
      AssertEquals('the line is reported', 4, E.Line);
    end;
  end;
end;

initialization
  RegisterTest(TSchemaTest);
end.

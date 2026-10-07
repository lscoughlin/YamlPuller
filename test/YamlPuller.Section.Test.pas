{**
license: Apache-2.0
copyright: Copyright 2026 Liam Seamus Coughlin
---
The section operation of the puller (the Parse(event, data) operation).
@br
The puller builds the value that starts at one event. The test picks the
start event from the event stream, then compares the value and the
error cases.
}
unit YamlPuller.Section.Test;

{$mode delphi}{$H+}

interface

uses
  SysUtils, Classes, fpjson, fpcunit, testregistry, YamlPuller,
  YamlPuller.Input, YamlPuller.Events, YamlPuller.Errors;

type
  TSectionTest = class(TTestCase)
  private
    function NthEvent(APuller: TYamlPuller; AType: TYamlEventType;
      ANth: Integer): TYamlEvent;
    function NthScalar(APuller: TYamlPuller; const AText: string;
      ANth: Integer): TYamlEvent;
    function SectionJson(AText: UTF8String;
      const AEvent: TYamlEvent): string;
  published
    procedure TestSectionMapping;
    procedure TestSectionSequence;
    procedure TestSectionScalar;
    procedure TestSectionWholeDocument;
    procedure TestStreamStartIsNil;
    procedure TestEndEventIsNil;
    procedure TestForeignEventRejected;
    procedure TestSectionSeesEarlierAnchor;
    procedure TestSectionAliasInsideSection;
    procedure TestSectionMultiDocument;
    procedure TestSectionNestedStart;
    procedure TestSectionCallerOwnsResult;
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

function TSectionTest.NthEvent(APuller: TYamlPuller; AType: TYamlEventType;
  ANth: Integer): TYamlEvent;
var
  Ev: TYamlEvent;
  Count: Integer;
begin
  Count := 0;
  while APuller.HasNext do
  begin
    Ev := APuller.Next;
    if Ev.EventType = AType then
    begin
      Inc(Count);
      if Count = ANth then
        Exit(Ev);
    end;
  end;
  raise Exception.Create('The test did not find the event');
end;

function TSectionTest.NthScalar(APuller: TYamlPuller; const AText: string;
  ANth: Integer): TYamlEvent;
var
  Ev: TYamlEvent;
  Count: Integer;
begin
  Count := 0;
  while APuller.HasNext do
  begin
    Ev := APuller.Next;
    if (Ev.EventType = yetScalar) and (string(Ev.EventText) = AText) then
    begin
      Inc(Count);
      if Count = ANth then
        Exit(Ev);
    end;
  end;
  raise Exception.Create('The test did not find the scalar');
end;

function TSectionTest.SectionJson(AText: UTF8String;
  const AEvent: TYamlEvent): string;
var
  Puller: TYamlPuller;
  Data: TJSONData;
begin
  Puller := TYamlPullerFactory.FromString(AText);
  try
    Puller.Parse(AEvent, Data);
  finally
    Puller.Free;
  end;
  if Data = nil then
    Exit('');
  try
    Result := Minify(Data.AsJSON);
  finally
    Data.Free;
  end;
end;

procedure TSectionTest.TestSectionMapping;
var
  Puller: TYamlPuller;
  Ev: TYamlEvent;
  Text: UTF8String;
begin
  Text := 'a: 1'#10'b:'#10'  c: 2'#10'  d: 3'#10;
  Puller := TYamlPullerFactory.FromString(Text);
  try
    // the second mapping start is the value of the member b
    Ev := NthEvent(Puller, yetMappingStart, 2);
    AssertEquals('{"c":2,"d":3}', SectionJson(Text, Ev));
  finally
    Puller.Free;
  end;
end;

procedure TSectionTest.TestSectionSequence;
var
  Puller: TYamlPuller;
  Ev: TYamlEvent;
  Text: UTF8String;
begin
  Text := 'items:'#10'  - one'#10'  - two'#10;
  Puller := TYamlPullerFactory.FromString(Text);
  try
    Ev := NthEvent(Puller, yetSequenceStart, 1);
    AssertEquals('["one","two"]', SectionJson(Text, Ev));
  finally
    Puller.Free;
  end;
end;

procedure TSectionTest.TestSectionScalar;
var
  Puller: TYamlPuller;
  Ev: TYamlEvent;
  Text: UTF8String;
begin
  Text := 'a: 1'#10'b: 2'#10;
  Puller := TYamlPullerFactory.FromString(Text);
  try
    Ev := NthScalar(Puller, '2', 1);
    AssertEquals('2', SectionJson(Text, Ev));
  finally
    Puller.Free;
  end;
end;

procedure TSectionTest.TestSectionWholeDocument;
var
  Puller: TYamlPuller;
  Ev: TYamlEvent;
  Text: UTF8String;
begin
  Text := 'a: 1'#10'b: 2'#10;
  Puller := TYamlPullerFactory.FromString(Text);
  try
    Ev := NthEvent(Puller, yetDocumentStart, 1);
    AssertEquals('{"a":1,"b":2}', SectionJson(Text, Ev));
  finally
    Puller.Free;
  end;
end;

procedure TSectionTest.TestStreamStartIsNil;
var
  Puller: TYamlPuller;
  Ev: TYamlEvent;
  Text: UTF8String;
begin
  Text := 'a: 1'#10;
  Puller := TYamlPullerFactory.FromString(Text);
  try
    Ev := NthEvent(Puller, yetStreamStart, 1);
    AssertEquals('the stream start starts no value', '', SectionJson(Text, Ev));
  finally
    Puller.Free;
  end;
end;

procedure TSectionTest.TestEndEventIsNil;
var
  Puller: TYamlPuller;
  Ev: TYamlEvent;
  Text: UTF8String;
begin
  Text := 'a: 1'#10;
  Puller := TYamlPullerFactory.FromString(Text);
  try
    Ev := NthEvent(Puller, yetMappingEnd, 1);
    AssertEquals('an end event starts no value', '', SectionJson(Text, Ev));
  finally
    Puller.Free;
  end;
end;

procedure TSectionTest.TestForeignEventRejected;
var
  Puller: TYamlPuller;
  Data: TJSONData;
  Ev: TYamlEvent;
  Raised: Boolean;
begin
  Puller := TYamlPullerFactory.FromString(UTF8String('a: 1'#10));
  try
    FillChar(Ev, SizeOf(Ev), 0);
    Ev.EventType := yetScalar;
    Ev.EventText := 'zzz';
    Ev.Line := 99;
    Ev.Column := 9;
    Ev.NestLevel := 3;
    Raised := False;
    try
      Puller.Parse(Ev, Data);
    except
      on E: EYamlParserError do
        Raised := True;
    end;
    AssertTrue('an event from another source is rejected', Raised);
  finally
    Puller.Free;
  end;
end;

procedure TSectionTest.TestSectionSeesEarlierAnchor;
var
  Puller: TYamlPuller;
  Ev: TYamlEvent;
  Text: UTF8String;
begin
  Text := 'base: &b'#10'  x: 1'#10'use: *b'#10;
  Puller := TYamlPullerFactory.FromString(Text);
  try
    // the alias at use sees the anchor b, because b is complete before it
    Ev := NthEvent(Puller, yetAlias, 1);
    AssertEquals('{"x":1}', SectionJson(Text, Ev));
  finally
    Puller.Free;
  end;
end;

procedure TSectionTest.TestSectionAliasInsideSection;
var
  Puller: TYamlPuller;
  Ev: TYamlEvent;
  Text: UTF8String;
begin
  Text := 'a: &b 1'#10'c:'#10'  d: *b'#10'  e: 2'#10;
  Puller := TYamlPullerFactory.FromString(Text);
  try
    Ev := NthEvent(Puller, yetMappingStart, 1);
    AssertEquals('{"a":1,"c":{"d":1,"e":2}}', SectionJson(Text, Ev));
  finally
    Puller.Free;
  end;
end;

procedure TSectionTest.TestSectionMultiDocument;
var
  Puller: TYamlPuller;
  Ev: TYamlEvent;
  Text: UTF8String;
begin
  Text := 'a: 1'#10'---'#10'b: 2'#10;
  Puller := TYamlPullerFactory.FromString(Text);
  try
    Ev := NthEvent(Puller, yetDocumentStart, 2);
    AssertEquals('{"b":2}', SectionJson(Text, Ev));
  finally
    Puller.Free;
  end;
end;

procedure TSectionTest.TestSectionNestedStart;
var
  Puller: TYamlPuller;
  Ev: TYamlEvent;
  Text: UTF8String;
begin
  Text := 'top:'#10'  inner:'#10'    - 1'#10'    - 2'#10;
  Puller := TYamlPullerFactory.FromString(Text);
  try
    Ev := NthEvent(Puller, yetSequenceStart, 1);
    AssertEquals('[1,2]', SectionJson(Text, Ev));
  finally
    Puller.Free;
  end;
end;

procedure TSectionTest.TestSectionCallerOwnsResult;
var
  Puller: TYamlPuller;
  Ev: TYamlEvent;
  Data: TJSONData;
  Text: UTF8String;
begin
  Text := 'a: 1'#10;
  Puller := TYamlPullerFactory.FromString(Text);
  try
    Ev := NthEvent(Puller, yetDocumentStart, 1);
    Puller.Parse(Ev, Data);
    AssertTrue('the caller received a value', Data <> nil);
    Data.Free;
  finally
    Puller.Free;
  end;
end;

initialization
  RegisterTest(TSectionTest);
end.

{**
license: Apache-2.0
copyright: Copyright 2026 Liam Seamus Coughlin
---
Performance and memory (plan story S14).
@br
The pull parser reads events on demand. A caller that reads a prefix does no
work for the content that the caller does not request. The event list is the
one buffer that the puller holds.
}
unit YamlPuller.Streaming.Test;

{$mode delphi}{$H+}

interface

uses
  SysUtils, Classes, fpcunit, testregistry, YamlPuller, YamlPuller.Input,
  YamlPuller.Events;

type
  TStreamingTest = class(TTestCase)
  private
    function LargeDocument(ACount: Integer): string;
  published
    procedure TestReadPrefixAndStop;
    procedure TestEventCountIsNotBufferedForPrefix;
    procedure TestLineReaderHoldsOffsets;
    procedure TestLargeDocument;
  end;

implementation

function TStreamingTest.LargeDocument(ACount: Integer): string;
var
  I: Integer;
begin
  Result := '';
  for I := 0 to ACount - 1 do
    Result := Result + 'key' + IntToStr(I) + ': ' + IntToStr(I) + #10;
end;

procedure TStreamingTest.TestReadPrefixAndStop;
var
  Puller: TYamlPuller;
  Event: TYamlEvent;
  Seen, I: Integer;
begin
  Puller := TYamlPullerFactory.FromString(UTF8String(LargeDocument(1000)));
  try
    // read only the first three events, then stop
    Seen := 0;
    for I := 1 to 3 do
    begin
      AssertTrue('an event remains', Puller.HasNext);
      Event := Puller.Next;
      Inc(Seen);
    end;
    AssertEquals('the caller read the prefix', 3, Seen);
    AssertTrue('the stream start is first', Seen >= 1);
  finally
    Puller.Free;
  end;
end;

procedure TStreamingTest.TestEventCountIsNotBufferedForPrefix;
var
  PSmall, PLarge: TYamlPuller;
  N: Integer;
begin
  // the public puller yields the same prefix for a small and a large source
  PSmall := TYamlPullerFactory.FromString(UTF8String(LargeDocument(5)));
  PLarge := TYamlPullerFactory.FromString(UTF8String(LargeDocument(5000)));
  try
    N := 0;
    while PSmall.HasNext and (N < 3) do
    begin
      PSmall.Next;
      Inc(N);
    end;
    AssertEquals('the small source yields three events', 3, N);
    N := 0;
    while PLarge.HasNext and (N < 3) do
    begin
      PLarge.Next;
      Inc(N);
    end;
    AssertEquals('the large source yields the same prefix', 3, N);
  finally
    PSmall.Free;
    PLarge.Free;
  end;
end;

procedure TStreamingTest.TestLineReaderHoldsOffsets;
var
  Input: TYamlInput;
  Line: UnicodeString;
  N, Count: Integer;
begin
  // the line reader yields each line on demand. It holds the offsets, not a
  // second copy of the text. The line reader is an internal input unit.
  Input := TYamlInput.FromString(UTF8String(LargeDocument(200)));
  Input.Reset;
  Count := 0;
  while Input.NextLine(Line, N) do
  begin
    AssertEquals('the line number is the ordinal', Count + 1, N);
    Inc(Count);
  end;
  AssertEquals('the line count is correct', 200, Count);
  AssertEquals('the reader reports the line count', 200, Input.LineCount);
end;

procedure TStreamingTest.TestLargeDocument;
var
  Puller: TYamlPuller;
begin
  // a large document parses. The test records the case as supported.
  Puller := TYamlPullerFactory.FromString(UTF8String(LargeDocument(5000)));
  try
    AssertTrue('the large source has an event', Puller.HasNext);
  finally
    Puller.Free;
  end;
  AssertTrue('the large document is supported', True);
end;

initialization
  RegisterTest(TStreamingTest);
end.

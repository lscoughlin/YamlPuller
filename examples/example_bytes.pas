{**
license: Apache-2.0
copyright: Copyright 2026 Liam Seamus Coughlin
---
Example: parse a byte array (plan story S15).
@br
The program creates a puller from a byte array with the FromBytes method. The
byte array holds a UTF-8 document with a byte order mark.
}
program example_bytes;

{$mode delphi}{$H+}

uses
  SysUtils, fpjson, YamlPuller;

var
  Puller: TYamlPuller;
  Data: TJSONData;
  Bytes: TBytes;
  S: UTF8String;
  I: Integer;

begin
  S := 'key: value' + #10;
  SetLength(Bytes, 3 + Length(S));
  Bytes[0] := $EF; // the UTF-8 byte order mark
  Bytes[1] := $BB;
  Bytes[2] := $BF;
  for I := 1 to Length(S) do
    Bytes[2 + I] := Ord(S[I]);
  Puller := TYamlPullerFactory.FromBytes(Bytes);
  try
    Data := Puller.Parse;
    try
      WriteLn(Data.AsJSON);
    finally
      Data.Free;
    end;
  finally
    Puller.Free;
  end;
end.

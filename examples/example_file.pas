{**
license: Apache-2.0
copyright: Copyright 2026 Liam Seamus Coughlin
---
Example: parse a file (plan story S15).
@br
The program creates a puller from an open file handle with the FromFile
method. The program parses the file and writes the JSON value. The program
takes the file name from the command line, or uses a temporary file.
}
program example_file;

{$mode delphi}{$H+}

uses
  SysUtils, fpjson, YamlPuller;

var
  FileName: string;
  Handle: THandle;
  Puller: TYamlPuller;
  Data: TJSONData;
  F: Text;

begin
  if ParamCount >= 1 then
    FileName := ParamStr(1)
  else
    FileName := GetTempDir(False) + 'example_file.yaml';
  if ParamCount < 1 then
  begin
    Assign(F, FileName);
    Rewrite(F);
    WriteLn(F, 'host: localhost');
    WriteLn(F, 'port: 8080');
    Close(F);
  end;
  Handle := FileOpen(FileName, fmOpenRead);
  if Handle = THandle(-1) then
  begin
    WriteLn('cannot open ', FileName);
    Halt(1);
  end;
  try
    Puller := TYamlPullerFactory.FromFile(Handle);
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
  finally
    FileClose(Handle);
  end;
end.

{**
license: Apache-2.0
copyright: Copyright 2026 Liam Seamus Coughlin
---
Exception hierarchy for YamlPuller (plan story S12).
@br
Every error names the cause and the position; the message uses
  ASD-STE100 Simplified Technical English.
}
unit YamlPuller.Errors;

{$mode delphi}{$H+}

interface

uses
  SysUtils;

type
  /// base class for every YamlPuller error
  EYamlError = class(Exception)
  private
    FLine: Integer;
    FColumn: Integer;
  public
    constructor Create(const AMessage: string; ALine, AColumn: Integer); overload;
    constructor Create(const AMessage: string); overload;
    /// the 1-based line number, or 0 when the error has no position
    property Line: Integer read FLine;
    /// the 1-based column number, or 0 when the error has no position
    property Column: Integer read FColumn;
    /// the position text, as "line L, column C"
    function Position: string;
  end;

  /// an error from the scanner
  EYamlScannerError = class(EYamlError);

  /// an error from the parser or the JSON bridge
  EYamlParserError = class(EYamlError);

implementation

constructor EYamlError.Create(const AMessage: string; ALine, AColumn: Integer);
begin
  FLine := ALine;
  FColumn := AColumn;
  if (ALine > 0) and (AColumn > 0) then
    inherited Create(Format('%s at line %d, column %d', [AMessage, ALine, AColumn]))
  else if ALine > 0 then
    inherited Create(Format('%s at line %d', [AMessage, ALine]))
  else
    inherited Create(AMessage);
end;

constructor EYamlError.Create(const AMessage: string);
begin
  Create(AMessage, 0, 0);
end;

function EYamlError.Position: string;
begin
  Result := Format('line %d, column %d', [FLine, FColumn]);
end;

end.

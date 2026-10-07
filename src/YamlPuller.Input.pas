{**
license: Apache-2.0
copyright: Copyright 2026 Liam Seamus Coughlin
---
Input layer: bytes to characters (plan story S01).
@br
Four data sources, BOM detection, BOM-less detection, line-break
  normalization, and a lazy line reader with a running line number.
TYamlLineReader marks the pull boundary: the scanner asks for one physical
  line at a time, so the puller reads only the lines that it needs.
}
unit YamlPuller.Input;

{$mode delphi}{$H+}

interface

uses
  SysUtils, Classes, YamlPuller.Errors;

type
  TYamlInput = class;

  /// a lazy line reader. The reader yields one physical line at a time. The
  /// puller uses one reader for the whole stream, so the puller reads only
  /// the lines that it needs.
  TYamlLineReader = class
  private
    FInput: TYamlInput;
    FHasPushBack: Boolean;
    FPushBack: UnicodeString;
    FPushBackNo: Integer;
  public
    constructor Create(AInput: TYamlInput);
    /// the next line and its 1-based number. The reader advances.
    function NextLine(out ALine: UnicodeString; out ANumber: Integer): Boolean;
    /// put one line back for the next read
    procedure PushBack(const ALine: UnicodeString; ANumber: Integer);
  end;

  /// the input layer for one document source
  TYamlInput = class
  private
    FText: UnicodeString;
    FStarts: TArray<Integer>;
    FLineIndex: Integer;
    procedure SplitLines;
  public
    constructor Create(const AText: UnicodeString);
    /// read from a file handle. The caller keeps ownership of the handle.
    class function FromFile(const AHandle: THandle): TYamlInput;
    /// read from a stream, from the current position to the end
    class function FromStream(AStream: TStream): TYamlInput;
    /// read from a byte buffer
    class function FromBytes(const ABytes: TBytes): TYamlInput;
    /// read from a UTF-8 string
    class function FromString(const AText: UTF8String): TYamlInput;
    /// read from text that is already decoded and normalized
    class function FromText(const AText: UnicodeString): TYamlInput;
    /// decode a byte buffer to normalized characters
    class function Decode(const ABytes: TBytes): UnicodeString;
    /// true when the line reader is at the end
    function Eof: Boolean;
    /// the next line and its 1-based number. The reader advances.
    function NextLine(out ALine: UnicodeString; out ANumber: Integer): Boolean;
    /// the next line without a read. The reader does not advance.
    function PeekLine(out ALine: UnicodeString; out ANumber: Integer): Boolean;
    /// set the line reader to the first line
    procedure Reset;
    /// the whole normalized text
    property Text: UnicodeString read FText;
    /// the number of lines
    function LineCount: Integer;
  end;

implementation

const
  BOM_UTF8: array[0..2] of Byte = ($EF, $BB, $BF);

function BytesAsUTF8(const ABytes: TBytes; AStart, ACount: Integer): UTF8String;
begin
  SetLength(Result, ACount);
  if ACount > 0 then
    Move(ABytes[AStart], Result[1], ACount);
end;

function NormalizeBreaks(const S: UnicodeString): UnicodeString;
var
  I, N: Integer;
  Buf: UnicodeString;
begin
  N := Length(S);
  SetLength(Buf, N);
  I := 1;
  N := 0;
  while I <= Length(S) do
  begin
    if S[I] = #13 then
    begin
      Inc(N);
      Buf[N] := #10;
      if (I < Length(S)) and (S[I + 1] = #10) then
        Inc(I);
    end
    else
    begin
      Inc(N);
      Buf[N] := S[I];
    end;
    Inc(I);
  end;
  SetLength(Buf, N);
  Result := Buf;
end;

function DecodeUTF32(const ABytes: TBytes; AStart, ACount: Integer;
  ABigEndian: Boolean): UnicodeString;
var
  I, CP, N: Integer;
  B0, B1, B2, B3: LongWord;
  Buf: UnicodeString;
begin
  SetLength(Buf, ACount div 4 * 2 + 2);
  I := AStart;
  N := 0;
  while I + 3 <= AStart + ACount - 1 do
  begin
    if ABigEndian then
    begin
      B0 := ABytes[I]; B1 := ABytes[I + 1]; B2 := ABytes[I + 2]; B3 := ABytes[I + 3];
    end
    else
    begin
      B0 := ABytes[I + 3]; B1 := ABytes[I + 2]; B2 := ABytes[I + 1]; B3 := ABytes[I];
    end;
    CP := Integer((B0 shl 24) or (B1 shl 16) or (B2 shl 8) or B3);
    if CP < $10000 then
    begin
      Inc(N);
      Buf[N] := WideChar(CP);
    end
    else
    begin
      CP := CP - $10000;
      Inc(N);
      Buf[N] := WideChar($D800 or (CP shr 10));
      Inc(N);
      Buf[N] := WideChar($DC00 or (CP and $3FF));
    end;
    Inc(I, 4);
  end;
  SetLength(Buf, N);
  Result := Buf;
end;

function DecodeUTF16(const ABytes: TBytes; AStart, ACount: Integer;
  ABigEndian: Boolean): UnicodeString;
var
  I, N: Integer;
  W: Word;
  Buf: UnicodeString;
begin
  SetLength(Buf, ACount div 2 + 1);
  I := AStart;
  N := 0;
  while I + 1 <= AStart + ACount - 1 do
  begin
    if ABigEndian then
      W := (Word(ABytes[I]) shl 8) or Word(ABytes[I + 1])
    else
      W := Word(ABytes[I]) or (Word(ABytes[I + 1]) shl 8);
    Inc(N);
    Buf[N] := WideChar(W);
    Inc(I, 2);
  end;
  SetLength(Buf, N);
  Result := Buf;
end;

class function TYamlInput.Decode(const ABytes: TBytes): UnicodeString;
var
  N: Integer;
begin
  N := Length(ABytes);
  if N = 0 then
    Exit('');
  if (N >= 4) and (ABytes[0] = $FF) and (ABytes[1] = $FE)
    and (ABytes[2] = 0) and (ABytes[3] = 0) then
    Result := DecodeUTF32(ABytes, 4, N - 4, False)
  else if (N >= 4) and (ABytes[0] = 0) and (ABytes[1] = 0)
    and (ABytes[2] = $FE) and (ABytes[3] = $FF) then
    Result := DecodeUTF32(ABytes, 4, N - 4, True)
  else if (N >= 3) and (ABytes[0] = $EF) and (ABytes[1] = $BB) and (ABytes[2] = $BF) then
    Result := UTF8Decode(BytesAsUTF8(ABytes, 3, N - 3))
  else if (N >= 2) and (ABytes[0] = $FF) and (ABytes[1] = $FE) then
    Result := DecodeUTF16(ABytes, 2, N - 2, False)
  else if (N >= 2) and (ABytes[0] = $FE) and (ABytes[1] = $FF) then
    Result := DecodeUTF16(ABytes, 2, N - 2, True)
  else if (N >= 2) and (ABytes[0] = 0) then
    Result := DecodeUTF16(ABytes, 0, N, True)
  else if (N >= 2) and (ABytes[1] = 0) then
    Result := DecodeUTF16(ABytes, 0, N, False)
  else
    Result := UTF8Decode(BytesAsUTF8(ABytes, 0, N));
  Result := NormalizeBreaks(Result);
end;

constructor TYamlInput.Create(const AText: UnicodeString);
begin
  FText := AText;
  FLineIndex := 0;
  FStarts := nil;
end;

procedure TYamlInput.SplitLines;
var
  I, N: Integer;
begin
  if Length(FStarts) > 0 then
    Exit;
  SetLength(FStarts, 1);
  FStarts[0] := 1;
  N := 1;
  for I := 1 to Length(FText) do
    if FText[I] = #10 then
      if I < Length(FText) then
      begin
        SetLength(FStarts, N + 1);
        FStarts[N] := I + 1;
        Inc(N);
      end;
end;

function TYamlInput.LineCount: Integer;
begin
  SplitLines;
  Result := Length(FStarts);
end;

class function TYamlInput.FromBytes(const ABytes: TBytes): TYamlInput;
begin
  Result := TYamlInput.Create(Decode(ABytes));
end;

class function TYamlInput.FromString(const AText: UTF8String): TYamlInput;
var
  B: TBytes;
begin
  SetLength(B, Length(AText));
  if Length(AText) > 0 then
    Move(AText[1], B[0], Length(AText));
  Result := TYamlInput.Create(Decode(B));
end;

class function TYamlInput.FromText(const AText: UnicodeString): TYamlInput;
begin
  Result := TYamlInput.Create(AText);
end;

class function TYamlInput.FromStream(AStream: TStream): TYamlInput;
var
  B: TBytes;
  Count: Int64;
begin
  Count := AStream.Size - AStream.Position;
  if Count < 0 then
    Count := 0;
  SetLength(B, Count);
  if Count > 0 then
    AStream.ReadBuffer(B[0], Count);
  Result := TYamlInput.Create(Decode(B));
end;

class function TYamlInput.FromFile(const AHandle: THandle): TYamlInput;
var
  S: THandleStream;
begin
  S := THandleStream.Create(AHandle);
  try
    Result := FromStream(S);
  finally
    S.Free;
  end;
end;

function TYamlInput.Eof: Boolean;
begin
  SplitLines;
  Result := FLineIndex >= Length(FStarts);
end;

procedure TYamlInput.Reset;
begin
  FLineIndex := 0;
end;

function TYamlInput.PeekLine(out ALine: UnicodeString; out ANumber: Integer): Boolean;
var
  Start, Stop: Integer;
begin
  SplitLines;
  if FLineIndex >= Length(FStarts) then
  begin
    ALine := '';
    ANumber := 0;
    Exit(False);
  end;
  Start := FStarts[FLineIndex];
  if FLineIndex + 1 < Length(FStarts) then
    Stop := FStarts[FLineIndex + 1] - 2
  else
  begin
    Stop := Length(FText);
    // the source ends with a line break: the break is not part of the line
    if (Stop >= 1) and (FText[Stop] = #10) then
      Dec(Stop);
  end;
  if Stop >= Start then
    ALine := Copy(FText, Start, Stop - Start + 1)
  else
    ALine := '';
  ANumber := FLineIndex + 1;
  Result := True;
end;

function TYamlInput.NextLine(out ALine: UnicodeString; out ANumber: Integer): Boolean;
begin
  Result := PeekLine(ALine, ANumber);
  if Result then
    Inc(FLineIndex);
end;

{ TYamlLineReader }

constructor TYamlLineReader.Create(AInput: TYamlInput);
begin
  inherited Create;
  FInput := AInput;
  FHasPushBack := False;
end;

function TYamlLineReader.NextLine(out ALine: UnicodeString;
  out ANumber: Integer): Boolean;
begin
  if FHasPushBack then
  begin
    ALine := FPushBack;
    ANumber := FPushBackNo;
    FHasPushBack := False;
    Exit(True);
  end;
  Result := FInput.NextLine(ALine, ANumber);
end;

procedure TYamlLineReader.PushBack(const ALine: UnicodeString;
  ANumber: Integer);
begin
  FPushBack := ALine;
  FPushBackNo := ANumber;
  FHasPushBack := True;
end;

end.

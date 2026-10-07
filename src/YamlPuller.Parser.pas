{**
license: Apache-2.0
copyright: Copyright 2026 Liam Seamus Coughlin
---
Parser: event state machine (plan story S08).
@br
The parser reads the token list and produces the event list. The parser
  resolves the scalar type, attaches the anchor and the tag to the node
  event, and pairs each start event with an end event.
}
unit YamlPuller.Parser;

{$mode delphi}{$H+}

interface

uses
  SysUtils, YamlPuller.Events, YamlPuller.Errors, YamlPuller.Schema,
  YamlPuller.Scanner.Core;

type
  /// the parser. One instance parses one token list.
  TYamlParser = class
  private
    FTokens: TArray<TYamlToken>;
    FEvents: array of TYamlEventEx;
    FSchema: TYamlSchemaResolver;
    FLevel: Integer;
    FInDocument: Boolean;
    FStreamStarted: Boolean;
    FPendingAnchor: UTF8String;
    FPendingTag: UTF8String;
    procedure Emit(const AEvent: TYamlEventEx);
    procedure Reset;
    procedure ParseTokens(const ATokens: TArray<TYamlToken>);
  public
    constructor Create;
    destructor Destroy; override;
    /// parse the token list and return the event list
    function Parse(const ATokens: TArray<TYamlToken>): TArray<TYamlEventEx>;
    /// parse the tokens of one document region. The parser keeps the level
    /// and the pending properties across the calls. The function returns
    /// the events of this region.
    function ParseDocumentTokens(const ATokens: TArray<TYamlToken>)
      : TArray<TYamlEventEx>;
    /// close the open document and the stream and return the final events
    function ParseStreamEnd: TArray<TYamlEventEx>;
    property Schema: TYamlSchemaResolver read FSchema;
  end;

implementation

constructor TYamlParser.Create;
begin
  inherited Create;
  FSchema := TYamlSchemaResolver.Create;
end;

destructor TYamlParser.Destroy;
begin
  FSchema.Free;
  inherited Destroy;
end;

procedure TYamlParser.Emit(const AEvent: TYamlEventEx);
begin
  SetLength(FEvents, Length(FEvents) + 1);
  FEvents[High(FEvents)] := AEvent;
end;

function TYamlParser.Parse(const ATokens: TArray<TYamlToken>): TArray<TYamlEventEx>;
var
  I, From: Integer;
begin
  Reset;
  FLevel := 0;
  FInDocument := False;
  FPendingAnchor := '';
  FPendingTag := '';
  SetLength(FEvents, 0);
  Emit(MakeEvent(yetStreamStart, '', 0, 0, 0));
  FStreamStarted := True;
  ParseTokens(ATokens);
  if FInDocument then
  begin
    Emit(MakeEvent(yetDocumentEnd, '', FLevel, 0, 0));
    FInDocument := False;
  end;
  Emit(MakeEvent(yetStreamEnd, '', 0, 0, 0));
  From := 0;
  SetLength(Result, Length(FEvents));
  for I := From to High(FEvents) do
    Result[I] := FEvents[I];
end;

procedure TYamlParser.Reset;
begin
  FLevel := 0;
  FInDocument := False;
  FStreamStarted := False;
  FPendingAnchor := '';
  FPendingTag := '';
  SetLength(FEvents, 0);
end;

procedure TYamlParser.ParseTokens(const ATokens: TArray<TYamlToken>);
var
  I: Integer;
  Tok: TYamlToken;
  Ev: TYamlEventEx;
  SType: TYamlScalarType;
  IsPlain: Boolean;
begin
  FTokens := ATokens;
  for I := 0 to High(ATokens) do
  begin
    Tok := ATokens[I];
    case Tok.Kind of
      ytkAnchor:
        FPendingAnchor := UTF8Encode(Tok.Text);
      ytkTag:
        FPendingTag := UTF8Encode(Tok.Text);
      ytkDocumentStart:
        begin
          if FInDocument then
            Emit(MakeEvent(yetDocumentEnd, '', FLevel, Tok.Line, Tok.Column));
          Emit(MakeEvent(yetDocumentStart, '', FLevel, Tok.Line, Tok.Column));
          FInDocument := True;
        end;
      ytkDocumentEnd:
        begin
          Emit(MakeEvent(yetDocumentEnd, '', FLevel, Tok.Line, Tok.Column));
          FInDocument := False;
        end;
      ytkMapStart, ytkFlowMapStart:
        begin
          Ev := MakeEvent(yetMappingStart, '', FLevel, Tok.Line, Tok.Column);
          Ev.Anchor := FPendingAnchor;
          Ev.Tag := FPendingTag;
          FPendingAnchor := '';
          FPendingTag := '';
          Emit(Ev);
          Inc(FLevel);
        end;
      ytkMapEnd, ytkFlowMapEnd:
        begin
          Dec(FLevel);
          Emit(MakeEvent(yetMappingEnd, '', FLevel, Tok.Line, Tok.Column));
        end;
      ytkSeqStart, ytkFlowSeqStart:
        begin
          Ev := MakeEvent(yetSequenceStart, '', FLevel, Tok.Line, Tok.Column);
          Ev.Anchor := FPendingAnchor;
          Ev.Tag := FPendingTag;
          FPendingAnchor := '';
          FPendingTag := '';
          Emit(Ev);
          Inc(FLevel);
        end;
      ytkSeqEnd, ytkFlowSeqEnd:
        begin
          Dec(FLevel);
          Emit(MakeEvent(yetSequenceEnd, '', FLevel, Tok.Line, Tok.Column));
        end;
      ytkScalar:
        begin
          IsPlain := Tok.ScalarStyle = yssPlain;
          if FPendingTag <> '' then
          begin
            if not FSchema.ApplyTag(FPendingTag, SType, Tok.Line, Tok.Column) then
            begin
              // an unknown tag: keep the underlying node type
              if IsPlain then
                SType := FSchema.ResolvePlain(UTF8Encode(Tok.Text))
              else
                SType := ystStr;
            end;
          end
          else if IsPlain then
            SType := FSchema.ResolvePlain(UTF8Encode(Tok.Text))
          else
            SType := ystStr;
          Ev := MakeEvent(yetScalar, UTF8Encode(Tok.Text), FLevel,
            Tok.Line, Tok.Column);
          Ev.ScalarType := SType;
          Ev.Anchor := FPendingAnchor;
          Ev.Tag := FPendingTag;
          FPendingAnchor := '';
          FPendingTag := '';
          Emit(Ev);
        end;
      ytkAlias:
        begin
          Ev := MakeEvent(yetAlias, UTF8Encode(Tok.Text), FLevel,
            Tok.Line, Tok.Column);
          Emit(Ev);
          FPendingAnchor := '';
          FPendingTag := '';
        end;
    else
      ; // ytkKey, ytkValue, ytkEntry, ytkDirective
    end;
  end;
end;

function TYamlParser.ParseDocumentTokens(const ATokens: TArray<TYamlToken>)
  : TArray<TYamlEventEx>;
var
  Before, I: Integer;
begin
  Before := Length(FEvents);
  if not FStreamStarted then
  begin
    Emit(MakeEvent(yetStreamStart, '', 0, 0, 0));
    FStreamStarted := True;
  end;
  ParseTokens(ATokens);
  if FInDocument then
  begin
    Emit(MakeEvent(yetDocumentEnd, '', FLevel, 0, 0));
    FInDocument := False;
  end;
  SetLength(Result, Length(FEvents) - Before);
  for I := 0 to High(Result) do
    Result[I] := FEvents[Before + I];
end;

function TYamlParser.ParseStreamEnd: TArray<TYamlEventEx>;
var
  Before, I: Integer;
begin
  Before := Length(FEvents);
  if not FStreamStarted then
  begin
    Emit(MakeEvent(yetStreamStart, '', 0, 0, 0));
    FStreamStarted := True;
  end;
  Emit(MakeEvent(yetStreamEnd, '', 0, 0, 0));
  SetLength(Result, Length(FEvents) - Before);
  for I := 0 to High(Result) do
    Result[I] := FEvents[Before + I];
end;

end.

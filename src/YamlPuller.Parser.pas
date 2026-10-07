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
    procedure Emit(const AEvent: TYamlEventEx);
  public
    constructor Create;
    destructor Destroy; override;
    /// parse the token list and return the event list
    function Parse(const ATokens: TArray<TYamlToken>): TArray<TYamlEventEx>;
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
  I, Level, DocCount: Integer;
  PendingAnchor, PendingTag: UTF8String;
  Tok: TYamlToken;
  Ev: TYamlEventEx;
  SType: TYamlScalarType;
  IsPlain, InDocument: Boolean;
begin
  FTokens := ATokens;
  SetLength(FEvents, 0);
  Level := 0;
  DocCount := 0;
  InDocument := False;
  PendingAnchor := '';
  PendingTag := '';

  Emit(MakeEvent(yetStreamStart, '', 0, 0, 0));

  for I := 0 to High(ATokens) do
  begin
    Tok := ATokens[I];
    case Tok.Kind of
      ytkAnchor:
        PendingAnchor := UTF8Encode(Tok.Text);
      ytkTag:
        PendingTag := UTF8Encode(Tok.Text);
      ytkDocumentStart:
        begin
          if InDocument then
            Emit(MakeEvent(yetDocumentEnd, '', Level, Tok.Line, Tok.Column));
          Emit(MakeEvent(yetDocumentStart, '', Level, Tok.Line, Tok.Column));
          InDocument := True;
          Inc(DocCount);
        end;
      ytkDocumentEnd:
        begin
          Emit(MakeEvent(yetDocumentEnd, '', Level, Tok.Line, Tok.Column));
          InDocument := False;
        end;
      ytkMapStart, ytkFlowMapStart:
        begin
          Ev := MakeEvent(yetMappingStart, '', Level, Tok.Line, Tok.Column);
          Ev.Anchor := PendingAnchor;
          Ev.Tag := PendingTag;
          PendingAnchor := '';
          PendingTag := '';
          Emit(Ev);
          Inc(Level);
        end;
      ytkMapEnd, ytkFlowMapEnd:
        begin
          Dec(Level);
          Emit(MakeEvent(yetMappingEnd, '', Level, Tok.Line, Tok.Column));
        end;
      ytkSeqStart, ytkFlowSeqStart:
        begin
          Ev := MakeEvent(yetSequenceStart, '', Level, Tok.Line, Tok.Column);
          Ev.Anchor := PendingAnchor;
          Ev.Tag := PendingTag;
          PendingAnchor := '';
          PendingTag := '';
          Emit(Ev);
          Inc(Level);
        end;
      ytkSeqEnd, ytkFlowSeqEnd:
        begin
          Dec(Level);
          Emit(MakeEvent(yetSequenceEnd, '', Level, Tok.Line, Tok.Column));
        end;
      ytkScalar:
        begin
          IsPlain := Tok.ScalarStyle = yssPlain;
          if PendingTag <> '' then
          begin
            if not FSchema.ApplyTag(PendingTag, SType, Tok.Line, Tok.Column) then
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
          Ev := MakeEvent(yetScalar, UTF8Encode(Tok.Text), Level,
            Tok.Line, Tok.Column);
          Ev.ScalarType := SType;
          Ev.Anchor := PendingAnchor;
          Ev.Tag := PendingTag;
          PendingAnchor := '';
          PendingTag := '';
          Emit(Ev);
        end;
      ytkAlias:
        begin
          Ev := MakeEvent(yetAlias, UTF8Encode(Tok.Text), Level,
            Tok.Line, Tok.Column);
          Emit(Ev);
          PendingAnchor := '';
          PendingTag := '';
        end;
    else
      ; // ytkKey, ytkValue, ytkEntry, ytkDirective
    end;
  end;

  // close any open document
  if InDocument then
    Emit(MakeEvent(yetDocumentEnd, '', Level, 0, 0));
  Emit(MakeEvent(yetStreamEnd, '', 0, 0, 0));
  Result := FEvents;
end;

end.

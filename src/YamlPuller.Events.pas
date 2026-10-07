{**
license: Apache-2.0
copyright: Copyright 2026 Liam Seamus Coughlin
---
Event model for the pull parser (plan story S02).
@br
The public event record matches the README contract; the internal record
  adds the schema type, the tag, the anchor, and the position that `Parse`
  and the JSON bridge require.
}
unit YamlPuller.Events;

{$mode delphi}{$H+}

interface

uses
  SysUtils;

type
  /// one value of the YAML event type enumeration
  TYamlEventType = (
    yetStreamStart,
    yetStreamEnd,
    yetDocumentStart,
    yetDocumentEnd,
    yetMappingStart,
    yetMappingEnd,
    yetSequenceStart,
    yetSequenceEnd,
    yetScalar,
    yetAlias);

  /// the public event record. The README fixes these fields.
  TYamlEvent = record
    EventType: TYamlEventType;
    EventText: UTF8String;
    /// the nesting depth. The stream start is 0. Each map and seq start adds
    /// one. Each map and seq end removes one.
    NestLevel: Integer;
    Line: Integer;
    Column: Integer;
  end;

  /// the resolved type of a scalar
  TYamlScalarType = (
    ystUnresolved,
    ystNull,
    ystBool,
    ystInt,
    ystFloat,
    ystStr);

  /// the selectable schema
  TYamlSchemaKind = (yscCore, yscFailsafe, yscJson);

  /// the internal event record. The parser emits this record. `Next` projects
  /// it to `TYamlEvent`. `Parse` reads the full record.
  TYamlEventEx = record
    EventType: TYamlEventType;
    EventText: UTF8String;
    ScalarType: TYamlScalarType;
    Tag: UTF8String;
    Anchor: UTF8String;
    NestLevel: Integer;
    Line: Integer;
    Column: Integer;
  end;

const
  YamlEventTypeName: array[TYamlEventType] of string = (
    'yetStreamStart', 'yetStreamEnd', 'yetDocumentStart', 'yetDocumentEnd',
    'yetMappingStart', 'yetMappingEnd', 'yetSequenceStart', 'yetSequenceEnd',
    'yetScalar', 'yetAlias');

  YamlScalarTypeName: array[TYamlScalarType] of string = (
    'ystUnresolved', 'ystNull', 'ystBool', 'ystInt', 'ystFloat', 'ystStr');

/// build an event with a type, a text, a nest level, and a position
function MakeEvent(AType: TYamlEventType; const AText: UTF8String;
  ANestLevel, ALine, AColumn: Integer): TYamlEventEx;

/// project an internal event to the public event
function PublicEvent(const AEvent: TYamlEventEx): TYamlEvent;

implementation

function MakeEvent(AType: TYamlEventType; const AText: UTF8String;
  ANestLevel, ALine, AColumn: Integer): TYamlEventEx;
begin
  FillChar(Result, SizeOf(Result), 0);
  Result.EventType := AType;
  Result.EventText := AText;
  Result.ScalarType := ystUnresolved;
  Result.NestLevel := ANestLevel;
  Result.Line := ALine;
  Result.Column := AColumn;
end;

function PublicEvent(const AEvent: TYamlEventEx): TYamlEvent;
begin
  FillChar(Result, SizeOf(Result), 0);
  Result.EventType := AEvent.EventType;
  Result.EventText := AEvent.EventText;
  Result.NestLevel := AEvent.NestLevel;
  Result.Line := AEvent.Line;
  Result.Column := AEvent.Column;
end;

end.

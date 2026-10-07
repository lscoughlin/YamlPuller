# YamlPuller Usage

## Purpose

This document describes the use of the YamlPuller library. The README file
holds the public API summary. This document gives the usage sequence and
examples.

## Requirements

The library has these requirements:

- Free Pascal 3.2.2 or later.
- The compiler mode `{$mode delphi}`.
- The FCL unit `fpjson` for the `Parse` operation.
- The program `make` for the build.

The `make` command is the build system. The `make` command compiles the
library units. A second target runs the unit tests. The `YamlPuller.lpk`
package file gives the same units to the Lazarus IDE. The README describes
the four data sources.

## The Four Factory Methods

`TYamlPullerFactory` creates a `TYamlPuller` from one data source. The choice
of method follows the data source.

| Method | Data source |
|---|---|
| `FromFile(file: handle)` | An open file handle |
| `FromStream(astream: TStream)` | A `TStream` instance |
| `FromBytes(astream: TBytes)` | A `TBytes` value |
| `FromString(astream: utf8string)` | A UTF-8 string |

The factory holds no data. A second call to the factory creates a second,
independent puller.

## The Pull Loop

`HasNext` states whether the stream holds more events. `Next` returns the next
event. The caller repeats the `Next` call while `HasNext` is true.

The event sequence starts with a stream-start event. The event sequence ends
with a stream-end event. A document start event and a document end event
enclose the events of each document.

Each `*Start` event has a matching `*End` event. The matching events are in
nested order.

## Event Types

The event type table below lists the events that `Next` returns.

| Event type | The event reports |
|---|---|
| Stream start | The start of the stream |
| Stream end | The end of the stream |
| Document start | The start of a document |
| Document end | The end of a document |
| Mapping start | The start of a mapping |
| Mapping end | The end of a mapping |
| Sequence start | The start of a sequence |
| Sequence end | The end of a sequence |
| Scalar | One scalar value, in the event text |
| Alias | One alias reference, in the event text |

## The Supported Tag Set

The library resolves an untagged scalar with the YAML 1.2 core schema. The
core schema has these tags:

| Tag | Type |
|---|---|
| `tag:yaml.org,2002:null` | Null |
| `tag:yaml.org,2002:bool` | Boolean |
| `tag:yaml.org,2002:int` | Integer |
| `tag:yaml.org,2002:float` | Float |
| `tag:yaml.org,2002:str` | String |
| `tag:yaml.org,2002:map` | Mapping |
| `tag:yaml.org,2002:seq` | Sequence |

The core schema resolves a plain scalar by these forms:

| Type | Plain forms |
|---|---|
| Null | `~`, `null`, `Null`, `NULL`, the empty scalar |
| Bool | `true`, `True`, `TRUE`, `false`, `False`, `FALSE` |
| Int | `[-+]?[0-9]+`, `0o[0-7]+`, `0x[0-9a-fA-F]+` |
| Float | A decimal form with an optional exponent, `.inf`, or `.nan` |
| String | Every other plain scalar |

A quoted scalar and a block scalar resolve to the string type. So `'123'` is
the string `"123"`, and `123` is the number `123`.

An explicit tag overrides the core schema. The example below holds three
values with explicit tags.

```yaml
port: !!int '8080'
name: !!str 123
quoted: 'true'
```

The result is this JSON text. The `port` member is a number, the `name`
member is a string, and the `quoted` member is a string.

```json
{"port":8080,"name":"123","quoted":"true"}
```

## The Merge Key

This library is a YAML 1.2 parser. YAML 1.2 removed the merge
key `<<` that YAML 1.1 defines. The library applies strict YAML 1.2 behavior.

The key `<<` is an ordinary scalar key. The example below holds a mapping with
one member named `<<`.

```yaml
defaults: &base
  host: localhost
server:
  <<: *base
  port: 8080
```

The parse of the `server` mapping gives the member `<<` with the value of the
`base` mapping. The result is this JSON text:

```json
{"defaults":{"host":"localhost"},"server":{"<<":{"host":"localhost"},"port":8080}}
```

The library performs no merge. The library raises no error for the key.

## Recursive Anchors

A YAML document is a directed graph. An anchor labels a node. An alias adds an
arrow to that node. A node can reference itself. A self-reference is a cycle,
or a recursive anchor.

The example below holds a mapping whose `child` member is the mapping itself.

```yaml
root: &self
  name: top
  child: *self
```

An event loop reads this document without an error. The loop reports one alias
event for the `child` member.

The `Parse` operation rejects the document. A cycle has no `TJSONData` value,
because FCL JSON is a tree. The error names the line and the column of the
alias.

## Non-String Mapping Keys

A YAML mapping key can be any node. A string key is the common case. The
example below shows scalar keys of other types.

```yaml
1: one
true: yes
```

The `Parse` operation converts a scalar key to its canonical YAML
core-schema text. The result is this JSON text:

```json
{"1":"one","true":"yes"}
```

A complex key is a sequence or a mapping. The explicit key form uses a
question mark and a space (`? `). The example below holds a sequence key.

```yaml
? - a
  - b
: complex
```

The `Parse` operation rejects this document. A sequence key raises an error,
because JSON has no name for the key. The error names the line and the
column.

An event loop reads the same document without an error. The loop reports a
mapping start event, then the events of the key node, then the events of the
value node.

## The Parse Operation

`Parse` reads the whole event stream and returns an FCL JSON value. The
return type is `TJSONData`. The caller releases the returned value.

The result follows the document count:

| Document count | Result |
|---|---|
| One document | The value of that document |
| Two or more documents | A `TJSONArray` with one element per document, in document order |

The value of a document follows the event type:

| YAML event | FCL JSON value |
|---|---|
| Mapping | `TJSONObject` |
| Sequence | `TJSONArray` |
| Scalar, null | `TJSONNull` |
| Scalar, boolean | `TJSONBoolean` |
| Scalar, integer | `TJSONInt64Number` |
| Scalar, float | `TJSONFloatNumber` |
| Scalar, string | `TJSONString` |

A mapping key becomes the name of a JSON member. A mapping value becomes the
JSON member value.

## Example: a String to a JSON Value

The example below creates a puller from a string. The example parses the
stream into a `TJSONData` value.

```pascal
uses
  fpjson, YamlPuller;

var
  puller: TYamlPuller;
  data: TJSONData;
begin
  puller := TYamlPullerFactory.FromString(
    'name: example' + LineEnding +
    'count: 3' + LineEnding +
    'enabled: true' + LineEnding);
  try
    data := puller.Parse;
    try
      WriteLn(data.AsJSON);
    finally
      data.Free;
    end;
  finally
    puller.Free;
  end;
end;
```

The example writes this text:

```json
{"name":"example","count":3,"enabled":true}
```

## Example: an Event Loop

The example below reads the events one at a time. The example writes the event
type and the event text.

```pascal
uses
  YamlPuller;

var
  puller: TYamlPuller;
  event: TYamlEvent;
begin
  puller := TYamlPullerFactory.FromString('list:' + LineEnding + '  - one' + LineEnding + '  - two' + LineEnding);
  try
    while puller.HasNext do
    begin
      event := puller.Next;
      WriteLn(Ord(event.EventType), ': ', event.EventText);
    end;
  finally
    puller.Free;
  end;
end;
```

The event loop is useful when the caller needs only part of the document. The
caller can stop the loop at any event.

## Example: a Multi-Document Stream

The example below parses a stream with two documents. The result is a
`TJSONArray`.

```pascal
uses
  fpjson, YamlPuller;

var
  puller: TYamlPuller;
  data: TJSONData;
begin
  puller := TYamlPullerFactory.FromString(
    '---' + LineEnding +
    'name: first' + LineEnding +
    '---' + LineEnding +
    'name: second' + LineEnding);
  try
    data := puller.Parse;
    try
      WriteLn(data.AsJSON);
    finally
      data.Free;
    end;
  finally
    puller.Free;
  end;
end;
```

The example writes this text:

```json
[{"name":"first"},{"name":"second"}]
```

## Example: a Stream Source

The example below creates a puller from a file stream. The example parses the
stream into a `TJSONData` value.

```pascal
uses
  Classes, fpjson, YamlPuller;

var
  source: TFileStream;
  puller: TYamlPuller;
  data: TJSONData;
begin
  source := TFileStream.Create('config.yaml', fmOpenRead);
  try
    puller := TYamlPullerFactory.FromStream(source);
    data := puller.Parse;
    try
      WriteLn(data.AsJSON);
    finally
      data.Free;
    end;
    puller.Free;
  finally
    source.Free;
  end;
end;
```

## Release of Resources

The caller releases each `TYamlPuller` instance. The puller does not release
the data source. The caller releases the data source.

The caller releases each value that `Parse` returns.

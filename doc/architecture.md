# YamlPuller Architecture

## Purpose

This document describes the structure and the behavior of the YamlPuller
library. The library is a YAML 1.2 pull parser for Object Pascal.

A pull parser returns one event at a time. The caller controls the event
sequence. The caller can stop the event loop at any event. The puller reads
the source one document region at a time. The scanner holds the tokens of the
current region only. A caller that stops early does not read the later
documents. The `Parse` operation reads the whole stream because it builds the
whole JSON value. The streaming behavior and its limits are recorded in
`doc/usage.md`.

The public API is the contract. The README file holds the public API. This
document describes the internals below that API.

## Assumptions

This section records the assumed environment. Each assumption is confirmed
against the build.

| Item | Assumed value |
|---|---|
| Language | Object Pascal |
| Compiler mode | `{$mode delphi}` |
| Compiler | Free Pascal 3.2.2 or later. The build is confirmed with Free Pascal 3.2.4. |
| JSON classes | FCL `fpjson` (`TJSONObject`, `TJSONArray`, and the scalar classes) |
| Test framework | `fpcunit` with a console runner |
| YAML version | YAML 1.2 |
| Build tool | `make` |

The `Makefile` is the build system. The `Makefile` compiles the library units
in `src/` and runs the unit tests in `test/`. The repository also holds a
Lazarus package file, `YamlPuller.lpk`. The package file lists the same source
units and the `FCL` requirement. The Makefile build and the Lazarus build use
the same units.

## Layer Model

The library has four layers. Data moves from the input layer to the JSON
bridge. Each layer has one responsibility.

```
+----------------+     +----------------+     +----------------+     +----------------+
|  Input layer   | --> |  Scanner       | --> |  Parser        | --> |  JSON bridge   |
|  bytes -> chars|     |  chars -> toks |     |  toks -> events|     |  events -> FCL  |
+----------------+     +----------------+     +----------------+     +----------------+
```

The input layer removes the byte encoding. The scanner removes the character
syntax. The parser removes the event structure. The JSON bridge converts the
event structure into an FCL JSON object.

### Input Layer

The input layer receives one of four data sources:

- A file handle.
- A `TStream` instance.
- A `TBytes` value.
- A UTF-8 string.

The input layer performs two operations on the bytes:

1. Byte order mark (BOM) detection. YAML 1.2 permits UTF-8, UTF-16, and
   UTF-32. The BOM identifies the encoding. A UTF-8 stream can also exist
   without a BOM. The input layer detects the encoding from the first
   characters in that case.
2. Line-break normalization. YAML 1.2 accepts LF, CRLF, and CR as line
   breaks. The input layer reports one line-break form to the scanner.

The input layer supplies characters, not bytes, to the scanner.

### Scanner

The scanner reads characters and produces tokens. Each token has a type and a
text value. The scanner tracks these items:

- The current indentation column.
- The block context stack. The stack holds the open block collections.
- The current position, as a line number and a column number.

The scanner reads one document region at a time. The region holds the lines
from the current position to the next document start marker at column 0. The
scanner holds the tokens of the current region only. The scanner reads the
next region when the caller requests its tokens.

The scanner reports indentation as block collection tokens. An indentation
increase opens a block collection. An indentation decrease closes the open
block collections. The scanner has these token families:

| Family | Token kinds |
|---|---|
| Document markers | `ytkDocumentStart` for `---`, `ytkDocumentEnd` for `...` |
| Directives | `ytkDirective` for `%YAML` and `%TAG` |
| Block collections | `ytkMapStart`, `ytkMapEnd`, `ytkSeqStart`, `ytkSeqEnd` |
| Block entries | `ytkEntry` for `-`, `ytkKey` for `?`, `ytkValue` for `:` |
| Flow collections | `ytkFlowMapStart`, `ytkFlowMapEnd`, `ytkFlowSeqStart`, `ytkFlowSeqEnd`, `ytkFlowEntry` for `,` |
| Scalars | `ytkScalar`, with the style plain, single-quoted, double-quoted, block literal, or block folded |
| Properties | `ytkAnchor` for `&`, `ytkAlias` for `*`, `ytkTag` for `!` and a tag handle |

A comment runs from `#` to the end of the line. The scanner removes a
comment and reports no token for it.

### Parser

The parser reads tokens and produces events. The parser holds a state machine.
The state machine has these states:

- Stream start and stream end.
- Document start and document end.
- Mapping start and mapping end.
- Sequence start and sequence end.
- Scalar.
- Alias.

The parser reports an anchor as a property of the next node event. The parser
reports an alias as an alias event. The alias stays unresolved in the event
stream. The JSON bridge holds the table of anchors for the current document
and resolves each alias against that table.

### JSON Bridge

The JSON bridge reads the event stream and builds an FCL JSON value. The
README documents these operations as `Parse: TJSONData` and
`Parse(event, data)`.

The `Parse(event, data)` operation builds the value that starts at one event.
The operation reads forward one document at a time until the event is in the
event log. The read then stops at the end event of the node. A node event
builds its node. A document start builds the whole document. A stream start
and an end event start no value.

The bridge applies these rules to a single document:

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
JSON member value. A nested mapping becomes a nested `TJSONObject`. A nested
sequence becomes a nested `TJSONArray`.

The bridge counts the documents in the stream. A stream with one document
returns the value of that document. A stream with two or more documents
returns a `TJSONArray`. Each element is the value of one document, in
document order.

## Event Model

`TYamlEvent` is the unit of output from the parser. The README defines five
fields:

| Field | Type | Meaning |
|---|---|---|
| `EventType` | `TYamlEventType` | The kind of the event |
| `EventText` | `utf8string` | The text of the event |
| `NestLevel` | `integer` | The nesting depth of the event |
| `Line` | `integer` | The 1-based line of the event |
| `Column` | `integer` | The 1-based column of the event |

The stream start event has the nest level 0. Each `*Start` event of a
collection adds one to the nest level. Each `*End` event of a collection
removes one. A scalar event and an alias event keep the nest level of the
enclosing collection.

`TYamlEventType` is an enumeration. The enumeration requires these values:

| Value | Meaning |
|---|---|
| `yetStreamStart` | The start of the stream |
| `yetStreamEnd` | The end of the stream |
| `yetDocumentStart` | The start of a document |
| `yetDocumentEnd` | The end of a document |
| `yetMappingStart` | The start of a block or flow mapping |
| `yetMappingEnd` | The end of a mapping |
| `yetSequenceStart` | The start of a block or flow sequence |
| `yetSequenceEnd` | The end of a sequence |
| `yetScalar` | A scalar value |
| `yetAlias` | An alias reference |

Each `*Start` event has a matching `*End` event. The matching events are in
nested order. A mapping start event and its mapping end event enclose the
events of the mapping entries.

## Position Tracking

The scanner records the line and the column of the first character of each
token. The parser holds the position of the current event. The position
appears in an error message. An error message names the line and the column of
the token that caused the error.

## Scalars and the Core Schema

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

A quoted scalar and a block scalar resolve to the string type. An explicit
tag overrides the core schema.

The library applies these rules to a tag:

- The core schema is the default tag set.
- The failsafe schema and the JSON schema are selectable. Each schema is a
  subset of the core schema.
- The `%TAG` directive expands a tag handle before the comparison.
- An unknown local tag causes the library to keep the underlying node type. A
  strict mode raises an error instead.
- A YAML 1.1-only tag raises an error that names the line and the column. The
  tag set of YAML 1.1 includes `!!timestamp`, `!!binary`, `!!set`, `!!omap`,
  and `!!pairs`. YAML 1.2 dropped these tags.

The event stream reports the tag text of a node. The tag resolution occurs
only in `Parse`.

## The Merge Key

YAML 1.1 defines the merge key `<<` (tag `tag:yaml.org,2002:merge`). YAML 1.2
removed this key from the specification. This library is a YAML 1.2 parser.

The library applies strict YAML 1.2 behavior to the `<<` key. The library
treats `<<` as an ordinary scalar key. A mapping with the key `<<` therefore
holds one member with the name `<<`. The library does not merge the referenced
mapping. The library does not raise an error for the key.

This rule has no effect on anchors and aliases. The library supports anchors
and aliases without the merge key.

## Recursive Anchors

A YAML document is a directed graph. An anchor labels a node. An alias adds an
arrow to that node. A node can therefore reference itself, directly or through
other nodes. A self-reference is a cycle, or a recursive anchor.

The library applies these rules:

- The event stream reports an alias as one alias event. The event stream is
  safe for a cycle, because the event stream does not resolve the alias.
- `Parse` resolves an acyclic alias by copy. The result holds the value of the
  anchored node.
- `Parse` rejects a cyclic alias. A cyclic alias raises an error that names
  the line and the column. FCL JSON is a tree. A tree holds no cycle.
- `Parse` applies a depth bound to the alias resolution. The depth bound
  closes the resource-exhaustion risk of a deep or a large alias expansion.

The depth bound is the `MaxDepth` property of the JSON bridge. The default
value is 1000.

## Non-String Mapping Keys

YAML places no restriction on a mapping key. A key can be any node: an
integer, a boolean, a null, a sequence, or a mapping. The explicit key form
uses a question mark and a space (`? `). JSON requires that every object
member name is a string. FCL JSON follows this rule.

The library applies these rules to a mapping key:

| Key node | Rule |
|---|---|
| String scalar | The member name is the text of the key. |
| Integer, float, boolean, or null scalar | The member name is the canonical YAML core-schema text of the key. |
| Sequence or mapping | The library raises an error. JSON has no name for the key. The error names the line and the column. |
| Duplicate member name after this conversion | The library raises an error. YAML requires unique keys. |

The event stream reports a mapping key without loss. The mapping start event
is followed by the events of the key node and the events of the value node.
The conversion occurs only in `Parse`.

## Constraints

The repository guidelines constrain the source files:

- A Pascal file is less than 1000 lines long. A Pascal file expresses one
  concept, or one related set of concepts.
- A Pascal method is less than 500 lines long. This limit is a soft limit.
  A Pascal method expresses one responsibility.

The layer model is compatible with these constraints. Each scanner token
family and each parser state can occupy one unit or one method.

## Decisions

All design questions are decided. This section records each decision.

The multi-document behavior is decided. A stream with two or more documents
returns a `TJSONArray` of the document values.

The merge-key behavior is decided. The library applies strict YAML 1.2
behavior: the key `<<` is an ordinary scalar key.

The recursive-anchor behavior is decided. `Parse` resolves an acyclic alias by
copy and rejects a cyclic alias with a line-and-column error.

The non-string-key behavior is decided. A scalar key becomes its canonical
text. A collection key raises an error.

The tag-set behavior is decided. The core schema is the default. The failsafe
schema and the JSON schema are selectable. A YAML 1.1-only tag raises an
error.

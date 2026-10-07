# YamlPuller

YamlPuller is a YAML 1.2 compliant pull parser. It is an Object Pascal library.
The library uses the FCL JSON classes for the `Parse` result.

## Overview

The library consists of two main classes: `TYamlPullerFactory` and
`TYamlPuller`.

`TYamlPullerFactory` instantiates a `TYamlPuller` from a data source.
`TYamlPuller` reads the YAML event stream. `TYamlPuller.Next` returns one
`TYamlEvent` at a time.

## Build

`make` is the build system. The `Makefile` compiles the library units in
`src/`, runs the unit tests in `test/`, and runs the example programs in
`examples/`. The `make examples` target compiles and runs each example.

The repository also holds a Lazarus package file, `YamlPuller.lpk`. The
package file lists the library units and the `FCL` requirement. A user opens
the package in the Lazarus IDE to browse the units or to install the package.

The `Makefile` is the primary build system. The `make` build and the Lazarus
build use the same source units.

## TYamlPullerFactory

```yaml
TYamlPullerFactory:
    - TYamlPuller FromFile( file: handle )
    - TYamlPuller FromStream( astream: TStream )
    - TYamlPuller FromBytes( astream: TBytes )
    - TYamlPuller FromString( astream: utf8string )
```

The factory instantiates a `TYamlPuller` from a given data source. The four
methods cover the four data sources:

- `FromFile` reads from a file handle.
- `FromStream` reads from a `TStream`.
- `FromBytes` reads from a `TBytes` value.
- `FromString` reads from a UTF-8 string.

## TYamlPuller

```yaml
TYamlPuller:
    Next: TYamlEvent # the next event
    HasNext: boolean # more events are available
    Parse: TJSONData # reads the whole event stream into an FCL JSON value
    Parse( event: TYamlEvent, data: TJSONData ) # reads one subsection
```

- `Next` returns the next event from the stream.
- `HasNext` states whether more events are available.
- `Parse` reads the whole event stream and returns an FCL JSON value.
  - A stream with one document returns the value of that document. The value
    is a `TJSONObject`, a `TJSONArray`, or a scalar.
  - A stream with two or more documents returns a `TJSONArray`. Each element
    is the value of one document, in document order.
  - `Parse` resolves an alias by copy. A cyclic alias raises an error that
    names the line and the column. FCL JSON is a tree and holds no cycle.
  - A mapping key that is a string becomes the member name unchanged. A
    scalar key of another core type becomes its canonical core-schema text. A
    collection key raises an error that names the line and the column. A
    duplicate member name after this conversion raises an error.
  - `Parse` resolves an untagged scalar with the YAML 1.2 core schema. The
    core schema has the tags null, bool, int, float, str, map, and seq. A
    YAML 1.1-only tag raises an error that names the line and the column.
  - The caller releases the returned value.
  - The caller releases the returned value.
- `Parse(event, data)` reads the subsection that starts at `event` and
  assigns the JSON value to `data`. The caller releases `data`.
  - A mapping start, a sequence start, a scalar, and an alias build their
    node value.
  - A document start builds the value of the whole document.
  - A stream start and an end event set `data` to nil, because such an
    event starts no value.
  - An alias inside the subsection resolves to an anchor that is complete
    before `event`, in the same document.
  - The event identifies the start by its value. The event must come from
    the same puller.

## TYamlEvent

`TYamlEvent` is one event parsed from the stream.

```yaml
TYamlEvent:
    EventType: TYamlEventType # one value of the YAML event type enumeration
    EventText: utf8string # the event text
    NestLevel: integer # the nesting depth
    Line: integer # the 1-based line of the event
    Column: integer # the 1-based column of the event
```

- `EventType` is one value of the `TYamlEventType` enumeration.
- `EventText` holds the text of the event.
- `NestLevel` is the nesting depth. The stream start event is 0. Each mapping
  start event and each sequence start event adds one. Each mapping end event
  and each sequence end event removes one.
- `Line` and `Column` give the position of the event in the input.

## License

This product is licensed under the Apache License, Version 2.0. See the
`LICENSE` file for the full text.

Copyright 2026 Liam Seamus Coughlin.

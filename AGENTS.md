# Repository Guidelines

## Language

All text output uses ASD-STE100 Simplified Technical English.

## Documentation

Documentation is in the `doc/` directory. Documentation is descriptive and
declarative. Documentation never uses the imperative mood. Documentation never
refers to a file in the `plan/` directory.

## Plans

Plans are in the `plan/` directory. A plan can refer to a document in the
`doc/` directory.

## Pascal File Header

Each Pascal file starts with a pasdoc documentation comment. The comment
wraps YAML front matter. The front matter holds a `license` key and a
`copyright` key.

```pascal
{**
license: Apache-2.0
copyright: Copyright 2026 Liam Seamus Coughlin
---
Purpose of the file.
@br
Notes on the file.
}
unit Example;
```

- The comment is a pasdoc comment. The opening `{**` is on its own line. The
  `license` key follows on the next line.
- The `license` value is the SPDX license identifier. The README holds the
  full license name.
- The `copyright` value holds the copyright holder and the year.
- Additional keys are permitted.
- A line with three hyphens (a `---` line) closes the front matter.
- The closing `}` is on its own line.

The front matter is followed by a pasdoc description of the file. The
description holds two parts.

- The purpose of the file. The purpose is one sentence. The purpose states
  the one concept that the file expresses.
- The notes on the file. The notes state the constraints, the dependencies,
  and the related plan story.

```pascal
{**
license: Apache-2.0
copyright: Copyright 2026 Liam Seamus Coughlin
---
Scanner driver: indentation and simple keys (plan story S03).
@br
The driver reads the physical lines and produces the token list. The family
units supply the scalar, block, flow, and comment functions.
}
unit YamlPuller.Scanner;
```

## Pascal Source

- A Pascal file is less than 1000 lines long. A Pascal file expresses one
  concept, or one related set of concepts.
- A Pascal method is less than 500 lines long. This limit is a soft limit. A
  Pascal method expresses one responsibility.

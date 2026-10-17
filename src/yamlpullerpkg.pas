{**
license: Apache-2.0
copyright: Copyright 2026 Liam Seamus Coughlin
---
Lazarus package entry unit.
@br
The unit name differs from YamlPuller so the package compiler does not write
a file that replaces the public unit.
}
unit yamlpullerpkg;

{$warn 5023 off : no warning about unused units}
interface

uses
  YamlPuller,
  YamlPuller.Input,
  YamlPuller.Events,
  YamlPuller.Scanner.Core,
  YamlPuller.Scanner,
  YamlPuller.Scanner.Comments,
  YamlPuller.Scanner.Scalar,
  YamlPuller.Scanner.Block,
  YamlPuller.Scanner.Flow,
  YamlPuller.Parser,
  YamlPuller.Schema,
  YamlPuller.JSON,
  YamlPuller.Errors;

implementation

end.

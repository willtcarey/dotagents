---
name: ruby
description: Use when reading and writing Ruby code.
---

# Ruby

Use RubyDex (`rdx`) for semantic navigation of Ruby codebases. Run it from the workspace root.

Use RubyDex to find declarations and definitions, namespace members, inheritance, mixins, descendants, resolved constant references, and declarations defined in a file. Use `rg` instead for literal text, comments, messages, templates, configuration, and non-Ruby files.

RubyDex helps locate code but does not replace reading the relevant source and tests before editing.

## Query Schema

### Nodes

- `Document`: a source file
- `Definition`: one occurrence of a Ruby construct in a file
- `Declaration`: the global merged concept of a named entity
- `Namespace`: a class, module, or singleton class declaration
- `Class`
- `Module`
- `SingletonClass`
- `Method`
- `Constant`
- `ConstantAlias`
- `GlobalVariable`
- `InstanceVariable`
- `ClassVariable`

### Relationships

- `Document-[:DEFINES]->Definition`
- `Definition-[:DECLARES]->Declaration`
- `Definition-[:CONTAINS]->Definition`
- `Class-[:HAS_PARENT]->Class`; use `*` for the full chain
- `Declaration-[:INCLUDES]->Declaration`
- `Declaration-[:PREPENDS]->Declaration`
- `Declaration-[:EXTENDS]->Declaration`
- `Declaration-[:OWNS]->Declaration`
- `Declaration-[:HAS_ANCESTOR]->Declaration`
- `Declaration-[:HAS_DESCENDANT]->Declaration`
- `Document-[:REFERENCES]->Declaration`

### Properties

- Any node: `label`, `kind`
- Declaration: `name`, `unqualified_name`, `visibility`, `definition_count`
- Definition: `name`, `file`, `line`
- Document: `uri`, `path`, `name`

Run read-only Cypher queries, preferring JSON for programmatic inspection:

```bash
rdx query "MATCH (d:Declaration) WHERE d.name CONTAINS 'User' RETURN d.label, d.name LIMIT 50" --format json
```

For Rails code, also apply the `rails-conventions` skill.

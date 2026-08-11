---
name: rails-conventions
description: Apply Will's preferred Rails conventions when implementing, refactoring, or reviewing Ruby on Rails code.
---

# Rails Conventions

## Models

- Do not add numericality validations for foreign keys.
- Model domain concepts as objects with behavior; do not default to service objects.
- Define one primary class per file. An enclosing class or module used only to namespace that primary class does not count as an additional class. Error classes and small data classes defined with `Data.define` or `Struct.new` may share the file.

## Views

- When possible, do not assign variables in views.
- When view logic is needed, prefer a ViewComponent if the project uses ViewComponent. Otherwise, move the logic to the controller when feasible.
- Do not go to great lengths to expose a controller instance variable solely for use in a partial; prefer passing a local to the partial when appropriate.

## Controllers

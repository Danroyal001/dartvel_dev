# dartvel_generator

Compile-time generators for Dartvel applications.

This package discovers Dartvel pages, layouts, guards, models, and backend
annotations, then emits readable Flutter/Dart glue code used by the Dartvel CLI
and build pipeline.

## Generated Output

Generated files are intentionally formatted and named for developers:

- stable helper names instead of opaque abbreviations
- small route and redirect helpers
- explicit imports for pages, layouts, and guards
- `dart format` compatible output

## Development

Run package tests from this directory:

```bash
dart test
```

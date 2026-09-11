# dartvel_generator

> **Retired.** The `build_runner` builders in this package are retired and will
> be removed in `dartvel_generator` 2.0.0. Generate with the `dartvel` CLI
> instead. They still work exactly as they did — nothing breaks today — and
> every build logs a warning naming the replacement.

## Migrating

```bash
# instead of
dart run build_runner build --delete-conflicting-outputs

# run
dart run dartvel_cli:dartvel routes
```

`dartvel build` generates before it builds, so on that path there is nothing
to run separately.

Then drop both packages from the project:

```yaml
dev_dependencies:
  build_runner: ^2.5.4      # remove
  dartvel_generator: ^1.2.0 # remove
  dartvel_cli: ^0.4.1       # keep: it is the generator now
```

Keep `build_runner` only if some *other* package's builders need it — a
`json_serializable`, a `freezed`, `flutter_vscode`'s controller bindings.
`dartvel build` and `dartvel dev` still run it for those.

## Why

`dart run dartvel_cli:dartvel routes` generates the whole client: the
`lib/dartvel_client/dartvel_client.dart` barrel every page imports, the router,
each page's body, functional widgets, models, backend functions and config.
These builders generate only the router, env, config, runtime and page bodies,
so they cannot start from a clean checkout at all — with no barrel, the first
page's `@DVPage` cannot be resolved and the build stops. Every project on this
path was really running `dartvel routes` first and build_runner second, and
keeping two generators in step over one concern is what let three bugs live in
the build_runner router that `dartvel routes` never had.

## Still here

The builders — `route_builder`, `router_builder`, `page_body_builder` — are
unchanged and still `auto_apply: dependents`, so an existing project keeps
building while it migrates. Removing them outright would have deleted the
`router.g.dart` they had written into `lib/`, which is a broken project with no
explanation attached.

## Development

Run package tests from this directory:

```bash
dart test
```

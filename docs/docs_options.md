# `dartvel.docs`: the generated documentation site

`dartvel docs` writes the project's own reference -- its data models,
functions, routes, jobs, policies, modules and decision records -- as a
document, `docs.json`, beside the raw graph, `graph.json`. The site that draws
it is `DVDocsApp`, a Flutter application from `dartvel_flutter`, compiled on
its own the way Studio is. No page of it is hand-written HTML.

## Off unless you turn it on

A build carries the site only when `pubspec.yaml` asks for it. This holds for
every application and every build profile: an application deployed by
somebody who never read this page does not acquire a page listing its models
and policies.

```yaml
dartvel:
  docs:
    enabled: true   # default false
    path: /docs     # default /docs
    access: studio  # studio (default) or public
```

- `enabled`: only `true` turns it on. Anything else, or no `docs` section at
  all, is off.
- `path`: where the site is mounted. It must begin with `/`, cannot be `/`,
  and is a literal (`/docs/:id` and `/docs/*` are refused). A trailing slash
  is dropped.
- `access`: who may read it.
  - `studio` (the default): the site is Studio's. A person without the
    Studio grant who opens a page of it is sent to Studio's sign-in
    (`<admin mount>/login?from=...`), and the document, the graph and the
    compiled site answer exactly as a path the application does not serve
    (its 404). It needs a server that serves Studio (`dartvel.admin.enabled`
    on a `web-server` build).
  - `public`: anybody may read it.

## What each build does with it

| Build | `access: studio` | `access: public` |
|---|---|---|
| `dartvel build web-server` | Carried in the binary in a section of its own, outside the files it serves to anybody, and served at the mount behind Studio's sign-in and grant. Refused when the build serves no Studio. | Carried the same way and served to anybody. |
| `dartvel build web` | Refused: a static host serves every file to anybody, so it cannot keep the site behind Studio. Build `web-server`, or choose `access: public`. | Written at the mount, like any other page of the site. |

Either build refuses, naming both, a mount that an application page is at or
inside -- a site with its own `/docs` pages keeps them, and the build says to
move one of the two with `dartvel.docs.path`.

## Local use

`dartvel docs` writes `docs.json` and `graph.json` to `build/docs` (or
`--output`). `dartvel docs --serve` also compiles the site and serves it on
loopback at `http://127.0.0.1:4180/` (`--port`), rebuilding when the project
changes. It needs no `dartvel.docs` setting: it is the documentation you are
writing against, not something deployed.

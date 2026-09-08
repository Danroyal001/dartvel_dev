import 'package:flutter/material.dart';
import '../dartvel_client/dartvel_client.dart';
import '../components/site.dart';

/// Every section the repository records as Shipped, and nothing else.
///
/// The list is taken from docs/spec-status.json, which is checked by a tool
/// that fails when a section claims to be built and the evidence it names does
/// not exist. A marketing page that listed more than that would be the first
/// place the project stopped being honest.
/// Public because the page body is lowered into the generated router,
/// which reaches a page's public symbols through its import and cannot see
/// a private one at all.
const List<(String, String, String)> shipped = <(String, String, String)>[
  (
    'UI',
    'DVBox and DVText',
    'One layout primitive with a fluent modifier chain. DVBox.list, .row, '
    '.grid and .wrapLine for collections; DVBox(child) for a single one.',
  ),
  (
    'Styling',
    'Fluent modifiers',
    'padding, rounded, colour, typography, shadows, tap targets and semantics '
    'on one chain, built on Mix. A box can be turned now, and could not: the '
    'chain faded a box, rounded it, bordered it and painted a gradient '
    'through it, and had no way to rotate one -- so an imported design\'s '
    'tilted badge and its angled price flash came through square. Rendered, '
    'plausible, and not the design, which is the kind of loss nothing '
    'reports. rotate takes degrees rather than radians, which differs from '
    'Flutter\'s own Transform.rotate on purpose: the number in a page '
    'document, the number a designer reads in an inspector, the number Figma '
    'reports for a layer and the number in exported source are then all the '
    'same one, converted once where the widget is built. Text can be '
    'underlined and struck through now, and could not: the chain carried '
    'every other text style a design uses and had no way to mark a link or '
    'a superseded price, so both arrived as ordinary text. One method taking '
    'Flutter\'s own TextDecoration rather than an underline flag and a '
    'strikethrough flag beside each other, because a design that underlines '
    'and strikes the same run is a real design and two flags cannot say it. '
    'Text nobody decorated carries no decoration at all rather than '
    'TextDecoration.none, which would override an underline an enclosing '
    'theme asked for. A box can be blurred now, and could not: a soft-focus '
    'shape rendered sharp, and a frosted card over a photograph rendered as '
    'a flat translucent panel. Two methods rather than one, because they '
    'are not the same picture -- blur softens the box and what is in it, '
    'backdropBlur leaves it sharp and softens whatever shows through, which '
    'is the whole of the frosted effect. The unit is a standard deviation, '
    'the one ImageFilter.blur and CSS both take, and Figma writes the '
    'number from its Layer blur straight into blur(Npx), so the value a '
    'designer typed is the value everywhere. A background blur is bounded '
    'by the box, since an unclipped one blurs the whole screen behind it '
    'and nothing points at the card that asked for it. The chain reaches '
    'text now, and did not: DVText drew text and only text, so a modifier '
    'carrying padding, a background, a corner radius, a width or a fade '
    'reached it and did nothing on a build that succeeded. This repository '
    'did it to itself four times, two of them visible here -- the '
    'paragraph helper set a readable measure every paragraph was meant to '
    'be held to and none of them were, and the prebuilt sign-in page asks '
    'for a padded, rounded, dark button and drew the two words on their '
    'own. The box half is drawn by the thing that draws '
    'boxes, only when one was asked for, and the tap and the semantics are '
    'left with the text so a button does not run its action twice and a '
    'screen reader does not say heading twice. A rounded box also rounds '
    'what is in it now, and did not: the radius reached the decoration and '
    'nothing else, so a box drew rounded corners and its child squared them '
    'off again. With a flat colour nobody notices. With a photograph '
    'everybody does, and it is the commonest rounded thing in any design -- '
    'every circular avatar came through as a square photograph inside a '
    'rounded outline. A box can also be told to crop what is in it without '
    'being rounded, which is a decision of its own -- a photograph cropped '
    'by a square frame is the commonest version -- and without it the child '
    'paints outside the box and the page carries an overflow stripe.',
  ),
  (
    'Routing',
    'File-based pages',
    'A file under lib/pages is a route. Navigation is typed against generated '
    'targets, so a moved page is a compile error rather than a 404.',
  ),
  (
    'State',
    'Signals',
    'context.signal, signal(context, value), reactive models and DV.global. '
    'Operating on signals returns a signal, so a + b and stock > 0 track '
    'their sources without a separate computed type.',
  ),
  (
    'Models',
    '@DVModel',
    'One annotated class generates the typed client, serialization, the form, '
    'the table, the admin surface and the sync. Which meant that reading the '
    'annotation wrongly cost all of them at once, and it was read wrongly in '
    'two ways. The pattern that finds a model stopped at the first closing '
    'bracket, so a string argument containing one -- a schema type of '
    'Product (beta), say -- ended the annotation early and the model was not '
    'found at all: no class, no table, no admin row, no graph node, on a '
    'build that succeeded. Six separate parsers carried that pattern, and a '
    'model one of them misses while another finds it is a table in the '
    'database with no row anywhere else. The same scan now skips strings and '
    'comments, because an annotation written about in a paragraph is not an '
    'annotation -- this page describes one further down, and a parser that '
    'took the first one it saw in the file read the paragraph.',
  ),
  (
    'Forms',
    'DVForm<T>',
    'Inputs, validation and error surfaces derived from the model, so a field '
    'added to the model appears in the form.',
  ),
  (
    'Backend',
    '@DVBackendFunction',
    'A Dart function becomes an endpoint, served by an Axum and Tokio runtime '
    'in Rust reached over FFI, with the client generated alongside it.',
  ),
  (
    'Streaming Functions',
    'Server-sent events',
    'A backend function that returns a stream is served as SSE, with a typed '
    'client that consumes it.',
  ),
  (
    'Authorization',
    'DV.Auth.authorization',
    'Policies over models, functions and pages, enforced before a handler '
    'runs rather than inside it, and default-deny: a policy nobody '
    'registered answers no, which is the right answer to a question the '
    'application never taught it. A page declares one with the page '
    'annotation policy argument, and that is now enforced -- it was '
    'accepted and ignored until '
    'September 2026, so a page carrying the annotation for guarding it was '
    'open to everybody with nothing anywhere saying so. A page whose '
    'application has configured nothing to answer its policy is refused '
    'rather than opened, because treating no answer as yes would put the '
    'same bug back as a default; and a folder guard still runs first, since '
    'a page can be under one and carry a policy of its own. A backend '
    'function declares one the same way, and its gate runs on the generated '
    'route after the body is read, so the cross-site check still runs '
    'first. And a policy class -- the annotation naming the model it '
    'governs, with a method per action -- is read now, which it was not: '
    'the annotation was the specification\'s own headline example of '
    'authorization and appeared in one file, the one declaring it, so a '
    'PostPolicy somebody wrote compiled and was never consulted. Its '
    'conventional methods are registered by the client runtime before a '
    'page can ask whether to draw an action, because a generated table '
    'hides an action the policy denies and a client that registered '
    'nothing would hide every one of them. The server does not register '
    'them: a policy is written against the models, those are reached '
    'through the generated barrel, and that barrel carries the router and '
    'the widgets, so one policy import would compile Flutter into a server '
    'with no screen. It enforces the policy on a backend function by name '
    'instead. A method that takes a different model than the one '
    'the annotation names stops the build: it would register the check '
    'under that other model, leaving the annotated one failing closed while '
    'the other is opened by a policy nobody wrote for it. What a generated '
    'admin does not yet do is ask before it draws New and Delete: it draws '
    'them and deletes the row. That one is named rather than half-built, '
    'because the check needs a user and there are two notions of one here '
    'that nobody has reconciled -- the session user and the model a policy '
    'is written against -- and handing the wrong one to a check would throw '
    'where a refusal belongs, which is worse than the gap.',
  ),
  (
    'Theme',
    'Light and dark',
    'A themed surface that follows the system by default. This site runs on '
    'it — switch your appearance and it follows.',
  ),
  (
    'Model Sync and Presence',
    'Built on models and signals',
    'Generated sync, subscriptions, presence and fanout. There is no '
    'DV.Realtime namespace, deliberately: it is models, signals and queues.',
  ),
  (
    'SEO',
    'Head tags, prerendering and a sitemap that says something',
    'dartvel build web writes the title, description, canonical, Open Graph '
    'and Twitter tags from configuration, and prerendered routes carry '
    'semantic content for crawlers. The sitemap leaves out routes the '
    'router guards, which it did not until recently: it was built by '
    'reading path literals out of the generated router, and a pattern that '
    'matches a path cannot see the guard three lines under it, so every '
    'private route was published. The generator now writes down which '
    'routes it guards and the build reads that instead of guessing. A '
    'module mounted with sitemap: exclude is left out now too, and was not: '
    'the key was parsed, reached the mount and was written into the route '
    'index, and the sitemap writer never asked -- the same failure, in the '
    'one place a comment said it was handled. Those routes are still '
    'answered and still redirected to, because the exclusion is about being '
    'advertised rather than reachable, so the sitemap and the server '
    'manifest ask different questions. A page '
    'tunes its own entry with @DVPage(sitemap: DVPageSitemap(priority: 0.8, '
    'changeFrequency: DVSitemapChangeFrequency.daily)), and the project '
    'sets the rest under dartvel.seo.sitemap: whether to write the file at '
    'all, which paths to exclude, and the defaults for a page that said '
    'nothing. A page overrides those field by field, so saying only that it '
    'changes daily keeps the project\'s priority. A route neither of them '
    'mentions stays a bare URL, because a priority nobody asked for says '
    'the same thing as none and a crawler cannot tell it was invented; a '
    'priority outside 0 to 1 or a changefreq that is not one of the seven '
    'words sitemaps.org defines is refused rather than clamped or dropped, '
    'since a crawler discards the whole entry when a child will not '
    'validate. Adding that argument also found something worse: it is a '
    'call, and every parser of @DVPage(...) here stopped at the first close '
    'parenthesis, so a page carrying it was not discovered at all and its '
    'route was missing from the router on a build that succeeded -- and a '
    'policy written after it was not read, which generates a guarded page '
    'open.',
  ),
  (
    'AI',
    'DV.AI, and tools a provider can call',
    'A local adapter, structured outputs and embeddings, with provider '
    'extension points. A function marked as an AI tool is registered with a '
    'handler now, which it was not: the generated list carried a name, a '
    'description and a file path, so an assistant could read that a function '
    'existed and had no way to run it. Each tool gets a JSON Schema, because '
    'every provider requires one, and an argument of the wrong type is '
    'refused by name rather than coerced -- a tool that quietly received 0 '
    'for a number it could not read would run and be wrong, which is the '
    'thing a schema exists to prevent.',
  ),
  (
    'CSRF Protection',
    'On by default',
    'Token issue and verification wired through the request pipeline rather '
    'than left to the application.',
  ),
  (
    'Reversible Transactions',
    'DV.transaction',
    'context.afterCommit and context.compensate, so a failure unwinds what '
    'ran rather than leaving it half-applied.',
  ),
  (
    'Background and Durable Work',
    '@DVJob and DV.Queues',
    'Durable jobs and queues. background: true and durable: true on a backend '
    'function are sugar that compiles onto the same layer.',
  ),
  (
    'Authentication',
    'Four ways in',
    'WebAuthn assertions, SAML 2.0 built against signature wrapping rather '
    'than around it, LDAP over BER, and Sign-In with Ethereum bound to a '
    'nonce, a domain and a clock.',
  ),
  (
    'Cache',
    'Rendezvous hashing',
    'Keys spread across several servers. Adding or removing a node moves only '
    'that node’s share — with a modulo it moves almost everything, and the '
    'cache empties without reporting anything.',
  ),
  (
    'File Storage',
    'S3, Azure Blob, GCS',
    'Verified against Azurite and fake-gcs-server in CI, not against fakes. '
    'Azure signs the encoded path, which only a real server will tell you.',
  ),
  (
    'Search',
    'Meilisearch, OpenSearch, Algolia',
    'With highlights and facet counts, which an engine returns only when the '
    'query asks. Run against real Meilisearch and OpenSearch in CI.',
  ),
  (
    'APIs',
    'Flat-buffer envelope',
    'Form-data whose fields are binary buffers, so an int stays an int. Over '
    'text multipart the type is gone by the time a parameter is decoded.',
  ),
  (
    'Admin, Devtools, and Scaffolding',
    'dartvel inspect, dartvel mcp',
    'One versioned graph of routes, models, functions and jobs, with the '
    'source each was derived from. --json is a serialization of it, and '
    'dartvel mcp serves it to a coding agent. The dashboard itself is one '
    'per application and the backend serves it, at a path the project '
    'chooses -- a default rather than a constant, because a fixed admin path '
    'is most of why wp-admin is the most scanned URL on the internet. Its '
    'pages used to be ordinary pages in the client, with no guard on any of '
    'them, compiled into every build the application shipped; one of them is '
    'the page builder, whose stored documents the router prefers over the '
    'compiled page. They declare a policy now, the guard refuses when '
    'nothing is configured to answer it, a release build does not serve the '
    'dashboard unless the project asked, and a request refused for want of a '
    'sign-in is answered exactly as a route that does not exist -- an admin '
    'answering 401 where the rest of the site answers 404 tells a scanner '
    'the host has one, and where, before anybody has typed a password. The '
    'dashboard itself is written by dartvel build web-server into the '
    'directory the server already read from, which no build step had ever '
    'created -- so turning the admin on used to produce a 404 from a mount '
    'that was working correctly. It is a static page rather than a second '
    'Flutter application, because the backend serving it may be a container '
    'with no Flutter toolchain and no route to the internet, and for the '
    'same reason it loads nothing from another host: a dashboard that '
    'half-renders because a CDN is unreachable is worse than one that was '
    'never offered, and this is the page somebody opens when something is '
    'already wrong. Every reference in it is relative, so moving the mount '
    'somewhere private does not break it. It shows the models, routes, '
    'backend functions and jobs the application declares, each with the file '
    'it came from -- one dashboard for the whole application, which is why '
    'it reads a graph with no build target in it. What it reads is the graph '
    'the build captured rather than the running application, so queues, '
    'cache tags and the page builder are named in the specification and not '
    'in it yet, and dartvel dev does not serve it -- the dev server hands '
    'back the project\'s own index.html rather than a build output, so the '
    'way to see the dashboard today is a web-server build followed by '
    'dartvel preview.',
  ),
  (
    'Pages',
    'Every annotation',
    '@DVPage, @DVFunctionalWidget, @DVBackendFunction and @DVJob.handler all '
    'take a block body. No more one-line wrappers around a public helper.',
  ),
  (
    'Queues, Jobs, and Signals',
    'DV.Jobs and DVQueues',
    'Typed job payloads with retries, backoff, dead letters and idempotency '
    'keys. Signals stay context.signal and reactive models; cross-client '
    'delivery rides model sync rather than a second event system.',
  ),
  (
    'Database',
    'SQLite by default, and migrations that run',
    'Zero-config SQLite with WAL for local work and in-memory for tests, '
    'Postgres and MySQL with TLS, and one adapter API in front of all of '
    'them. Migrations run now, and did not: dartvel db migrate read a list '
    'of table names, printed a line per model saying it had migrated it and '
    'a total saying they were synced successfully, wrote a snapshot, and '
    'executed nothing at all. The statement that creates each table was '
    'generated, correct, and called by nothing anywhere. The generator now '
    'writes those statements where the command can read them -- from the '
    'same column list the model itself carries, so the migration and the '
    'queries cannot describe different tables -- and the command runs them '
    'against SQLite, which is the database the framework can reach from a '
    'command line. For Postgres or MySQL it writes the statements out and '
    'says it did not run them, because the CLI has no connection to a '
    'managed database and saying so is worth more than the green line it '
    'replaces. A table that already exists gains the columns its model '
    'gained, since CREATE TABLE IF NOT EXISTS does nothing to a table that '
    'is there and a query naming a column it lacks fails against a database '
    'just reported as migrated. The tenant column is the one that cannot be '
    'added quietly: rows written before it existed belong to nobody, a '
    'predicate on every read hides all of them from everybody, and the table '
    'reads as empty in a way nobody can tell from data loss -- so a table '
    'with rows is left completely alone rather than half migrated, and the '
    'command asks whose those rows are.',
  ),
  (
    'Testing',
    'dartvel test',
    'Fake auth, queues, mail, storage, AI and windowing, generated model '
    'factories, and a build that fails on an accessibility regression instead '
    'of warning about one.',
  ),
  (
    'Data Import, Export, and Reporting',
    'Order.Import.csv',
    'Generated CSV, NDJSON and Excel import and export per model. Resumable '
    'imports are chunked onto the queue with the header carried on every '
    'chunk, so a worker can always rebuild a row.',
  ),
  (
    'Deployment',
    'dartvel deploy',
    'Web and server targets to Firebase, Vercel, Netlify, Cloudflare or a '
    'custom host from one command, with the backend compiled to its Rust '
    'runtime and the client to its target.',
  ),
  (
    'CLI',
    'One tool',
    'create, dev, build, doctor, inspect, explain, i18n, queue, cache and sh. '
    'build runs generation for you; doctor says what each target can '
    'actually do; explain looks up any diagnostic code. The shell is part of '
    'it: a typed surface for project tasks, commands as values and results '
    'as values, reachable from Dart, from dartvel task and from dartvel sh.',
  ),
  (
    'Backend Function Request Lifecycle',
    'context.lifecycle.request',
    'Every call moves through received, decoding, authenticating, validating, '
    'authorized, executing, committing and encoding as a read-only signal, '
    'with trace, tenant and idempotency IDs carried the whole way.',
  ),
  (
    'Static Web Generation',
    'dartvel build web',
    'Per-route HTML built from the semantics tree a real browser produced, '
    'sitemap.xml and robots.txt, a service worker and install prompt, and a '
    'build that fails when a page would ship with nothing to see.',
  ),
  (
    'Internationalization and Localization',
    'Typed keys, CLDR plurals',
    'Translation keys are typed and extracted to ARB; plurals follow CLDR, '
    'not English. Locale negotiation reads the path, a stored preference and '
    'Accept-Language in that order, with a per-tenant default; mail and '
    'notification templates render in the recipient\'s language, and every '
    'prerendered page carries hreflang.',
  ),
  (
    'Dartvel Studio',
    'Visual builder, exports to code',
    'Pages are built from the same widgets the app renders, with drag-and-drop, '
    'an inspector, undo, mobile-first breakpoints and one-click export to an '
    'ordinary @DVPage. A box carries how its children sit in it -- the gap '
    'between them and how they align along each axis -- so a design with '
    'twenty-four points between cards is drawn with twenty-four, not with the '
    'framework\'s default eight, and a bordered, faded box is drawn as one. '
    'It says its padding on each of four sides, casts a shadow, and scrolls '
    'its own axis -- a card padded 24 across and 32 down is drawn that way, '
    'an elevated card is elevated, and a screen taller than the phone it runs '
    'on scrolls instead of showing the overflow stripe. A text node names its '
    'typeface and its line height, and a box can be painted with a gradient, '
    'rounded at some corners and not others, and placed by coordinate inside '
    'a stack; an image says how it fills its box, so a logo is not cropped to '
    'look like a photograph, and a text node says how many lines it gets, so '
    'a long title does not push the screen down. '
    'An image can be one the application holds rather than one it points at -- a key in file storage, read once however many times the page draws it -- so an imported design does not depend on somebody else\'s URL still working. Everything the page draws is in the exported source, which is handed to '
    'the analyzer in CI -- an export that compiles and looks wrong is found by '
    'whoever pressed export. Every mutation is also an edit another editor '
    'can apply. '
    'Pro adds what only matters with more than one person: reusable '
    'components, revision history, multi-user editing with presence, roles, '
    'an audit trail and approval before a page goes live. And Figma import, '
    'which is a design becoming an application rather than a picture of one: '
    'frames become pages and prototype links between them become navigation, '
    'components become components, auto-layout keeps its spacing and '
    'alignment, strokes and fades and centred text survive, a tilted layer '
    'arrives tilted, text arrives in the case it displays rather than the '
    'case it happened to be typed in, a link keeps its underline and a '
    'superseded price its strike-through, a soft-focus shape arrives soft '
    'and a frosted card keeps the blur behind it rather than in front of '
    'it, images are '
    'downloaded and kept rather than linked to URLs that expire, and a node '
    'keeps the size it was drawn at only where the designer fixed it -- so '
    'the result is not pinned to the width of the artboard. Padding arrives on '
    'all four sides, shadows arrive, and a screen whose content runs past its '
    'own frame scrolls: Figma positions everything absolutely, so the import '
    'can measure that rather than guess at it -- and it uses those same '
    'coordinates to keep hand-placed elements where they were drawn, relative '
    'to the frame they are in. Typefaces, line heights, gradients, corners '
    'that differ and the way each image fills its frame all arrive, and so do '
    'the icons -- vector paths carry no image '
    'fill, so Figma is asked to render each one and the picture is kept, '
    'which is the difference between a design that arrives with everything '
    'but its icons and one that arrives. And the import is not only live '
    'pages: it becomes a project somebody can keep, each page the file its '
    'route names and each image an asset in the repository with the pubspec '
    'lines that make it build.',
  ),
  (
    'Accessibility',
    'Audited at release, driveable by a switch',
    'dartvel build web audits the semantics tree a real browser produced and '
    'fails on a nameless control, an empty heading or a skipped level, unless '
    'waived with a written reason. Generated tables navigate by keyboard and '
    'announce cells; contrast and tap targets are checked against published '
    'minimums; motion follows the platform\'s reduced-motion setting. Kiosk '
    'and embedded pages are driveable by one or two switches, auto-scan, or a '
    'remote\'s D-pad, and a kiosk\'s key block never covers the keys '
    'accessibility needs.',
  ),
  (
    'PWA',
    'Installable, offline, and it keeps your writes',
    'dartvel build web writes the manifest, the icons from web/icon.png, the '
    'offline page and a service worker that caches assets and keeps an '
    'outbox: a write made while the network is gone is answered 202 and '
    'replayed, in order, once it is back. That last part is proven in a '
    'real Chrome on every push, not read off the generator. The install '
    'prompt asks the browser now, and did not: it returned a value only a '
    'test could set, so it reported an acceptance whatever the person at the '
    'screen chose and then marked the application installed -- which hides '
    'the button, so an application somebody declined could never be '
    'installed from inside it again. The binding that opens the browser\'s '
    'own dialog was written and called by nothing at all, so tapping Install '
    'opened nothing. It waits for the answer now, because the browser only '
    'opens the dialog when asked and reports the choice afterwards.',
  ),
];

/// Half built: what is present and what is absent, in the repository's own
/// words. The checker holds this list to the index's Partial sections exactly.
const List<(String, String, String)> partial = <(String, String, String)>[
  (
    'Generated Model Pages',
    'Model.Page(...), wearing its own icon',
    'Public pages from a model, with .async, .signal and .fromId. Static '
    'paths come from the model rather than a route written out as a string. '
    'A model page can wear its own favicon now, and could not: the field '
    'existed and the head writer emitted it, and nothing anywhere set it -- '
    'the resolver filled the title, the description, the image and the '
    'structured data and left the favicon empty, so every product, article '
    'and profile wore the application shell\'s. There was nothing to fall '
    'back to either, since no favicon was configured anywhere. A model '
    'declares one, a module\'s models carry the module\'s, and '
    'dartvel.seo.favicon is the application\'s -- read rather than guessed '
    'from web/favicon.png, because a file that happens to be there is not a '
    'decision anybody made and a page quietly wearing the wrong icon looks '
    'exactly like the feature working. Absent: the resized, compressed, '
    'content-hashed derivative of the featured image the specification also '
    'asks for. That is why the field is separate from the image in the first '
    'place -- pointed straight at it, a page would serve a '
    'several-hundred-kilobyte photograph as a thirty-two pixel icon, which '
    'is worse than the icon it replaced -- and deriving one per request from '
    'a URL a row supplied is a fetch a server should not make.',
  ),
  (
    'Lifecycle Signals',
    'Five of six change',
    'DV.lifecycle.app and .build, context.lifecycle.page, .request and '
    '.transaction. Application code observes them; it does not assign them. '
    'Five of the six move. The kiosk signal is driven by the kiosk host and '
    'the transaction signal by DV.transaction, and the request '
    'signal now '
    'changes on a backend function that asks for a context -- received, '
    'executing, then preparing a response or failed. It never reports '
    'completed, because the body may be a stream the handler no longer owns, '
    'and saying a request finished while it is still sending would be a '
    'state that lies rather than one that is missing. The page signal moves '
    'too, on every generated route: there was no lifecycle extension on a '
    'build context at all, so the line the specification writes did not '
    'compile in a page, and the getter threw for want of a signal nothing '
    'created. It runs from created to ready to active after the first '
    'frame, then says it is leaving before it has left. The application '
    'signal reports what the platform gives it, and reported two of its ten '
    'states: booting and ready, both set while the application was starting, '
    'and nothing ever set another -- so an application watching it to save a '
    'draft when it goes into the background never saw that happen, which '
    'reads as an application that is never backgrounded rather than a signal '
    'that does not say. Flutter reports it already, and the mapping is where '
    'the judgement is. Hidden counts as backgrounded as much as paused does, '
    'because on a desktop it is the whole of it: a covered or minimised '
    'window never reaches paused. Inactive counts as nothing -- it is a '
    'notification banner or an incoming call, with the application still on '
    'screen, and treating it as backgrounded would flush an application\'s '
    'state every time a message arrived. Absent: the states '
    'that belong to a data fetch or a route transition rather than to a '
    'widget, named rather than emitted at moments that merely resemble '
    'them; and anything that advances the build signal, which describes a '
    'build pipeline running in a process the application is not.',
  ),
  (
    'Scheduling',
    'Cron on both sides, and it runs now',
    'Five-field cron parsed the way cron actually reads it, day-of-month OR '
    'day-of-week, with nextAfter for the next tick and a scheduler that '
    'dispatches onto the queue rather than running inline. The scheduler was '
    'built and nothing ever started one: the only place in the repository '
    'that constructed it was its own unit test, so a schedule declared on a '
    'backend function travelled into a generated list and stopped, and this '
    'entry said it ran. A served backend now registers every declared '
    'schedule and ticks, and an application with none starts no timer. The '
    'client half runs too, started by the generated runtime, and its '
    'handlers live in their own file: the backend imports the other one, '
    'and a schedule declared on a page would otherwise pull Flutter into a '
    'server that has no screen. A schedule can also say for itself whether '
    'the periods missed while the process was down are run when it comes '
    'back. Saying nothing is not the same as saying no: a schedule that '
    'wrote it down has decided about itself and outranks the blanket '
    'setting the application starts its schedules with, which is what a '
    'nightly digest needs -- four of them the morning a server comes back '
    'is worse than one missed -- while a rollup that writes a row per day '
    'needs the opposite. A value the build cannot read stops it, because a '
    'generated schedule carries the answer rather than working it out '
    'later.',
  ),
  (
    'Middleware',
    'Ten run, tracing wraps, two guard the body, five say why not',
    'Composable middleware around backend functions, with the request '
    'lifecycle observable as a signal. The nineteen keys did nothing until '
    'recently. The annotation had one reader -- a check that the name was '
    'spelled correctly -- which then dropped the list, so nothing reached '
    'the generated router and no request was ever handled differently for '
    'declaring any of them. The implementations were not missing: the rate '
    'limiter, the security headers, locale negotiation, maintenance mode, '
    'tenant resolution and the rest were all written and tested through a '
    'chain each test built by hand, and nothing else ever built one. Ten '
    'now run, in the order declared, wrapped around the handler so a '
    'refusal answers before the function does and resolved headers reach a '
    'response that exists. CSRF is already enforced on every state-changing '
    'request whether it is declared or not. Two more cannot be middleware at '
    'all -- the chain runs around the handler, and by the time it has '
    'anything to say the body is already in memory, so a limit that arrives '
    'there is not a limit. The body and upload limits are checked where the '
    'body is read instead: the announced length first, without reading a '
    'byte, and then the read itself capped for a sender that announced '
    'nothing. Declaring both gives each shape its own number, which is the '
    'point of there being two -- a JSON body of several megabytes is a '
    'mistake and an upload of several megabytes is the feature. The '
    'tracing wraps the handler and the chain both, which is where it has to '
    'be: a request refused by a rate limit is still a request, and a trace '
    'covering only the ones that got through is a latency graph with the '
    'slow half missing. One of the ten is the content security policy, '
    'which sends what the project configured under dartvel.security.csp -- '
    'and a route that declares the key with nothing configured fails the '
    'build, because a policy is a statement about one application\'s own '
    'scripts and origins, no default could be right for another, and an '
    'empty header is not no policy: a browser reads it as one that allows '
    'nothing. The remaining five fail the build naming what to '
    'use instead, because somebody who wrote one of them has decided '
    'something is being enforced, and serving as though it were is not a '
    'smaller failure for having been quiet about it. Two of those five '
    'now name something a developer can actually do. CORS and '
    'compression are answered for the whole server rather than per route '
    '-- the CORS headers go on every response including the preflight, '
    'which never reaches a route -- and the refusal used to say to pass '
    'them to the serve call. Nobody using Dartvel writes a serve call. '
    'The generated backend makes it, and it read no configuration, so an '
    'application could not set a CORS policy at all and could not turn '
    'compression off. dartvel.server is read at build time and emitted '
    'into that call: the origins, methods, headers, credentials and '
    'preflight max-age of the policy, and whether responses are '
    'compressed. Saying nothing means no CORS headers rather than '
    'answering every origin, since that is the single setting most '
    'likely to be wrong and a default nobody chose should not be it. A '
    'value the build cannot honour stops the build: credentials from any '
    'origin, which a browser refuses itself so the policy would allow '
    'nothing; an origin written with a path or a trailing slash, which '
    'never matches the Origin header and reads as CORS simply being '
    'broken; and compression written as the string false, which is not '
    'a boolean and would leave it on for somebody who wrote down that '
    'they wanted it off.',
  ),
  (
    'Multi-tenancy',
    'All three strategies, and a shared database that filters',
    'Tenant resolution is built: the current tenant is resolved from the '
    'configured source, the middleware makes it current for the rest of the '
    'request, presence is scoped by it, and it is held in a zone so it '
    'follows async work instead of leaking between concurrent requests. '
    'Filtering of generated model queries is built too, and was not until '
    'recently: the word tenant appeared nowhere in the model generator and '
    'nowhere in any database adapter, so on a shared database a query '
    'returned every tenant\'s rows while this entry said the feature was '
    'shipped. A model that asks for it gets a tenant column, a predicate on '
    'every read, the current tenant written into every write, and a delete '
    'that cannot reach another tenant\'s row. Those arrive together on '
    'purpose: a column written and not filtered on leaks, one filtered on '
    'and not written hides every row, and both look exactly like the feature '
    'working. It is per model, because a single-tenant application should '
    'not carry a column it never reads and a table deliberately shared '
    'across tenants would be broken by a predicate it never asked for. '
    'Asking for tenant scoping and public pages on the same model is '
    'refused: a public page is rendered with no request, so there is no '
    'current tenant to scope it by, and the row would be served at a public '
    'URL to anybody -- the exact leak the column exists to close, on the one '
    'path that never sees it. Which model is scoped is read from that '
    'model\'s own arguments now, and was read from the whole file, so one '
    'tenant-scoped model scoped every model declared beside it. The case '
    'that breaks is the one the rule was written for -- a currency list, a '
    'country table -- and the symptom is the opposite of a leak: rows '
    'written before the column existed belong to no tenant, so a predicate '
    'nobody asked for hides all of them from everybody. '
    'All three strategies do something now. Two of them did not: '
    'schema-per-tenant and database-per-tenant were an enum value and a '
    'function that built the right name and was called by nothing, so '
    'choosing either produced exactly the queries the shared strategy '
    'produces, against exactly the same database. Every tenant read every '
    'tenant\'s rows on the two settings chosen to prevent that, and it '
    'looked like it worked -- every query returned rows and the application '
    'behaved. A schema per tenant qualifies the table name, resolved when '
    'the statement runs rather than written in, because which schema is '
    'asking is a fact about the request and two requests are in flight at '
    'once. A database per tenant does not qualify the name, since the '
    'connection is what differs; the adapter is resolved per tenant instead, '
    'opened once each and kept, because a connection per query is a pool '
    'nobody wrote and on SQLite a second write lock over one file. Choosing '
    'that strategy without saying how to open a tenant\'s database is '
    'refused, because the fallback is one database for everybody -- the '
    'leak it exists to close, returning rows the whole time. Turning tenant '
    'scoping on for a table that already has rows is handled too: the table '
    'is left entirely alone until somebody says whose those rows are, since '
    'rows written before the column existed belong to nobody and would be '
    'hidden from everybody, leaving a table that reads as empty in a way '
    'nothing tells apart from data loss. Absent: creating the per-tenant '
    'schemas themselves, which needs a list of tenants the build does not '
    'have. A raw query an application writes itself is checked now, and was '
    'not: the generated queries carried the predicate and nothing else did '
    '-- a report, a dashboard count, a join the generator cannot express, a '
    'query written before the model was scoped -- each returning rows that '
    'looked plausible while showing one tenant another tenant\'s data. The '
    'generated client registers which tables are scoped, because the '
    'database layer has no idea what a model is, and a statement naming one '
    'without mentioning the column is refused. It is deliberately coarse: a '
    'false positive is a refusal somebody reads and fixes, a false negative '
    'leaves the old behaviour, and the one thing it never does is guess in '
    'the direction of allowing. Writes are checked too -- the worse half, '
    'since a write without the column puts a row in the table belonging to '
    'nobody that every tenant then cannot see -- and a name matches on a '
    'word boundary, so workorders is not orders: refusing that would teach '
    'people to reach for the escape hatch out of habit, which is how an '
    'escape hatch stops meaning anything. Crossing tenants deliberately is '
    'DV.Database.acrossTenants, for an operator report or a support tool: '
    'not hard, but written down.',
  ),
  (
    'Sensitive Model Fields',
    '@DVModel.sensitiveField(); encrypted: true refused',
    'Excluded from logs, AI context, traces, analytics, public serialization, '
    'search, generated pages, tables and admin by default. Reaching a client '
    'takes an explicit policy. encrypted: true is not implemented: there is '
    'no server-side field-encryption key surface yet, so a field declaring '
    'it fails generation, naming the model and field, rather than being '
    'stored as plaintext under a flag that says otherwise.',
  ),
  (
    'App store publishing',
    'One command to a store, and every refusal before the upload',
    'Present: dartvel publish takes a built application to Google Play, App Store Connect, TestFlight or Firebase App Distribution, declared once in pubspec.yaml. The work is an upload of a binary that took minutes to produce, so every refusal comes before it: a track nobody publishes to is refused rather than corrected to the nearest, credentials that were never declared are refused rather than left to a tool that stops to ask a pipeline with nobody to answer, and App Store Connect is refused off macOS at the start rather than with "command not found" at the end of a long build. --dry-run shows what Dartvel would do to a store account before it does it, and the upload uploads and nothing else. Absent: the stores are driven through their own tools rather than their APIs, so a machine without one is told to install it; nothing has been published from CI, which needs an account and a signing identity; and metadata, screenshots and staged rollouts are deliberately left alone.',
  ),
  (
    'Home Widgets',
    'Generated pages, packaged on Android and on Apple',
    'Present: @DVHomeWidget on any widget generates the page the specification describes -- a route at /widgets/<id> that centres the widget\'s content, which is what lets the widget launch the application at itself and a page navigate back to it -- and the application\'s list of them beside the router, for the packaging that puts them on a home screen. The identifier is the class name in kebab case, one rule in one place: a widget somebody has already put on their home screen is found again by it, and two spellings of the route is a tap that opens the not-found page. A build for a target with no home screen leaves them out and says which ones and why, or is refused outright when the project asks to be -- what must never happen is the third option, a widget quietly carried into an artifact that can never show it. On Android it is packaged: a provider, the metadata a launcher reads before anybody places one, a layout, and a receiver in the manifest. It draws the platform\'s own views rather than the Flutter tree, because a home screen is composed in the launcher\'s process and that cannot host a Flutter engine -- and the tap is what the specification actually asks for, a deep link to the page Dartvel generated. On iOS and macOS it is packaged as WidgetKit: a separate bundle with its own sources, Info.plist and entitlements, and an Xcode target spliced into the project that builds it, embeds it in the application and waits for it rather than racing it. Only one of the ways that goes wrong is loud -- a project file Xcode cannot parse -- and the rest are silent: a target absent from the project\'s target list is never built, an extension with no embed phase is built and left behind, and a second build that appended rather than replaced would give Xcode two targets with one name. The App Group is claimed at both ends, because an extension entitled to read a container the application never writes to renders its placeholder forever and nothing errors at either end. SwiftUI rather than the Flutter tree, for the same reason Android draws the platform\'s own views. The tap lands on both now: the URL arrives at the iOS app delegate, so the build writes the capture there -- two overrides, because a cold launch carries the URL in the launch options and never reaches open(url:) while a warm one arrives there with no launch options, and an implementation with one of them works in whichever case somebody happened to try. The Dart side reads it back and takes it away again, since a link left in the defaults would be opened on every later start. The shell properties are the page\'s now: @DVHomeWidget takes the arguments @DVPage takes, through the same parser, and the generated page is wrapped in the shell that applies them. It could not carry them at all before, because both scanners matched @DVHomeWidget() with the parentheses empty -- so writing what the specification describes deleted the widget without a word, and the annotation sat in the file saying otherwise. The title is the property that also leaves the application: a launcher\'s picker and the widget gallery each ask for a name and each were handed the identifier, so a widget was offered to people as step-counter, a route segment, among the names of their applications. Sharing the tree and the state is built as far as the platform allows, and the limit is stated rather than worked around: the surface on a home screen is composed in a process that cannot host a Flutter engine, so what is shared is the page at /widgets/<id> -- the same widget, the application\'s own tree, the same signals and globals as every other page -- and what crosses to the home screen is data. That crossing did not exist: the generated Swift read a key nothing wrote and the Android provider drew a constant, which is a widget showing its own name for ever and looks exactly like one that works. DVHomeWidgets.publish writes it, through one key rule in core that all three halves read, because a key spelled twice is a correctly built and correctly signed widget showing its placeholder for ever. Absent: an immediate refresh on Apple, since WidgetCenter is Swift-only and has no Objective-C class to message, so a published value is picked up on the timeline the provider asked for rather than at once; and @DVHomeWidget on a class rather than a function, which the declaration pattern reads as the class being extended.',
  ),
  (
    'Modules',
    'Mounted, with their routes, a verified manifest and their deployment modes',
    'Present: a module is a whole Dartvel application a parent mounts. The build finds it, takes its own route base off and puts the mount point on -- /products/:id standalone is /store/products/:id mounted -- generates the module before the parent, and serves its pages from the parent\'s router; they are in the route index and sitemap, tagged with the module they came from, and DV.Modules.<id> is the module the build mounted. Its assets are the paths that find them in the parent, its pages are typed targets that keep their names wherever it is mounted, and its globals are its own -- shared only where the declaration says: the module\'s pubspec names what it exports, the parent\'s what it hands down, and DV.Modules.<id>.global<T>() refuses anything else by naming the line that would allow it. A federated module publishes a signed manifest, generated from its own project by dartvel modules manifest so it cannot go stale, carrying its own routes rather than any parent\'s mount -- its identifier, version, routes, capabilities, assets, modes, public functions and signals, the parent it needs and where it is served from -- and the parent verifies it before mounting: a manifest edited after signing, one signed by a key it does not trust, one for a different module, an older version replayed over one already accepted, routes that collide with its own, or a capability the target lacks are each refused with the reason. A module says what hardware it needs and a build for a device profile refuses when that profile does not provide it or a fallback, so an image is not shipped to a lobby with a section that cannot run on it. dartvel doctor fails on a module the build cannot mount -- a missing project, a manifest that will not verify -- because an application that ships without the section on a green build is how a rotated signing key goes unnoticed. A federated module is mounted from its verified manifest rather than from the source beside it, and generates no import and no page: it is deployed elsewhere, and building a second copy from source would work until the two versions differed. Its routes still appear in the parent\'s route index and sitemap, under the parent\'s own domain, and the parent answers them by sending the reader to the module with the matched parameters carried across -- /store/products/7 arrives there as /products/7 -- so a micro-site serves its own HTML without disappearing from the site it is part of. Each module\'s shell, auth, theme and data modes are read and reach the running application, with a federated module defaulting to what its own deployment can honour and an explicit auth: inherit or data: shared on one refused -- there is no parent session to inherit and no shared database, so it would run with neither and read as a login bug. A split-backend module\'s client asks the registry where its own functions answer before falling back to the application it was compiled into, so the same module calls its own API standing alone and its deployed service when mounted; declared without an address it is refused, because the only other symptom would be a 404 from an application that looks right. What a module compiled into the parent contributes is the parent\'s to run: its backend functions answer in the parent\'s router at the module\'s own paths, its cron functions are in the parent\'s schedule, its AI tools in the parent\'s tool table, and its tables are created with the parent\'s when it shares the database. Two functions claiming one path, or two models one table, are refused rather than one of them quietly losing. A split-backend or federated module contributes none of it, running its own in its own deployment. A module\'s auth mode decides whether the parent\'s guard applies to its routes: inherit puts them behind it, public leaves them open, because a documentation module mounted into an application everybody has to sign into is a documentation module nobody can read. A module\'s theme mode decides what its pages render in and its shell mode what surrounds them -- inherit, extend, override or isolated for the first, and none as well for the second, with theme outermost so a module that overrides both is drawn in its own theme inside its own chrome. Its data mode decides where its models live: the parent\'s tables shared, its own names in the parent\'s database when schema-isolated, its own database when database-isolated, and refused outright when remote, because a module whose data is somewhere else has no table here to read. Every mode is applied at run time now rather than merely read. A module\'s own lifecycle signal moves too, and did not: it was created at discovered and moved by nothing, so an application waiting for a module to become usable waited forever. What registering says depends on where the module runs, because calling every registered module active would claim something the parent cannot know -- a federated module is deployed elsewhere, and whether it is up is not visible from here. Compiled-in modules are active, a split backend is active because its pages are compiled in, and a federated one is mounted: the parent has it at a path and cannot see whether it is serving. Absent: the exports block. What a module declares about its globals is read and enforced; the broader declaration the specification also writes -- exports, with pages, functions and a list of models -- is read by nothing, which is the same failure the globals one had before it was built, one level up. A module compiled into a parent contributes its pages to the route index, its functions to the parent router and its models to the parent migration whatever that block says, so an author who writes pages: false is refused nothing and told nothing. Named rather than half-built, because two of the three meanings are not obvious -- whether a list of models governs which types the parent may name, which tables the migration creates, or both -- and guessing one would produce a declaration that appears to work while enforcing something nobody chose.',
  ),
  (
    'Platform',
    'Runtime APIs everywhere; Linux bindings behind most names',
    'Present: the platform and screen APIs, FFI/JNI binding registration, and on Linux the bindings for clipboard, window, notifications, shortcuts, menus, printing, dialogs, kiosk keys and the device APIs. Absent: the names with no host API to reach on each platform -- 32 on Linux, 24 on web, 33 on Windows, 33 on macOS, 30 on iOS -- many of which do not apply there at all.',
  ),
  (
    'Mail and Notifications',
    'Every channel; SMTP against a real server, push not yet',
    'Present: email, in-app, push and web push with a VAPID signature pinned to the published P-256 vectors, local and test providers, and templates rendered in the recipient\'s language. The SMTP provider is exercised against a real SMTP server in a container, with the source of what arrived read back -- which is the only way to see the half of this that is accepted and wrong, and it found two things. A subject with an accent in it went down the wire as raw UTF-8 in a header that has to be ASCII: the server took it, and the clients that do not guess the encoding show it as mojibake to whoever was sent it. The body declared no transfer encoding, which means seven-bit, which it was not. Both are fixed and both are now checked against a server rather than against a connection this repository wrote. Absent: no provider has been exercised against a real APNS or push service.',
  ),
  (
    'OTA Updates',
    'Staged across a fleet, but not native patches',
    'Present: page bundles ship as data through DV.Updates and need no native patching, on named channels, and a staged rollout decides from the device and the version rather than at random -- so a device asked twice is answered the same. One question is asked and answered in one place: the channel\'s offer, the device\'s place in the rollout, a pinned version, a skipped one and a kiosk\'s maintenance window, so a check says whether to apply now, why not when not, and when it will be, and applying something the check held back is refused with the reason rather than quietly skipped. Absent: Shorebird-backed native patch application.',
  ),
  (
    'Billing',
    'Stripe and Paddle, and a price that is a price',
    'Present: checkout for a plan\'s configured price and webhooks that grant and revoke entitlements, each believed only when its own signature matches in constant time within five minutes. A model priced with @DVModel(billable: true, nativePrice: 100) carries that price now, and carried nothing before -- both arguments were declared on the annotation and read by nothing anywhere, so a model marked billable was a model with a comment on it. A price needs three things before it means anything. A currency, which dartvel.nativeCurrency has always been the setting for and which nothing read: a model declaring a price without it fails the build rather than being handed a guess, because a hundred of the wrong currency is a plausible number nothing downstream can catch. A rule for what the integer counts, because most of the world uses hundredths and some of it does not -- a hundred yen is a hundred yen, and a framework that divided every currency by a hundred would price a coffee at a hundredth of one with nothing about the number looking wrong. And a conversion that refuses: rates are the application\'s to set, so converting without one throws rather than returning the same integer under a different code, an inverse is never assumed because a published rate has a spread, and crossing currencies that count differently rescales -- ten dollars at 150 yen is 1500 yen, not 150000. A price on a model nothing can charge for, a negative price and a currency that is not a currency each stop the build; billable with no price does not, because usage-based billing is in the list and a model billed by the meter has no unit price. The example prices a product and its pricing page renders that price rather than repeating the number. Absent: App Store and Play Billing purchases, which need the store bindings; rates come from the application and no provider supplies them; and localisation does not yet pick a display currency on its own.',
  ),
  (
    'Desktop, Embedded, and Qt-Critical Capabilities',
    'Built on Linux, and most of it on Windows and macOS',
    'Present on Linux: global shortcuts, the application menu, printing, system dialogs, file associations, app links and deep links, the launch that opens what the app was started with, the device and fleet APIs -- manifest, health, watchdog, provisioning, diagnostics -- and startup measured phase by phase, published beside the live window list and carried in the diagnostics bundle. Present on Windows and macOS, each proven on its own runner: global shortcuts delivered by id, the application menu, the tray icon with its menu, and the device APIs. An application registers what it opens while it is running, on all three -- the user\'s own desktop entry and MIME package on Linux, the per-user half of the registry on Windows, the running bundle with LaunchServices on macOS -- which is the half an installer normally does and an application copied into place has nobody to do. Drag and drop is present on all three: a window takes the files or the text the desktop drops on it and says where it landed, through GTK on Linux, an OLE drop target on Windows and a dragging destination on macOS. The tray is present on all three too, on Linux as a StatusNotifierItem and its menu on the session bus. NFC is present on Linux through neard -- whether there is a reader that could read now and what is on the tag, with no tag answering as nothing and no reader saying so. Writing one is present too -- the half that hands somebody a card rather than reading theirs -- and it is fussier than it sounds, because nearly every way it goes wrong still reports success: a link goes into a URI record and not into text that looks like one, since a link written as text reads back correctly and does nothing when a phone touches it; a text record carries the language code NDEF requires and some readers show an empty record without; an empty value is refused, because a tag written with nothing on it cannot be told from one never written; and a locked tag is refused with the reason, so nobody presents the same card twice. Bluetooth is present on Linux through BlueZ: whether the radio is on, the adapters, and every device the machine knows about, so a fleet can tell a peripheral that is unpaired from one that is out of range -- and a machine with no bluetooth service at all says that rather than answering with an empty list. Pairing, connecting and forgetting are present too, which is what lets a fleet fix a reader that has come unpaired instead of sending somebody to the lobby. The answers are the fussy part: a device already paired is a success and not a failure, so nothing retries forever against hardware that works; a pairing that failed because no agent is registered says that, because on a device with nobody standing at it there is no passkey to answer and the radio is not the problem; connecting something unpaired says to pair it first rather than leaving a timeout to be explained; and forgetting asks the adapter the device is actually on, since on a machine with two the other one removes nothing and reports success. The USB bus is present on Linux -- what is plugged in, with each device\'s ids and what it says about itself, which is what tells a fleet the scanner is unplugged rather than broken. Talking to one is present too, through usbfs: open it, claim the interface, write and read. The ioctl numbers are computed from one rule and checked against the kernel headers, because each packs four fields and getting any of them wrong still produces a valid ioctl for something else. The errors say what they actually mean on a device node -- a permission error is a udev rule nobody wrote rather than a bug in the calling code, a busy interface is a kernel driver holding it that has to be detached, and a timeout is a device that may answer next time rather than one that has gone. The serial port is present on all three desktops: the ports with stable names, opened in raw mode -- because a line left in a terminal\'s default mode turns carriage returns into newlines and stops at the first 0x1a, so text works and the first binary frame arrives short -- read with a timeout, written, closed, and exercised in CI against a real pseudo-terminal on both -- macOS is a port rather than a copy, since its termios and its baud rates are not Linux\'s. Windows is the third: the ports come from the list Windows itself keeps in the registry, sorted by number so COM10 comes after COM9 rather than before it, every one of them opened through the device-namespace path and not only the ones above COM9, and an open that fails says which port and why in words -- not there, or held by another program -- rather than a number somebody has to go and look up. An eLinux bundle boots into the application: autostart, restartOnFailure and a declared watchdog become the systemd unit beside it, and CI hands that unit to systemd itself, so a directive systemd would reject is found at build time rather than at boot. Absent: USB transfers, Bluetooth pairing and I/O, and writing NFC tags.',
  ),
  (
    'Kiosk Mode',
    'Policy, clock, windows and desktop enforcement; mobile and embedded per target',
    'Present: the policy, state machine and enforcement matrix checked by dartvel doctor; named policies generated as DVKioskPolicies, with a device profile\'s kiosk entry over the section when dartvel build --device-profile selects it; the device-scope kiosk installed at start as DV.Platform.display.kiosk; display-scope kiosk windows pinned to a display; the session clock with its countdown and reset, on DV.lifecycle.kiosk; on Linux hardware-key blocking that never covers the keys accessibility needs, pointer confinement and notification suppression, on Windows hot keys and pointer confinement with what Win32 refuses reported unenforced, on macOS the presentation options that disable process switching and force quit, in a browser Fullscreen, Keyboard Lock and Pointer Lock with every gesture-less refusal reported; the screen-side host with its diagnostics screen; restart-loop detection; the sensitive-field analyze rule; dartvel inspect kiosk, the effective policy per target and per window with each value\'s source; and an update policy that decides when an update may be applied -- inside a maintenance window that may run past midnight, only with staff present, or immediately -- where a required update does not wait but resets the session before it lands. on Android lock task mode held on the running Activity, which a JNI binding reaches through the application\'s own lifecycle callbacks rather than a platform channel, with a declared device kiosk building the lock-task launcher the deployment needs -- the application as the home screen, and the device-admin component that makes the lock silent instead of a dialog nobody is standing at, proved on an emulator with Android\'s own dumpsys as the second opinion. Native enforcement is present on embedded Linux, where it means something different from everywhere else: there is no window manager, so the application already owns the display and what has to be stopped is somebody leaving it. A virtual terminal switch puts a login prompt in front of a running kiosk without the application ever knowing, and the console underneath paints kernel messages over the framebuffer while the application draws on it. Both are held, both are attempted independently so a device that allows one gets the one it can, and whatever could not be held is named with the reason and carries DV-KIOSK-007 -- because a kiosk that could not hold and says nothing reads exactly like one that did. Five containment keys in the specification -- an external-route rule, clipboard and text-selection blocking, cursor hiding and screen dimming -- were read by nothing. The parser took the routes, input and display maps and pulled three named children out of each, so those five were read straight past. Naming them as problems was the first step, because an unrecognised value always produced one while an unrecognised key produced nothing, and that is the worse of the two: somebody who writes the clipboard rule into a kiosk has decided the clipboard is locked, and silence reads as agreement. Four of the five are enforced now -- the four Dartvel can honour on its own, with no platform binding underneath. Text selection overrides what a page declares, because the annotation is the page\'s preference and the policy is the deployment\'s decision. The clipboard refuses in both directions and before the platform binding rather than after: blocking copy while allowing paste leaves a kiosk somebody can type into from whatever the last person left there, and asking the platform first would put the text on the clipboard and then report a failure. It refuses rather than quietly doing nothing, since a copy that reports success and copies nothing cannot be told from a clipboard that is broken. Neither is implied by kiosk mode -- an order screen showing a reference number is more useful if the number can be copied. What they deny follows the kiosk state rather than the process, so staff mode lifts it and a refused exit does not: somebody with the exit method has been trusted with more than the person in the queue, and an engineer who cannot copy the error code off the screen reads it down a phone. Hiding the cursor is the third: a pointer nobody can move is what a touchscreen kiosk shows when it is left on, sitting wherever the last mouse left it and reading as a frozen screen. Auto is the default and means touch-only, which cannot be read off the build target -- a kiosk on a Linux box with a touchscreen is a desktop build -- so it asks whether a pointing device is attached, and keeps asking, because an engineer plugs a mouse in to service the machine. Dimming the screen is the fourth, and it is half of what the key asks for: a kiosk shows one attract screen for months and burn-in is what that does to a panel, so the surface darkens after the configured idle and any touch brings it back -- the backlight is not turned down, which needs a platform binding, and both the setting and the signal say so rather than looking like they save power. The tap that wakes the screen is spent waking it, because somebody touching a dark panel means come back rather than buy whatever is under a finger they cannot see. A dim set longer than the idle timeout is refused outright: the session resets first and restarts the clock, so it would never arrive at all. The one that remains reports exactly as before, because naming four of five as done would leave it looking implemented by association. Absent: native enforcement on iPadOS, Tizen and webOS; what an external route should mean, distinct from the allow list; and, for the four that are built, a clipboard the operating system shares with another application, the system cursor outside the application\'s own surface, and the backlight -- none of which a rule written in Dart reaches.',
  ),
  (
    'Terminal Rendering',
    'A backend you opt into at build time',
    'Present: the terminal backend is linked only when asked for, through the dartvel_cli_flt fork; the terminal\'s size as a signal, read again on every resize; and launch negotiation wired into main -- --tui, no display with both backends, and the hand-off to the terminal runner beside the GUI binary. A Dartvel application renders in a terminal, verified in a pty: it could not before, because the bundle build reads a compiler configuration for a project\'s build hooks that nothing wrote where it looks, so the job proving the terminal had been rendering the embedder\'s own sample instead. Absent: the fork\'s own renderer, Kitty with an ANSI fallback, and a distributable runner.',
  ),
  (
    'Multi-Window',
    'Windows, displays and the single-instance launch',
    'Present: window identity as canonical URL, the Linux open binding, display enumeration, the exit policy, owned windows, honest modality, the single-instance launch that opens what the app was started with and hands a later launch to the first process, workspace restore, tear-out, display-scope kiosk windows, the Studio window inspector, dartvel inspect windows with the live list a running app publishes, and the performance contract: open-to-ready, tear-out handover, shared-store coalescing, size and spills, and restore duration are measured, the four diagnostics are findings, and dartvel analyze performance reads them. Device profile display names reach the generated client through dartvel build --device-profile, and every DV-WINDOW code has an emitter. Display enumeration works on all three desktops. The shared store reads its own tuning now, and did not: the specification documents four numbers under dartvel.windowing.sharedState and the build read none of them. Two were constructor parameters already, with defaults equal to the documented values, so a project that set a 64Kb spill threshold got 32 and one that set a 200ms debounce got 50 -- accepted, built, and the number in the pubspec was decoration. Kilobytes there and bytes in the constructor, converted at the build, because passing the number straight through would have spilled at 64 bytes. Absent: the other two, pollMs and sweepAfter, which have nothing behind them at all -- there is no separate-process polling backend and no sweep of spilled files -- and the three web and Android keys, documented and read by nothing.',
  ),
  (
    'Tab Workspaces',
    'Tabs that tear out, hand over between windows and persist',
    'Present: the tab strip, reorder, tear-out gated on capability, the empty-window rule, duplicate tabs, deduplication by route, a switcher on TV and watch, persistence scoped to the tenant and the user that drops routes that no longer resolve, and a re-dock that hands the tab over instead of rebuilding it -- the element moves between workspaces in one frame, so what was half typed, where the list had been scrolled to and the controllers behind them are the same objects on the other side. Absent: the drag cannot leave a window. The OS holds the pointer in the window it went down in and Flutter routes the whole drag to that view, so no strip elsewhere ever sees it; a cross-window move is an action on the tab menu instead, and tear-out into a brand-new window still builds the route from scratch.',
  ),
  (
    'Secrets and Environments',
    'Declared, rotated, and kept where the platform keeps keys',
    'Present: the declaration manifest and its analyze rule, rotation hooks, dartvel key generate | rotate | status, and the application key in the Secret Service on Linux, DPAPI on Windows, the Keychain on macOS and a non-extractable WebCrypto key on the web, with a file only the user can read as the fallback. Absent: the Android Keystore.',
  ),
  (
    'Web Server Rendering',
    'Pages assembled on request, from the route\'s data',
    'Present: the request pipeline the spec describes, given a resolver for the route\'s data -- route resolved with its parameters, page data resolved by the declared mode (awaited, cached, stale-while-revalidate, or deferred to the client), visibility checked with 404 and 401, the head and JSON-LD structured data generated from the data, the page\'s favicon, crawler-visible text, the Flutter bootstrap, and streaming that sends the head first. The resolver is generated from the application\'s models: a public model page is its row\'s title, content, image and published flag, read from the database when the page is asked for, hidden when unpublished. The kept pages can live in a shared cache, so a second server serves what the first resolved, and a page\'s schema.org type is the one its model declares.',
  ),
  (
    'Embedded, Television, and Extension Build Targets',
    'Builds that exist; devices that have not run them',
    'Present: tizen and vscode build. Absent: neither has been run; fuchsia\'s engine does not build at Flutter 3.44.5; webOS and Sony eLinux ship a Dart below the 3.12 floor, so their embedders cannot resolve the example.',
  ),
  (
    'Monitoring and Observability',
    'Metrics and health are real; logs are not',
    'Present: DVMetrics renders Prometheus text exposition and every server answers GET /metrics with it; dartvel metrics reads that endpoint and says so when nothing answers or nothing has been recorded yet, rather than printing a sample. DVHealth backs GET /health with real checks on a deadline. Tracing carries W3C Trace Context across the request boundary, with sampling decided from the trace id alone so a distributed request is not resampled at every hop. Absent: there is no log sink anywhere in the runtime, so DV.log and DV.ObservabilityAndLogging.event do not exist and nothing an application logs goes anywhere -- dartvel logs says so plainly instead of printing invented lines. Spans are captured but only into an in-process list nothing exports or serves, so dartvel traces has nothing to read either. Profiling, performance analysis, error reporting, and structured, AI-readable diagnostics are all unbuilt too.',
  ),
];

// Tuned, so the whole chain runs on a real project rather than only in a
// test: the annotation, the constant the generator writes into the
// router, the build that reads it back, and the <priority> and
// <changefreq> in build/web/sitemap.xml that CI then asserts.
//
// This file also describes the annotation in prose, a few hundred lines
// up, which is the shape that broke the parser once: it searched for the
// first @DVPage( in the file and found the paragraph.
@DVPage(
  title: 'Features — Dartvel',
  showAppBar: false,
  sitemap: DVPageSitemap(
    priority: 0.8,
    changeFrequency: DVSitemapChangeFrequency.weekly,
  ),
)
@pragma('vm:entry-point')
Widget _featuresPage(BuildContext context) => SingleChildScrollView(
      child: DVBox.list(<Widget>[
        const Section(
          children: <Widget>[
            Eyebrow('WHAT WORKS TODAY'),
            Heading('Thirty-five shipped sections.', level: 1),
            Body(
              'This list is the repository’s own record of what is built, not '
              'a description of what is planned. A tool checks it and fails '
              'when a section claims to be built and the evidence it names '
              'does not exist, so this page cannot quietly get ahead of the '
              'code.',
              width: 660,
            ),
            Body(
              'Twenty-two more sections are partial. They are listed as '
              'partial, with what is absent written next to what is present.',
              width: 660,
            ),
          ],
        ),
        Section(
          tint: true,
          children: <Widget>[
            // A grid where there is room. Twenty-two full-width rows
            // separated by hairlines is a list to scroll past rather than a
            // set of things to compare, and every one of them looked the
            // same as the last.
            LayoutBuilder(
              builder: (BuildContext context, BoxConstraints constraints) {
                final int columns = constraints.maxWidth >= 900
                    ? 2
                    : 1;
                if (columns == 1) {
                  return DVBox.list(<Widget>[
                    for (final (String area, String surface, String body) f
                        in shipped)
                      FeatureRow(area: f.$1, surface: f.$2, body: f.$3),
                  ], spacing: 14);
                }
                const double gap = 18;
                final double width =
                    (constraints.maxWidth - gap * (columns - 1)) / columns;
                return Wrap(
                  spacing: gap,
                  runSpacing: gap,
                  children: <Widget>[
                    for (final (String area, String surface, String body) f
                        in shipped)
                      SizedBox(
                        width: width,
                        child: FeatureRow(
                            area: f.$1, surface: f.$2, body: f.$3),
                      ),
                  ],
                );
              },
            ),
          ],
        ),
        Section(
          children: <Widget>[
            const Eyebrow('HALF BUILT'),
            const Heading('What is partial, and what is missing from it.',
                level: 2),
            const Body(
              'Each of these has real code behind it and a named gap. The '
              'gap is written next to the work, in the repository’s words, '
              'and the same tool holds this list to the index.',
              width: 660,
            ),
            DVBox.list(<Widget>[
              for (final (String area, String surface, String body) f
                  in partial)
                FeatureRow(area: f.$1, surface: f.$2, body: f.$3),
            ], spacing: 14),
          ],
        ),
        const SiteFooter(),
      ], spacing: 0),
    );

/// One shipped capability: the area, the surface you actually type, and what
/// it does.
@DVFunctionalWidget()
Widget _featureRow(
  BuildContext context, {
  required String area,
  required String surface,
  required String body,
}) {
  final Palette palette = Palette.of(context);
  return DVBox(
    DVBox.list(<Widget>[
      // A wrapping line rather than a row. The chip carries an API name and
      // some of them are long: in a fixed row the pair overflowed its card by
      // a few pixels at one width and by forty at another, and an overflow
      // clips in release with nothing to say it did.
      DVBox.wrapLine(<Widget>[
        DVText(area).modifier(
          const DVModifier()
              .fontSize(17)
              .fontWeight(FontWeight.w700)
              .color(palette.ink)
              // Level 2, not 3: these sit directly under the page's h1 and
              // nothing on the page is an h2, so 3 skipped a level and a
              // reader navigating by heading was told they had missed one.
              // Without any level at all they were twenty-two paragraphs, so
              // the page had a title and no structure under it -- for a screen
              // reader moving by heading and for the crawler-visible HTML
              // alike.
              .semanticHeading(2),
        ),
        SiteChip(surface),
      ], spacing: 10),
      DVText(body).modifier(
        const DVModifier().fontSize(15).color(palette.muted).height(1.6),
      ),
    ], spacing: 6),
    const DVModifier()
        // No height: a wrap gives its children unbounded height, so
        // double.infinity here collapsed every card and the section rendered
        // empty. Cards size to their content instead.
        .paddingOnly(left: 18, top: 16, right: 18, bottom: 18)
        // page, not surface: the section this sits on is tinted with surface,
        // so a card in the same colour is an invisible card.
        .backgroundColor(palette.page)
        .rounded(12)
        .border(Border.all(color: palette.rule)),
  );
}

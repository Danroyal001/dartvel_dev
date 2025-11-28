
# FAQ — dartvel v0.1

**Q: Does dartvel render HTML on the server (SSR)?**  
A: No. Pages are standard Flutter widgets. SEO is applied by injecting head/meta tags on web at runtime. Future versions may add SSG-like data prerender.

**Q: Can I use any state management?**  
A: Yes. dartvel is UI-agnostic beyond requiring pages to extend `DartvelPage`.

**Q: Where do I put static assets?**  
A: Use Flutter's normal `flutter.assets` section in `pubspec.yaml`.

**Q: How do I add custom meta tags?**  
A: Return them via `SeoProps(extraMeta: {'my:tag': 'value'})` in `buildWebSeo`.

**Q: How do I change transitions per route?**  
A: Override `transition` in your page; or set defaults via `webTransitions`.

**Q: Can I show custom loading/error UIs while data loads?**  
A: Yes. Add sibling files next to your page file:
`my.page.dart` → `my.loading.dart` with `MyPageLoading`, `my.error.dart` with `MyPageError`. If omitted, `DvDefaultLoading` and `DvDefaultError` are used.

**Q: How do I use env values in Flutter?**  
A: Put them in `.env` (or `.env.local`) and list those in `dartvel.envFiles`. Only `PUBLIC_*` keys are exported to `lib/dartvel_client/env.g.dart` and can be read with `DartvelEnv.get('PUBLIC_KEY')`.

**Q: How do I preview my built web app locally?**  
A: `dartvel preview --dir build/web` serves files with SPA fallback to `index.html`.

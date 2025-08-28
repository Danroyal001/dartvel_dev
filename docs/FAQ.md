
# FAQ — dartvel v2.1

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

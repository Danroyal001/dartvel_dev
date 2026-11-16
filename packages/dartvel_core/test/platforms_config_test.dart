// `dartvel.platforms`: settings that belong to one platform, grouped under it.
// The first is the web page's document: raw HTML at three edges of every
// page (inside <head>, right after <body> opens, right before </body>
// closes), the same in pubspec.yaml, in a Dart config class and in Studio.
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:dartvel_core/config.dart';
import 'package:dartvel_core/dartvel.dart'
    show dvMinifyHtml, dvApplyPageHtml, dvRenderRoutePage, DVRoutePage, dvPageContentSecurityPolicy;
import 'package:test/test.dart';

enum _WebFile implements DVWebFileRef {
  head('web/head.html');

  const _WebFile(this.path);
  @override
  final String path;
}

class _Empty extends DartvelConfig {
  const _Empty();
}

class _ShopConfig extends DartvelConfig {
  const _ShopConfig();

  @override
  DVPlatformSettings get platforms => const DVPlatformSettings(
        web: DVWebSettings(
          document: DVWebDocumentSlots(
            head: <DVHtmlSnippet>[
              DVHtmlSnippet.html('<meta name="theme-color" content="#000">'),
              DVHtmlSnippet.file(_WebFile.head),
            ],
            bodyStart: <DVHtmlSnippet>[
              DVHtmlSnippet.html('<noscript><iframe src="https://www.googletagmanager.com/ns.html?id=GTM-1"></iframe></noscript>'),
            ],
            bodyEnd: <DVHtmlSnippet>[
              DVHtmlSnippet.html('<script src="https://cdn.example.com/chat.js" async></script>'),
            ],
          ),
        ),
      );
}

String _hash(String script) => "'sha256-${base64.encode(sha256.convert(utf8.encode(script)).bytes)}'";

const String _shell = '<!DOCTYPE html>\n<html>\n  <head>\n    <meta charset="UTF-8">\n'
    '    <title>Site</title>\n  </head>\n  <body class="app">\n    <script src="flutter_bootstrap.js" async></script>\n'
    '  </body>\n</html>\n';

void main() {
  final Map<String, Object?> everyField = <String, Object?>{
    'platforms': <String, Object?>{
      'web': <String, Object?>{
        'document': <String, Object?>{
          'head': <Object?>[
            <String, Object?>{'html': '<meta name="theme-color" content="#000">'},
            <String, Object?>{'file': 'web/head.html'},
          ],
          'bodyStart': <Object?>[
            <String, Object?>{
              'html': '<noscript><iframe src="https://www.googletagmanager.com/ns.html?id=GTM-1"></iframe></noscript>',
            },
          ],
          'bodyEnd': <Object?>[
            <String, Object?>{'html': '<script src="https://cdn.example.com/chat.js" async></script>'},
          ],
        },
      },
    },
  };

  group('one configuration in two spellings', () {
    test('the Dart class serialises to exactly the YAML object', () {
      expect(const _ShopConfig().toPubspec(), everyField);
    });

    test('pubspec -> class -> pubspec is identical', () {
      final DartvelPubspecConfig read = DartvelPubspecConfig.fromPubspec(everyField);
      expect(read.problems, isEmpty);
      expect(read.toPubspec(), everyField);
    });

    test('class -> pubspec -> class is identical', () {
      final DartvelPubspecConfig read = DartvelPubspecConfig.fromPubspec(const _ShopConfig().toPubspec());
      expect(read.platforms, const _ShopConfig().platforms);
    });

    test('nothing set writes nothing', () {
      expect(const _Empty().toPubspec(), isEmpty);
      expect(DartvelPubspecConfig.fromPubspec(const <String, Object?>{}).platforms.isEmpty, isTrue);
    });
  });

  group('refused entries, in the same words for both spellings', () {
    List<String> problemsOf(Object? head) => DVPlatformSettings.fromPubspec(<String, Object?>{
          'web': <String, Object?>{
            'document': <String, Object?>{'head': head},
          },
        }).problems;

    test('an entry with both html and file', () {
      expect(problemsOf(<Object?>[
        <String, Object?>{'html': '<meta>', 'file': 'web/a.html'},
      ]).single, contains('either html or file'));
    });

    test('an entry with neither', () {
      expect(problemsOf(<Object?>[<String, Object?>{}]).single, contains('either html or file'));
    });

    test('a file outside web/, or climbing out of it', () {
      expect(problemsOf(<Object?>[<String, Object?>{'file': 'lib/a.html'}]).single, contains('under web/'));
      expect(problemsOf(<Object?>[<String, Object?>{'file': 'web/../secrets.html'}]).single, contains('under web/'));
    });

    test('the shell itself cannot be a snippet', () {
      expect(problemsOf(<Object?>[<String, Object?>{'file': 'web/index.html'}]).single, contains('index.html'));
    });

    test('an unknown slot is named', () {
      final List<String> problems = DVPlatformSettings.fromPubspec(<String, Object?>{
        'web': <String, Object?>{
          'document': <String, Object?>{'footer': <Object?>[]},
        },
      }).problems;
      expect(problems.single, contains('footer'));
      expect(problems.single, contains('head, bodyStart and bodyEnd'));
    });

    test('the other web settings under platforms.web are not refused', () {
      expect(
        DVPlatformSettings.fromPubspec(<String, Object?>{
          'web': <String, Object?>{
            'firstFrame': <String, Object?>{'widths': <int>[390]},
            'server': <String, Object?>{'compression': 'gzip'},
          },
        }).problems,
        isEmpty,
      );
    });
  });

  group('HTML that would break the page is refused', () {
    test('a script, style, comment or iframe left open swallows the page', () {
      for (final String html in <String>[
        '<script>start()',
        '<style>body{}',
        '<!-- note',
        '<noscript><img src="x">',
        '<iframe src="https://a.example">',
        '<textarea>',
      ]) {
        expect(dvHtmlSnippetProblems(html, slot: DVDocumentSlot.bodyEnd), isNotEmpty, reason: html);
      }
    });

    test('a div left open in bodyStart would take the app inside it', () {
      expect(dvHtmlSnippetProblems('<div class="banner">Sale', slot: DVDocumentSlot.bodyStart).single,
          contains('<div>'));
    });

    test('a closing tag with nothing open closes the page around it', () {
      expect(dvHtmlSnippetProblems('</div>', slot: DVDocumentSlot.bodyEnd).single, contains('</div>'));
    });

    test('the page structure tags are not a snippet', () {
      for (final String html in <String>['<body>', '</head>', '<html lang="en">', '</body>', '<head>']) {
        expect(dvHtmlSnippetProblems(html, slot: DVDocumentSlot.bodyEnd), isNotEmpty, reason: html);
      }
    });

    test('the head takes only what a head can hold', () {
      expect(dvHtmlSnippetProblems('<div>hi</div>', slot: DVDocumentSlot.head).single, contains('<div>'));
      expect(
        dvHtmlSnippetProblems(
          '<meta name="x" content="y"><link rel="preconnect" href="https://a.example">'
          '<script>window.x=1</script><style>a{}</style><noscript><style>b{}</style></noscript>'
          '<base href="/"><template><p>t</p></template>',
          slot: DVDocumentSlot.head,
        ),
        isEmpty,
      );
    });

    test('the title and description are each page\'s own', () {
      expect(dvHtmlSnippetProblems('<title>Mine</title>', slot: DVDocumentSlot.head).single, contains('title'));
      expect(dvHtmlSnippetProblems('<meta name="description" content="d">', slot: DVDocumentSlot.head).single,
          contains('description'));
    });

    test('well-formed snippets pass, void elements and quoted > included', () {
      expect(
        dvHtmlSnippetProblems(
          '<div data-x="a>b"><img src="a.png" alt=""><br><p>One<p>Two</div>'
          '<script>if (a < b && c > d) { document.write("</div>".length) }</script>',
          slot: DVDocumentSlot.bodyEnd,
        ),
        isEmpty,
      );
    });
  });

  group('the document edges', () {
    final DVWebDocumentSlots slots = const DVWebDocumentSlots(
      head: <DVHtmlSnippet>[DVHtmlSnippet.html('<meta name="x" content="1">')],
      bodyStart: <DVHtmlSnippet>[DVHtmlSnippet.html('<noscript>Tag</noscript>')],
      bodyEnd: <DVHtmlSnippet>[DVHtmlSnippet.html('<script>last()</script>')],
    );

    test('each slot lands at its edge', () {
      final String html = dvApplyDocumentSlots(_shell, slots);
      expect(html.indexOf('<meta name="x"'), lessThan(html.indexOf('</head>')));
      expect(html.indexOf('<meta name="x"'), greaterThan(html.indexOf('<title>')));
      final int bodyOpen = html.indexOf('<body class="app">') + '<body class="app">'.length;
      expect(html.substring(bodyOpen).trimLeft(), startsWith('<!-- dartvel:body-start -->'));
      expect(html.substring(0, html.indexOf('</body>')).trimRight(), endsWith('<!-- /dartvel:body-end -->'));
    });

    test('applying twice replaces rather than adds', () {
      final String once = dvApplyDocumentSlots(_shell, slots);
      expect(dvApplyDocumentSlots(once, slots), once);
      final String cleared = dvApplyDocumentSlots(once, const DVWebDocumentSlots());
      expect(cleared, isNot(contains('last()')));
      expect(cleared, isNot(contains('dartvel:body-end')));
    });

    test('files are read through the reader, in order', () {
      final String html = dvApplyDocumentSlots(
        _shell,
        const DVWebDocumentSlots(head: <DVHtmlSnippet>[
          DVHtmlSnippet.html('<meta name="a" content="1">'),
          DVHtmlSnippet.file(_WebFile.head),
        ]),
        readFile: (String path) => path == 'web/head.html' ? '<meta name="b" content="2">' : throw StateError(path),
      );
      expect(html.indexOf('name="a"'), lessThan(html.indexOf('name="b"')));
    });

    test('the page document goes before the body-end slot, which stays last', () {
      final String withSlots = dvApplyDocumentSlots(_shell, slots);
      final String page = dvApplyPageHtml(withSlots, '<main><h1>Hi</h1></main>', path: '/');
      expect(page.indexOf('<h1>Hi</h1>'), lessThan(page.indexOf('last()')));
      expect(page.substring(0, page.indexOf('</body>')).trimRight(), endsWith('<!-- /dartvel:body-end -->'));
    });

    test('a rendered route keeps both body edges, and the minifier leaves the snippet as written', () {
      const String spaced = '<script>\n  var  a = 1;   // keep\n  last(a)\n</script>';
      final String withSlots = dvApplyDocumentSlots(_shell, const DVWebDocumentSlots(
        bodyStart: <DVHtmlSnippet>[DVHtmlSnippet.html('<noscript>Tag</noscript>')],
        bodyEnd: <DVHtmlSnippet>[DVHtmlSnippet.html(spaced)],
      ));
      final String html = dvRenderRoutePage(
        withSlots,
        const DVRoutePage(route: '/', title: 'Home', html: '<main><h1>Home</h1></main>'),
      );
      expect(html, contains(spaced));
      expect(RegExp(r'<body[^>]*><!-- dartvel:body-start -->').hasMatch(html), isTrue, reason: html);
      expect(RegExp(r'<!-- /dartvel:body-end --></body>').hasMatch(html), isTrue, reason: html);
      expect(html.indexOf('<h1>Home</h1>'), lessThan(html.indexOf(spaced)));
      expect(dvMinifyHtml(html), html);
    });

    test("a page's policy lists the snippet's inline script", () {
      final String html = dvApplyDocumentSlots(_shell, slots);
      expect(dvPageContentSecurityPolicy("script-src 'self' 'inline-scripts'", html), contains(_hash('last()')));
    });
  });

  group('the Content-Security-Policy follows the snippets', () {
    const DVWebDocumentSlots tags = DVWebDocumentSlots(
      head: <DVHtmlSnippet>[
        DVHtmlSnippet.html('<script async src="https://www.googletagmanager.com/gtag/js?id=G-1"></script>'
            '<script>window.dataLayer=[];</script>'
            '<link rel="stylesheet" href="https://fonts.example.com/a.css">'),
      ],
      bodyStart: <DVHtmlSnippet>[
        DVHtmlSnippet.html('<noscript><iframe src="https://www.googletagmanager.com/ns.html"></iframe></noscript>'
            '<img src="https://px.example.com/p.gif" alt="">'),
      ],
      bodyEnd: <DVHtmlSnippet>[DVHtmlSnippet.html('<script src="/local.js"></script>')],
    );

    test('external hosts, by the directive that loads them', () {
      expect(dvDocumentSlotCspSources(tags), <String, List<String>>{
        'script-src': <String>['https://www.googletagmanager.com'],
        'style-src': <String>['https://fonts.example.com'],
        'frame-src': <String>['https://www.googletagmanager.com'],
        'img-src': <String>['https://px.example.com'],
      });
    });

    test('a policy with the inline-scripts source keeps it, and gains the hosts', () {
      final String policy = dvPageCspWithDocumentSlots(
          "default-src 'self'; script-src 'self' 'inline-scripts'", tags);
      expect(policy, contains("script-src 'self' 'inline-scripts' https://www.googletagmanager.com"));
      expect(policy, contains('img-src'));
      expect(policy, isNot(contains(_hash('window.dataLayer=[];'))));
    });

    test('a policy without it gets each inline snippet script hashed in', () {
      final String policy = dvPageCspWithDocumentSlots("script-src 'self' 'sha256-old'", tags);
      expect(policy, contains(_hash('window.dataLayer=[];')));
      expect(policy, contains("'sha256-old'"));
    });

    test('no snippets leaves the policy alone', () {
      expect(dvPageCspWithDocumentSlots("script-src 'self'", const DVWebDocumentSlots()), "script-src 'self'");
    });
  });

  group('the old homes still work', () {
    test('dartvel.web and dartvel.android are read as platforms.web and platforms.android', () {
      final Map<Object?, Object?> section = dvWithPlatforms(<Object?, Object?>{
        'web': <String, Object?>{'firstFrame': <String, Object?>{'widths': <int>[390]}},
        'android': <String, Object?>{'permissions': <String>['CAMERA']},
        'platforms': <String, Object?>{
          'web': <String, Object?>{
            'document': <String, Object?>{'head': <Object?>[]},
          },
        },
      });
      final Map<Object?, Object?> platforms = section['platforms']! as Map<Object?, Object?>;
      expect((platforms['web']! as Map<Object?, Object?>).keys, containsAll(<String>['firstFrame', 'document']));
      expect(platforms['android'], <String, Object?>{'permissions': <String>['CAMERA']});
      // Readers that have not moved yet see the same values at the old key.
      expect((section['web']! as Map<Object?, Object?>).keys, containsAll(<String>['firstFrame', 'document']));
    });

    test('the new home wins where both set the same key', () {
      final Map<Object?, Object?> section = dvWithPlatforms(<Object?, Object?>{
        'web': <String, Object?>{'server': <String, Object?>{'compression': 'gzip', 'x': 1}},
        'platforms': <String, Object?>{
          'web': <String, Object?>{'server': <String, Object?>{'compression': 'zstd'}},
        },
      });
      expect((section['web']! as Map<Object?, Object?>)['server'], <String, Object?>{'compression': 'zstd', 'x': 1});
    });

    test('the list of targets a project builds for stays valid, and reads as targets', () {
      final Map<Object?, Object?> listed = <Object?, Object?>{
        'platforms': <String>['web', 'android'],
      };
      expect(dvWithPlatforms(listed), listed);
      expect(DVPlatformSettings.fromPubspec(listed['platforms']).problems, isEmpty);
      expect(dvPlatformTargets(listed['platforms']), <String>['web', 'android']);
      expect(
        dvPlatformTargets(<String, Object?>{'web': <String, Object?>{}, 'ios': null}),
        <String>['web', 'ios'],
      );
    });

    test('a list of targets beside an old platform key becomes the map, targets kept', () {
      final Map<Object?, Object?> section = dvWithPlatforms(<Object?, Object?>{
        'platforms': <String>['web', 'android'],
        'web': <String, Object?>{'firstFrame': <String, Object?>{}},
      });
      expect(dvPlatformTargets(section['platforms']), containsAll(<String>['web', 'android']));
      expect(((section['platforms']! as Map)['web']! as Map).keys, contains('firstFrame'));
    });

    test('a section with neither is unchanged', () {
      final Map<Object?, Object?> section = <Object?, Object?>{'seo': <String, Object?>{}};
      expect(dvWithPlatforms(section), section);
    });

    test('which old keys a project still uses, for the build to mention', () {
      expect(dvLegacyPlatformKeys(<Object?, Object?>{'web': <String, Object?>{}, 'seo': 1}), <String>['web']);
    });
  });
}

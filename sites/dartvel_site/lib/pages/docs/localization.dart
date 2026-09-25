import 'package:flutter/material.dart';

import '../../dartvel_client/dartvel_client.dart';

@DVPage(
  title: 'Dartvel localization: typed keys, plurals and ARB catalogues',
  description: 'Declare each string once as a typed key and dartvel i18n tells '
      'you which languages are missing it. Plurals follow the CLDR '
      'rules of each language.',
  showAppBar: false,
)
@pragma('vm:entry-point')
Widget _docsLocalizationPage(BuildContext context) => const DocsArticle(
      page: DVRoutes.docslocalization,
      lead: <String>[
        'Declare each string once as a typed key, and `dartvel i18n` tells you '
            'which languages are missing it.',
        'Plurals follow the CLDR rules of each language.',
      ],
      sections: <DocsSection>[
        DocsSection(
          id: 'keys',
          title: 'Declare keys and load catalogues',
          children: <Widget>[
            DocsCode('i18n-keys'),
            Bullets(<String>[
              'A catalogue is const, with DVTranslationKey keys.',
              'DVPluralForms takes zero, one, two, few, many and other, and '
                  'the language decides which one a count uses.',
            ]),
          ],
        ),
        DocsSection(
          id: 'use',
          title: 'Translate text and counts',
          children: <Widget>[
            DocsCode('i18n-use'),
            Bullets(<String>[
              '{name} placeholders are filled from args, and {count} from the '
                  'count.',
              'A missing key shows the key itself. Pass strict: true to throw '
                  'instead.',
              'DV.I18n.textDirection is rtl for Arabic, Hebrew, Persian and '
                  'the other right-to-left languages.',
            ]),
          ],
        ),
        DocsSection(
          id: 'extract',
          title: 'Keep every language complete',
          children: <Widget>[
            DocsShell(<String>[
              'dartvel i18n extract --locale en --locale fr',
              'dartvel i18n check --strict',
            ]),
            Bullets(<String>[
              'extract finds every DVTranslationKey under lib/ and writes '
                  'lib/l10n/app_<locale>.arb, keeping translations you have.',
              'check lists untranslated and no-longer-used keys per language. '
                  '--strict fails, for CI.',
            ]),
          ],
        ),
        DocsSection(
          id: 'seo',
          title: 'Tell search engines about each language',
          children: <Widget>[
            DocsShell(<String>[
              '# pubspec.yaml',
              'dartvel:',
              '  seo:',
              '    siteUrl: https://example.com',
              '  i18n:',
              '    locales: [en, fr]',
              '    defaultLocale: en',
            ]),
            DocsText('With two or more locales, `dartvel build web` writes '
                'hreflang links on every page: /about for the default and '
                '/fr/about for French, plus x-default.'),
          ],
        ),
        DocsSection(
          id: 'negotiate',
          title: 'Pick a language for a request',
          children: <Widget>[
            DocsText('dvNegotiateLocale from dartvel_core chooses among your '
                'supported locales. A /fr/ path wins, then a stored '
                'preference, then Accept-Language, then the tenant\'s default, '
                'then your fallback.'),
          ],
        ),
        DocsSection(
          id: 'status',
          title: 'Status',
          children: <Widget>[
            DocsStatus('Internationalization and Localization'),
          ],
        ),
      ],
    );

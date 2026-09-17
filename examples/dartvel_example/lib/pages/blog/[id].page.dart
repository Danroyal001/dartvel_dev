import 'package:dartvel_example/dartvel_client/dartvel_client.dart';
import 'package:flutter/material.dart';

import '../../components/shop_ui.dart';
import '../../theme/palette.dart';

/// A brew guide, by its slug.
@DVPage(title: 'Brew guide')
@pragma('vm:entry-point')
Widget _blogIdPage(BuildContext context) => (() {
  final Palette p = Palette.of(context);
  final String id = context.dvParams['id'] ?? '';
  final BrewGuide guide = brewGuides[id] ?? brewGuides['pour-over']!;
  return ShopScroll(
    maxWidth: readingMaxWidth,
    children: <Widget>[
      const BackToShop(),
      PageHeading(guide.title, overline: 'Brew guide', subtitle: guide.intro),
      DVBox.wrapLine([
        for (final MapEntry<String, String> fact in guide.facts.entries)
          CoffeeFact(fact.key, fact.value),
      ], spacing: 10),
      DVBox.list([
        for (int i = 0; i < guide.steps.length; i++)
          DVBox.row(
            [
              DVText('${i + 1}').modifier(
                p.headline
                    .color(p.accent)
                    .width(32)
                    .height(32)
                    .rounded(16)
                    .align(Alignment.center)
                    .backgroundColor(p.accentSoft),
              ),
              Expanded(child: DVText(guide.steps[i]).modifier(p.body)),
            ],
            spacing: 14,
            crossAlign: DVCrossAlign.start,
          ),
      ], spacing: 16).modifier(cardStyle(p, padding: 22).maxWidth(720)),
    ],
  );
})();

class BrewGuide {
  const BrewGuide(this.title, this.intro, this.facts, this.steps);

  final String title;
  final String intro;
  final Map<String, String> facts;
  final List<String> steps;
}

const Map<String, BrewGuide> brewGuides = <String, BrewGuide>{
  'pour-over': BrewGuide(
    'Pour-over',
    'Clean and bright. The way to taste a washed Ethiopian or Kenyan.',
    <String, String>{'Coffee': '15 g', 'Water': '250 g', 'Time': '3 min'},
    <String>[
      'Rinse the paper filter with hot water and pour that water away.',
      'Grind 15 g of coffee to the size of coarse sea salt.',
      'Pour 40 g of water just off the boil and wait 30 seconds.',
      'Pour the rest in slow circles, finishing by 1 minute 45.',
      'Let it drain. It should be done by 3 minutes.',
    ],
  ),
  'cold-brew': BrewGuide(
    'Cold brew',
    'Sweet and low in acidity. Make it the night before.',
    <String, String>{'Coffee': '100 g', 'Water': '1 litre', 'Time': '14 h'},
    <String>[
      'Grind 100 g of coffee coarse.',
      'Stir it into a litre of cold water.',
      'Cover and leave it in the fridge for 14 hours.',
      'Strain through a paper filter and dilute to taste.',
    ],
  ),
};

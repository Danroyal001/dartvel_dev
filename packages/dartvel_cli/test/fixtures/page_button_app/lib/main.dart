// sigmadev.digital's shape: a header with a link over a long page, and the
// layout's "To the bottom / Back to top" button. On 3.47.11 to 3.47.13 the
// button's semantics node covered the whole window and took every click.
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/material.dart';

class SiteLayout extends DartvelLayout {
  const SiteLayout({super.key, required super.child}) : super(pageScrollToTop: true);

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const SizedBox(
            height: 70,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: EdgeInsets.only(left: 16),
                child: DVNavLink.external('/linked', child: Text('Home link')),
              ),
            ),
          ),
          Expanded(child: child),
        ],
      );
}

class LongPage extends StatelessWidget {
  const LongPage({super.key});

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            for (int row = 0; row < 80; row++) SizedBox(height: 50, child: Text('Row $row')),
          ],
        ),
      );
}

void main() {
  dvEnsureSemantics();
  runApp(const MaterialApp(
    home: DVPageShell(spec: DVPageScaffoldSpec(title: 'Long'), child: SiteLayout(child: LongPage())),
  ));
}

import 'package:flutter/material.dart';
import '../dartvel_client/dartvel_client.dart';

class IndexPageError extends StatelessWidget {
  const IndexPageError({super.key});

  @override
  Widget build(BuildContext context) {
    return DVBox.list([
      const DVText('ERROR').modifier(
        DVModifier().fontSize(24).fontWeight(FontWeight.w800).color(Colors.red),
      ),
      const DVText('Something went wrong'),
      DVText('Go Back').modifier(
        const DVModifier()
            .padding(12)
            .rounded(8)
            .backgroundColor(Colors.black)
            .color(Colors.white)
            .onPressed(() => Navigator.of(context).pop()),
      ),
    ]).modifier(
      const DVModifier().align(Alignment.center),
    );
  }
}

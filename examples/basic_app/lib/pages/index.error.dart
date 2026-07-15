import 'package:basic_app/dartvel_client/dartvel_client.dart';
import 'package:flutter/material.dart';

class IndexPageError extends StatelessWidget {
  const IndexPageError({super.key});

  @override
  Widget build(BuildContext context) {
    return DVBox.list([
      const Icon(Icons.error_outline, size: 48, color: Colors.red),
      const DVText('Something went wrong'),
      const DVText('Go Back').modifier(
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

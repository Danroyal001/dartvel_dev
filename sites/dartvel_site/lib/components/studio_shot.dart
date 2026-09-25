// A screenshot of Studio, framed.
//
// Every picture passed here is of the real thing: the page builder and the
// model records are the web-server binary's own Studio at /__studio, and the
// workflow builder is dartvel_studio_pro's section rendered by Flutter. A
// mockup of a feature is a claim nobody can check, and this site's claims are
// meant to be checkable.
import 'package:flutter/material.dart';

import '../dartvel_client/dartvel_client.dart';
import 'site.dart';

/// [asset] is a path under assets/studio, declared in pubspec.yaml, and
/// [label] is what a screen reader says in place of the picture.
@DVFunctionalWidget()
Widget _studioShot(
  BuildContext context,
  String asset,
  String label, {
  String? caption,
}) {
  final Palette palette = Palette.of(context);
  final String? note = caption;
  return DVBox.list(<Widget>[
    DVBox(
      ClipRRect(
        borderRadius: BorderRadius.circular(11),
        child: Image.asset(
          asset,
          semanticLabel: label,
          fit: BoxFit.fitWidth,
          width: double.infinity,
        ),
      ),
      const DVModifier()
          .width(double.infinity)
          .border(Border.all(color: palette.rule))
          .rounded(12)
          .shadow(<BoxShadow>[
        BoxShadow(
          color: Colors.black.withValues(alpha: palette.dark ? 0.45 : 0.10),
          blurRadius: 28,
          offset: const Offset(0, 12),
        ),
      ]),
    ),
    if (note != null)
      Prose(note, const DVModifier()
          .fontSize(13)
          .color(palette.faint)
          .lineHeight(1.5)),
  ], spacing: 10);
}

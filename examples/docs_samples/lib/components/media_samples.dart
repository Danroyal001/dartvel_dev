import 'package:flutter/widgets.dart';

import '../dartvel_client/dartvel_client.dart';

// docs:start media-image-view
Widget hero() => DVBox.image(
      // Generated from pubspec.yaml: a renamed file is a compile error, not a
      // blank box on somebody's phone.
      DVAsset.hero,
      alt: 'A team planning a release',
      width: 400,
      height: 210,
    );
// docs:end

// docs:start media-background
Widget banner() => const DVBox(DVText('Now shipping')).modifier(
      const DVModifier().backgroundImage(DVAsset.hero).padding(48),
    );
// docs:end

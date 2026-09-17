import 'package:flutter/widgets.dart';

import '../dartvel_client/dartvel_client.dart';

// docs:start media-image-view
Widget hero() => const DVImageView(
      DVImage.asset(
        'assets/hero.png', // listed under flutter: assets: in pubspec.yaml
        alt: 'A team planning a release',
        width: 2400,
        height: 1260,
      ),
      width: 400,
      height: 210,
    );
// docs:end

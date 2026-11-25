import 'dart:typed_data';

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

// docs:start media-pick
Future<void> choosePhoto() async {
  if (!DV.Platform.media.canPick) return;
  final DVFile? photo = await DV.Platform.media.pickImage(); // null: cancelled
  if (photo == null) return;
  final Uint8List bytes = await DV.Platform.media.readCapture(photo);
  await uploadPhoto(bytes); // or decode it
}

Future<List<DVFile>> chooseMenus() => DV.Platform.media.pickFiles(
      types: <String>['application/pdf', '.csv'],
      multiple: true,
    );
// docs:end

Future<void> uploadPhoto(Uint8List bytes) async {}

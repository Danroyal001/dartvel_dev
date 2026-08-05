import 'package:flutter/widgets.dart';

/// A browser cannot read an arbitrary filesystem path, so there is no provider
/// to return. [DVImageView] renders its placeholder instead of failing.
ImageProvider<Object>? fileImageProvider(String path) => null;

/// The names an application's data models take, and keeping the framework's
/// own names out of their way.
///
/// A data model is named whatever its application calls the thing: a blog
/// has a `Post`, a delivery app a `Route`. The generated client imports the
/// framework unprefixed beside the models, and the framework exports
/// ordinary words of its own -- dartvel_core's HTTP annotations `Get`,
/// `Post`, `Put`, `Delete`, `Patch` and `Route`, and Flutter's `Route` -- so a
/// model with one of those names made every generated library that saw both
/// fail to compile ("'Post' is exported from both"), or, worse, compile
/// against the annotation where the model was meant.
///
/// The application's name wins. Every framework import and export in a
/// generated library that also sees the models hides the models' names, so
/// the model is the only `Post` there is. Hiding a name a library does not
/// export is harmless but draws the analyzer's `undefined_hidden_name`, which
/// those libraries ignore; which names the framework exports changes from
/// release to release, and a list of them here would be one more thing to
/// drift.
library;

import 'dart:io';

import 'package:glob/glob.dart';
import 'package:file/local.dart';

import 'annotation_args.dart';
import 'primary_constructors.dart';

/// The generated class name of every data model declared under
/// `lib/models/` in [root], sorted.
///
/// Read the way the model generator reads them: the private annotated class,
/// with its leading underscore dropped.
List<String> dvDeclaredModelNames(String root) {
  if (!Directory('$root/lib/models').existsSync()) return const <String>[];
  final Set<String> names = <String>{};
  for (final entity in Glob('lib/models/**.dart').listFileSystemSync(
    const LocalFileSystem(),
    root: root,
    followLinks: false,
  )) {
    if (entity is! File) continue;
    final String text =
        dvDesugarPrimaryConstructors(File(entity.path).readAsStringSync());
    for (final RegExpMatch m in RegExp(
      r'@DVModel\b[\s\S]*?class\s+_([A-Za-z0-9_]+)\b',
    ).allMatches(dvMaskAnnotationArgs(text, 'DVModel'))) {
      names.add(m.group(1)!);
    }
  }
  return names.toList()..sort();
}

/// ` hide A, B` for a framework import or export beside models named
/// [modelNames], or nothing when there are none.
String dvHideModelNames(Iterable<String> modelNames) {
  final List<String> names = modelNames.toSet().toList()..sort();
  return names.isEmpty ? '' : ' hide ${names.join(', ')}';
}

/// The analyzer diagnostic a hidden model name draws from a framework
/// library that never exported it.
const String dvUndefinedHiddenName = 'undefined_hidden_name';

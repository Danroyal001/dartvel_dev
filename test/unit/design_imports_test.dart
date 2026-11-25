// Nothing Dartvel builds may name Flutter's deprecated design libraries.
//
// Flutter 3.50 deprecates package:flutter/material.dart and
// package:flutter/cupertino.dart for the material_ui and cupertino_ui
// packages, and those packages are copies of the libraries, not re-exports.
// One file left on the old import builds a second Material library beside
// the first: its widgets look for a Theme and a Material ancestor of their
// own classes, find none under the application's material_ui app, and fall
// back to defaults -- a regression that compiles and says nothing. The same
// holds for a generator template that writes the old import into every
// project it touches. So every tracked Dart file is read, strings included.
import 'package:test/test.dart';

import '../../tool/ci/design_imports.dart';

void main() {
  test('an import of the deprecated material library is reported', () {
    expect(
      dvDesignImportProblems(<String, String>{
        'packages/x/lib/a.dart': "import 'package:flutter/material.dart';\n",
      }),
      hasLength(1),
    );
  });

  test('the cupertino library, an export and a prefix are reported too', () {
    expect(
      dvDesignImportProblems(<String, String>{
        'a.dart': "import 'package:flutter/cupertino.dart' as c;\n",
        'b.dart': 'export "package:flutter/material.dart" show Colors;\n',
      }),
      hasLength(2),
    );
  });

  test('a generator template writing the old import is reported', () {
    // The silent case: it is a string to the analyzer, so neither dart fix
    // nor the deprecation warning sees it, and every generated project
    // inherits it.
    expect(
      dvDesignImportProblems(<String, String>{
        'packages/dartvel_cli/lib/src/gen.dart':
            "final String head = \"import 'package:flutter/material.dart';\";\n",
      }),
      hasLength(1),
    );
  });

  test('the replacements and plain prose are not reported', () {
    expect(
      dvDesignImportProblems(<String, String>{
        'a.dart': "import 'package:material_ui/material_ui.dart';\n"
            "import 'package:cupertino_ui/cupertino_ui.dart';\n"
            '/// Replaces package:flutter/material.dart, which is deprecated.\n'
            '// package:flutter/cupertino.dart is gone from here.\n',
      }),
      isEmpty,
    );
  });

  test('the files that have to name the old libraries are allowed', () {
    expect(
      dvDesignImportProblems(<String, String>{
        for (final String path in dvDesignImportAllowed.keys)
          path: "import 'package:flutter/material.dart';\n",
      }),
      isEmpty,
    );
  });

  test('this repository names neither library outside those files', () {
    expect(dvDesignImportProblems(dvTrackedDartSources()), isEmpty);
  });
}

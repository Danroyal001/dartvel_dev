/// Where the documentation site lives, and who may reach it.
///
/// One documentation site for one application, serving every platform that
/// application ships to. Not a page in the client: the documentation is a
/// separate Flutter application compiled on its own and served by the backend.
/// The application's own theme, shell and guards do not apply to it.
///
/// The path is a default rather than a constant. A framework that shipped a
/// fixed docs path would have created that for every application built with it.
/// The default exists so a new project works with no configuration; the setting
/// exists so a deployed one can move it somewhere nobody is guessing.
library;

import 'package:dartvel_core/dartvel.dart' show DVDocsMount;

export 'package:dartvel_core/dartvel.dart'
    show
        DVDocsAccess,
        DVDocsMount,
        dvDocsMount,
        dvDocsMountProblem,
        dvDocsMountConflict;

/// The default, and only the default.
const String dvDocsDefaultPath = '/docs';

/// The directory `dartvel build` writes the docs site into.
const String dvDocsPagesDirectory = '__docs';
/// Where under `build/web` a build puts the compiled docs site for [docs], or
/// why it cannot carry one.
///
/// [server] is a web-server build, which serves the site itself: from a
/// section of the binary of its own, outside the files it hands to anybody,
/// so `access: studio` can be enforced. [studioServed] is whether that
/// server also serves Studio, whose sign-in and grant `access: studio` is.
///
/// A static build is files on a host that serves every one of them to
/// anybody. A public site goes at its mount, where the host serves it; a
/// site behind Studio cannot be carried at all, and is refused rather than
/// published where anybody can read the project's graph.
({String? directory, String? problem}) dvDocsPlacement(
  DVDocsMount docs, {
  required bool server,
  required bool studioServed,
}) {
  if (server) {
    if (docs.requiresAuth && !studioServed) {
      return (
        directory: null,
        problem: 'dartvel.docs.access is studio, and this build serves no '
            'Studio to sign in to: turn Studio on with dartvel.admin.enabled, '
            'or set dartvel.docs.access to public.',
      );
    }
    return (directory: dvDocsPagesDirectory, problem: null);
  }
  if (docs.requiresAuth) {
    return (
      directory: null,
      problem: 'dartvel.docs.access is studio, and a static web build has no '
          'server to keep the documentation behind Studio: every file it '
          'writes is served to anybody. Build web-server, or set '
          'dartvel.docs.access to public (access: public) to publish it.',
    );
  }
  return (directory: docs.path.substring(1), problem: null);
}

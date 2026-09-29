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
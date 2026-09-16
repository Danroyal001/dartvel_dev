/// What the backend does with a request for the admin.
///
/// Three answers, and the difference between two of them is the whole
/// security posture of the feature: a request refused because nobody signed
/// in has to be indistinguishable from a request for a route that does not
/// exist.
///
/// The rules live in dartvel_core, beside `DVAdminServer`, because the
/// generated backend that serves the admin from a web-server binary cannot
/// depend on this package. `dartvel preview` and the binary decide the same
/// request with the same code rather than with two copies that drift.
library;

export 'package:dartvel_core/dartvel.dart'
    show DVAdminRequest, dvAdminFor, dvAdminHiddenHeaders, dvAdminHiddenStatus;

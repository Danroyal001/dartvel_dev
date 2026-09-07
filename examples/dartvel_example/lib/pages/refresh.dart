import 'package:dartvel_core/dartvel.dart';

/// A client-side schedule, which the generated runtime starts.
///
/// No `@DVPage`, so this is not a route -- it is here to put a
/// `@DVClientCron` in a file the client compiles. The client handlers live
/// in a generated file of their own precisely because a page reached from
/// the backend's schedules file would pull Flutter into a server with no
/// dart:ui, and the only way to know that stayed true is for an application
/// to declare one and still build.
@DVClientCron('*/15 * * * *')
void refreshDashboard() {}

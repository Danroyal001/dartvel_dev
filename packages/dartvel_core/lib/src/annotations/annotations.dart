/// Annotation for a route
class Route {
  final String path;
  final String? name;

  const Route(this.path, {this.name});
}

/// Annotation for a GET handler
class Get {
  final String path;
  const Get([this.path = '/']);
}

/// Annotation for a POST handler
class Post {
  final String path;
  const Post([this.path = '/']);
}

/// Annotation for a PUT handler
class Put {
  final String path;
  const Put([this.path = '/']);
}

/// Annotation for a DELETE handler
class Delete {
  final String path;
  const Delete([this.path = '/']);
}

/// Annotation for a PATCH handler
class Patch {
  final String path;
  const Patch([this.path = '/']);
}

/// Annotation for a Dartvel Page
class DVPage {
  final String? path;
  const DVPage([this.path]);
}

/// Annotation for a functional widget Page
class DVFunctionalWidget {
  const DVFunctionalWidget();
}

/// Annotation for a Dartvel Data Model
class DVModel {
  const DVModel();
}

/// Annotation for a Dartvel Backend Function
class DVBackendFunction {
  const DVBackendFunction();
}

/// Annotation for a Backend Cron Job
class DVBackendCron {
  final String cron;
  const DVBackendCron(this.cron);
}

/// Annotation for a Client Cron Job
class DVClientCron {
  final String cron;
  const DVClientCron(this.cron);
}

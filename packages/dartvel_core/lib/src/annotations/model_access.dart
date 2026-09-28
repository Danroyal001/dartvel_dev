/// Who may do what to a data model's records, and the indexes it asks its
/// database for, as a `@DVModel` declares them and as Studio stores them for
/// a model designed there.
///
/// One description for both on purpose: a model designed in Studio and
/// written out to source carries the same rules it was served with, and a
/// model written in code shows them in Studio's designer.
library;

/// Who may do something to a model's records through its data API.
enum DVAccess {
  /// Everybody, signed in or not.
  anyone,

  /// Any signed-in account of the application.
  signedIn,

  /// The people who may open Studio.
  team,

  /// Nobody through the data API. Studio itself still can.
  nobody;

  /// [name], or [fallback] for anything else.
  static DVAccess byName(Object? name, DVAccess fallback) {
    for (final DVAccess access in values) {
      if (access.name == name) return access;
    }
    return fallback;
  }
}

/// Who may read, create, change and delete a model's records.
///
/// A model designed in Studio has no `@DVPolicy` class to say so, so its
/// definition does, and its data API asks this. An application that
/// registers a policy for `<Model>.<action>` in code is asked instead.
class DVModelAccess {
  const DVModelAccess({
    this.view = DVAccess.team,
    this.create = DVAccess.team,
    this.update = DVAccess.team,
    this.delete = DVAccess.team,
  });

  factory DVModelAccess.fromJson(Map<Object?, Object?> json) => DVModelAccess(
    view: DVAccess.byName(json['view'], DVAccess.team),
    create: DVAccess.byName(json['create'], DVAccess.team),
    update: DVAccess.byName(json['update'], DVAccess.team),
    delete: DVAccess.byName(json['delete'], DVAccess.team),
  );

  final DVAccess view;
  final DVAccess create;
  final DVAccess update;
  final DVAccess delete;

  /// The rule for [action]: `view`, `create`, `update` or `delete`.
  DVAccess of(String action) => switch (action) {
    'view' => view,
    'create' => create,
    'update' => update,
    'delete' => delete,
    _ => DVAccess.nobody,
  };

  Map<String, Object?> toJson() => <String, Object?>{
    'view': view.name,
    'create': create.name,
    'update': update.name,
    'delete': delete.name,
  };
}

/// An index a data model asks its database for: one field or several, and
/// whether no two records may share the combination.
///
/// `@DVModel(indexes: <DVIndex>[DVIndex(<String>['status', 'placedAt'])])`.
class DVIndex {
  const DVIndex(this.fields, {this.unique = false});

  final List<String> fields;
  final bool unique;
}

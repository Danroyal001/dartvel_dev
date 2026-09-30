/// Reusable components: made once, used on any page, changed everywhere at
/// once.
///
/// A component is a page document kept at `/_dartvel/components/<Name>`,
/// beside the pages, so it is stored, published and delivered the way a
/// page is, and nothing new has to carry it. Its props -- the text, picture,
/// colour or tap action each use sets for itself -- are listed on its root.
/// Inside the component a prop is used by writing `{{name}}` in a text, an
/// image address or a colour, or by an action `{type: prop, name: ...}`.
///
/// A page keeps only where it uses a component and the props it gave, as a
/// node of type [dvStudioComponentType]. It is drawn from the component
/// every time, so an edit to the component reaches every page using it
/// without any of them being edited.
library;

import 'dart:async';

import 'package:dartvel_core/dartvel.dart'
    show dvStudioComponentsPrefix;
import 'package:flutter/widgets.dart';

import 'page_document.dart';

/// The node type a use of a component is.
const String dvStudioComponentType = 'component';

/// Where the props a component takes are listed on its root.
const String _propsKey = 'componentProps';

/// What kind of value a prop holds, which decides how Studio asks for it.
enum DVStudioPropKind {
  text('Text'),
  image('Picture'),
  colour('Colour'),
  action('What a tap does');

  const DVStudioPropKind(this.label);

  /// How the kind reads in Studio, for somebody who has never written code.
  final String label;
}

/// One prop of a component: its name, its kind, and the value a use that
/// does not set it gets.
@immutable
class DVStudioComponentProp {
  const DVStudioComponentProp(this.name, this.kind, this.value);

  final String name;
  final DVStudioPropKind kind;
  final Object? value;

  Map<String, Object?> toJson() => <String, Object?>{
        'name': name,
        'kind': kind.name,
        'value': value,
      };

  static DVStudioComponentProp? fromJson(Object? json) {
    if (json is! Map || json['name'] is! String) return null;
    final DVStudioPropKind kind = DVStudioPropKind.values.firstWhere(
      (DVStudioPropKind k) => k.name == json['kind'],
      orElse: () => DVStudioPropKind.text,
    );
    return DVStudioComponentProp(json['name']! as String, kind, json['value']);
  }
}

/// The address the component [name] is kept at.
String dvStudioComponentRoute(String name) => '$dvStudioComponentsPrefix$name';

/// The component kept at [route], or null when [route] is a page's.
String? dvStudioComponentName(String route) =>
    route.startsWith(dvStudioComponentsPrefix)
        ? route.substring(dvStudioComponentsPrefix.length)
        : null;

/// A component named [name], drawn as [root], taking [props].
DVPageDocument dvStudioComponent(
  String name, {
  required DVPageNode root,
  List<DVStudioComponentProp> props = const <DVStudioComponentProp>[],
}) {
  root.properties[_propsKey] = <Object?>[
    for (final DVStudioComponentProp prop in props) prop.toJson(),
  ];
  return DVPageDocument(
    route: dvStudioComponentRoute(name),
    title: name,
    root: root,
  );
}

/// The props [component] takes, in the order they were added.
List<DVStudioComponentProp> dvStudioComponentPropsOf(DVPageDocument component) =>
    <DVStudioComponentProp>[
      for (final Object? raw
          in (component.root.properties[_propsKey] as List?) ?? const <Object?>[])
        ?DVStudioComponentProp.fromJson(raw),
    ];

/// [component] with its props replaced by [props].
void dvStudioSetComponentProps(
  DVPageDocument component,
  List<DVStudioComponentProp> props,
) {
  component.root.properties[_propsKey] = <Object?>[
    for (final DVStudioComponentProp prop in props) prop.toJson(),
  ];
}

/// A use of the component [name], with the [props] it sets.
DVPageNode dvStudioComponentInstance(
  String name, {
  Map<String, Object?> props = const <String, Object?>{},
}) =>
    DVPageNode(
      type: dvStudioComponentType,
      properties: <String, Object?>{
        'component': name,
        'props': <String, Object?>{...props},
      },
    );

/// The component a use of one names.
String? dvStudioComponentOf(DVPageNode node) =>
    node.type == dvStudioComponentType && node.properties['component'] is String
        ? node.properties['component']! as String
        : null;

/// The props a use of a component sets.
Map<String, Object?> dvStudioInstancePropsOf(DVPageNode node) =>
    (node.properties['props'] as Map?)?.cast<String, Object?>() ??
    <String, Object?>{};

/// How deep components may use components before the rest is left out:
/// deep enough for any real design, and a loop stops here.
const int _maxDepth = 8;

/// The use [instance] drawn out: a copy of its component's tree with every
/// prop filled in -- the use's value, else the component's default -- or
/// null when the component is not there.
///
/// [lookup] finds a document by its address; the store's cache by default.
/// Components used inside the component are drawn out too, to a depth, so
/// one that uses itself stops rather than recursing forever.
DVPageNode? dvStudioExpandComponent(
  DVPageNode instance, {
  DVPageDocument? Function(String route)? lookup,
  int depth = 0,
}) {
  final String? name = dvStudioComponentOf(instance);
  if (name == null || depth >= _maxDepth) return null;
  final DVPageDocument? Function(String route) find =
      lookup ?? DVPageStore.cached;
  final DVPageDocument? component = find(dvStudioComponentRoute(name));
  if (component == null) return null;
  final Map<String, Object?> given = dvStudioInstancePropsOf(instance);
  final Map<String, Object?> values = <String, Object?>{
    for (final DVStudioComponentProp prop in dvStudioComponentPropsOf(component))
      prop.name: given.containsKey(prop.name) ? given[prop.name] : prop.value,
  };

  Object? fill(Object? value) {
    if (value is! String || !value.contains('{{')) return value;
    // A value that is one prop and nothing else takes the prop's value as it
    // is; one with words around it has the words kept.
    final RegExpMatch? whole = RegExp(r'^\{\{\s*(\w+)\s*\}\}$').firstMatch(value);
    if (whole != null) return values[whole.group(1)];
    return value.replaceAllMapped(
      RegExp(r'\{\{\s*(\w+)\s*\}\}'),
      (Match m) => '${values[m.group(1)] ?? ''}',
    );
  }

  DVPageNode copy(DVPageNode node) {
    if (node.type == dvStudioComponentType) {
      // A component inside the component: its props may themselves come
      // from this one's.
      final DVPageNode inner = DVPageNode(
        id: node.id,
        type: node.type,
        properties: <String, Object?>{
          ...node.properties,
          'props': <String, Object?>{
            for (final MapEntry<String, Object?> e
                in dvStudioInstancePropsOf(node).entries)
              e.key: fill(e.value),
          },
        },
      );
      return dvStudioExpandComponent(inner, lookup: find, depth: depth + 1) ??
          DVPageNode(id: node.id, type: 'box');
    }
    final Map<String, Object?>? action = node.action;
    final Map<String, Object?>? drawnAction =
        action != null && action['type'] == 'prop'
            ? (values[action['name']] as Map?)?.cast<String, Object?>()
            : action;
    return DVPageNode(
      id: node.id,
      type: node.type,
      layout: node.layout,
      properties: <String, Object?>{
        for (final MapEntry<String, Object?> e in node.properties.entries)
          if (e.key != _propsKey) e.key: fill(e.value),
      },
      action: drawnAction,
      breakpoints: <String, Map<String, Object?>>{
        for (final MapEntry<String, Map<String, Object?>> b
            in node.breakpoints.entries)
          b.key: <String, Object?>{
            for (final MapEntry<String, Object?> e in b.value.entries)
              e.key: fill(e.value),
          },
      },
      children: <DVPageNode>[for (final DVPageNode c in node.children) copy(c)],
    );
  }

  return copy(component.root);
}

/// A use of a component on a page, drawn from the component as it is now,
/// and again whenever it changes.
class DVStudioComponentView extends StatefulWidget {
  const DVStudioComponentView(this.node, {super.key});

  final DVPageNode node;

  @override
  State<DVStudioComponentView> createState() => _DVStudioComponentViewState();
}

class _DVStudioComponentViewState extends State<DVStudioComponentView> {
  StreamSubscription<String>? _changes;

  @override
  void initState() {
    super.initState();
    if (!DVPageStore.isPrimed) {
      unawaited(DVPageStore.prime().then((_) {
        if (mounted) setState(() {});
      }));
    }
    // Any component: a use of one component may draw others inside it.
    _changes = DVPageStore.changes.listen((String route) {
      if (dvStudioComponentName(route) != null && mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    unawaited(_changes?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final DVPageNode? drawn = dvStudioExpandComponent(widget.node);
    // A component somebody deleted is left out of the page, not an error in
    // the middle of it.
    if (drawn == null) return const SizedBox.shrink();
    return DVPageDocumentRenderer(DVPageDocument(route: '', root: drawn));
  }
}

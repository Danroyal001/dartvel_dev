import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// A serializable shortcut. [command] refers to a callback supplied by the app;
/// loading data never evaluates code or invokes the callback.
class const DVShortcut({
  required final String keys,
  required final String command,
  required final String label,
  final bool allowInTextFields = false,
}) {
  factory DVShortcut.fromJson(Map<String, Object?> json) {
    if (json['keys'] is! String ||
        json['command'] is! String ||
        json['label'] is! String ||
        (json.containsKey('allowInTextFields') &&
            json['allowInTextFields'] is! bool)) {
      throw ArgumentError.value(json, 'json', 'Invalid shortcut definition');
    }
    final result = DVShortcut(
      keys: json['keys']! as String,
      command: json['command']! as String,
      label: json['label']! as String,
      allowInTextFields: json['allowInTextFields'] as bool? ?? false,
    );
    result.validate();
    return result;
  }

  Map<String, Object?> toJson() => {
    'keys': keys,
    'command': command,
    'label': label,
    'allowInTextFields': allowInTextFields,
  };

  /// Fail early for malformed data, including unknown keys and modifiers.
  void validate() {
    if (command.trim().isEmpty || label.trim().isEmpty) {
      throw ArgumentError('A shortcut needs a command and a label');
    }
    _parse(keys, .windows);
    _parse(keys, .macOS);
  }
}

/// Shortcuts for the focused subtree. Put this in a shared layout for app scope
/// or around a page for page scope. The innermost focused scope wins.
///
/// Press `?` outside a text field to see the available shortcuts. Text fields
/// keep their keys unless a definition explicitly allows use while editing.
class const DVShortcutScope(
  final Map<String, VoidCallback> bindings, {
  super.key,
  required final Widget child,
  final bool showHelp = true,
  final List<DVShortcut>? definitions,
}) extends StatefulWidget {
  /// Definitions that Studio or another editor can store as JSON, paired with
  /// an explicit, application-owned command registry.
  const DVShortcutScope.commands(
    List<DVShortcut> commands, {
    Key? key,
    required Map<String, VoidCallback> actions,
    required Widget child,
    bool showHelp = true,
  }) : this(
         actions,
         definitions: commands,
         key: key,
         child: child,
         showHelp: showHelp,
       );

  List<DVShortcut> get commands =>
      definitions ??
      [
        for (final keys in bindings.keys)
          DVShortcut(keys: keys, command: keys, label: keys),
      ];
  Map<String, VoidCallback> get actions => bindings;

  @override
  State<DVShortcutScope> createState() => _DVShortcutScopeState();
}

class _DVShortcutScopeState extends State<DVShortcutScope> {
  bool _showingHelp = false;
  final _focus = FocusNode(debugLabel: 'Dartvel shortcuts');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final current = FocusManager.instance.primaryFocus;
      if (current == null || _focus.ancestors.contains(current)) {
        _focus.requestFocus();
      }
    });
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final platform = Theme.of(context).platform;
    final own = <_Binding>[];
    final seen = <String>{};
    for (final definition in widget.commands) {
      definition.validate();
      final parsed = _parse(definition.keys, platform);
      if (!seen.add(parsed.id) ||
          (widget.showHelp && parsed.id == _parse('?', platform).id)) {
        throw ArgumentError('Conflicting shortcut: ${definition.keys}');
      }
      final callback = widget.actions[definition.command];
      if (callback == null) {
        throw ArgumentError('No action registered for ${definition.command}');
      }
      own.add(_Binding(definition, parsed, callback));
    }
    final inherited =
        _ShortcutScope.maybeOf(context)?.bindings ?? const <_Binding>[];
    final available = [
      ...inherited.where((binding) => !seen.contains(binding.parsed.id)),
      ...own,
    ];
    return _ShortcutScope(
      bindings: available,
      child: Focus(
        focusNode: _focus,
        autofocus: true,
        onKeyEvent: (node, event) {
          if (event is! KeyDownEvent) return .ignored;
          final editing = _isEditing;
          for (final binding in own) {
            if (binding.parsed.activator.accepts(
              event,
              HardwareKeyboard.instance,
            )) {
              if (editing && !binding.definition.allowInTextFields) {
                return .ignored;
              }
              binding.callback();
              return .handled;
            }
          }
          if (widget.showHelp &&
              !editing &&
              _parse(
                '?',
                platform,
              ).activator.accepts(event, HardwareKeyboard.instance)) {
            _showHelp(available, platform);
            return .handled;
          }
          return .ignored;
        },
        child: widget.child,
      ),
    );
  }

  bool get _isEditing {
    final focused = FocusManager.instance.primaryFocus?.context;
    return focused != null &&
        (focused.widget is EditableText ||
            focused.findAncestorWidgetOfExactType<EditableText>() != null);
  }

  void _showHelp(List<_Binding> bindings, TargetPlatform platform) {
    if (_showingHelp) return;
    NavigatorState? navigator = Navigator.maybeOf(context);
    // App scope may wrap the Navigator in MaterialApp.builder.
    void findNavigator(Element element) {
      if (navigator != null) return;
      if (element is StatefulElement && element.state is NavigatorState) {
        navigator = element.state as NavigatorState;
      } else {
        element.visitChildren(findNavigator);
      }
    }

    if (navigator == null) context.visitChildElements(findNavigator);
    if (navigator == null) return;
    _showingHelp = true;
    unawaited(
      navigator!
          .push<void>(
            DialogRoute<void>(
              context: context,
              builder: (dialogContext) => AlertDialog(
                title: const Text('Keyboard shortcuts'),
                content: SizedBox(
                  width: 420,
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: .min,
                      children: [
                        for (final binding in bindings)
                          ListTile(
                            title: Text(binding.definition.label),
                            subtitle: Text(
                              _display(binding.definition.keys, platform),
                            ),
                          ),
                        const ListTile(
                          title: Text('Show keyboard shortcuts'),
                          subtitle: Text('?'),
                        ),
                      ],
                    ),
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(dialogContext).pop(),
                    child: const Text('Close'),
                  ),
                ],
              ),
            ),
          )
          .whenComplete(() => _showingHelp = false),
    );
  }
}

class const _ShortcutScope({
  required final List<_Binding> bindings,
  required super.child,
}) extends InheritedWidget {
  static _ShortcutScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_ShortcutScope>();
  @override
  bool updateShouldNotify(_ShortcutScope oldWidget) => true;
}

class const _Binding(
  final DVShortcut definition,
  final _Parsed parsed,
  final VoidCallback callback,
);
class const _Parsed(final SingleActivator activator, final String id);

String _display(String keys, TargetPlatform platform) => keys
    .toLowerCase()
    .replaceAll('mod', platform == .macOS || platform == .iOS ? 'Cmd' : 'Ctrl');

_Parsed _parse(String source, TargetPlatform platform) {
  var keys = source.toLowerCase().trim();
  if (keys == '?') keys = 'shift+slash';
  final parts = keys.split('+').map((part) => part.trim()).toList();
  final modifiers = <String>{};
  for (var modifier in parts.take(parts.length - 1)) {
    if (modifier == 'mod') {
      modifier = platform == .macOS || platform == .iOS ? 'meta' : 'ctrl';
    }
    if (modifier == 'cmd') modifier = 'meta';
    if (modifier == 'control') modifier = 'ctrl';
    if (!const {'ctrl', 'meta', 'alt', 'shift'}.contains(modifier) ||
        !modifiers.add(modifier)) {
      throw ArgumentError.value(
        source,
        'keys',
        'Invalid or duplicate modifier',
      );
    }
  }
  final name = parts.last;
  final key = _keys[name];
  if (key == null) throw ArgumentError.value(source, 'keys', 'Unknown key');
  final sorted = modifiers.toList()..sort();
  return _Parsed(
    SingleActivator(
      key,
      control: modifiers.contains('ctrl'),
      meta: modifiers.contains('meta'),
      alt: modifiers.contains('alt'),
      shift: modifiers.contains('shift'),
      includeRepeats: false,
    ),
    '${sorted.join('+')}+${key.keyId}',
  );
}

final Map<String, LogicalKeyboardKey> _keys = {
  for (var code = 97; code <= 122; code++)
    String.fromCharCode(code): LogicalKeyboardKey(code),
  for (var code = 48; code <= 57; code++)
    String.fromCharCode(code): LogicalKeyboardKey(code),
  'enter': .enter,
  'escape': .escape,
  'esc': .escape,
  'space': .space,
  'tab': .tab,
  'backspace': .backspace,
  'delete': .delete,
  'home': .home,
  'end': .end,
  'up': .arrowUp,
  'down': .arrowDown,
  'left': .arrowLeft,
  'right': .arrowRight,
  'pageup': .pageUp,
  'pagedown': .pageDown,
  'slash': .slash,
  '/': .slash,
  'comma': .comma,
  ',': .comma,
  'period': .period,
  '.': .period,
  'minus': .minus,
  '-': .minus,
  'equal': .equal,
  '=': .equal,
  for (var i = 1; i <= 12; i++)
    'f$i': LogicalKeyboardKey(LogicalKeyboardKey.f1.keyId + i - 1),
};

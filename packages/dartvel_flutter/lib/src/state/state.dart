// State management - Simple but powerful
import 'dart:developer' as developer;
import 'package:flutter/foundation.dart';

/// Observable value
class Observable<T> extends ChangeNotifier implements ValueListenable<T> {
  T _value;

  Observable(this._value);

  @override
  T get value => _value;

  set value(T newValue) {
    if (_value != newValue) {
      _value = newValue;
      notifyListeners();
    }
  }

  void update(T Function(T current) updater) {
    value = updater(_value);
  }
}

/// Store base class
abstract class Store extends ChangeNotifier {
  void dispatch(Object? action);
}

/// Simple store implementation
class SimpleStore<TState> extends Store {
  TState _state;
  final TState Function(TState, Object?) _reducer;

  SimpleStore(TState initialState, this._reducer) : _state = initialState;

  TState get state => _state;

  @override
  void dispatch(Object? action) {
    final newState = _reducer(_state, action);
    if (newState != _state) {
      _state = newState;
      notifyListeners();
    }
  }

  T select<T>(T Function(TState) selector) {
    return selector(_state);
  }
}

/// Global state container
class GlobalState {
  static final Map<Type, Store> _stores = {};

  static void register<T extends Store>(T store) {
    _stores[T] = store;
  }

  static T use<T extends Store>() {
    final store = _stores[T];
    if (store == null) {
      throw StateError('Store $T not registered');
    }
    return store as T;
  }

  static bool has<T extends Store>() => _stores.containsKey(T);
}

/// Middleware support
typedef Middleware<TState> = Object? Function(
  TState state,
  Object? action,
  void Function(Object?) dispatch,
);

class StoreWithMiddleware<TState> extends SimpleStore<TState> {
  final List<Middleware<TState>> _middleware;

  StoreWithMiddleware(
    super.initialState,
    super.reducer,
    this._middleware,
  );

  @override
  void dispatch(Object? action) {
    Object? currentAction = action;

    for (final middleware in _middleware) {
      final result = middleware(_state, currentAction, dispatch);
      if (result != null) {
        currentAction = result;
      }
    }

    super.dispatch(currentAction);
  }
}

/// Async action support
class AsyncAction<T> {
  final Future<T> Function() execute;
  final void Function(T result)? onSuccess;
  final void Function(Object error)? onError;

  AsyncAction(this.execute, {this.onSuccess, this.onError});
}

/// Async middleware
Middleware<TState> asyncMiddleware<TState>() {
  return (state, action, dispatch) {
    if (action is AsyncAction) {
      action.execute().then((result) {
        action.onSuccess?.call(result);
      }).catchError((error) {
        action.onError?.call(error);
      });
      return null; // Don't pass async actions to reducer
    }
    return action;
  };
}

Middleware<TState> loggingMiddleware<TState>() {
  return (state, action, dispatch) {
    developer.log('[Action] ${action.runtimeType}', name: 'dartvel');
    return action;
  };
}

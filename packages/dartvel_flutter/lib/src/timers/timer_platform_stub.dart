/// No platform: timers in memory, rung by the plain delivery.
library;

import 'timer_basic_delivery.dart';
import 'timer_delivery.dart';

DVTimerStore dvPlatformTimerStore(String app) => _MemoryStore();

DVTimerDelivery dvPlatformTimerDelivery({required bool declared}) => DVBasicTimerDelivery();

void dvTimerWatchStore(String app, void Function() changed) {}

final class _MemoryStore implements DVTimerStore {
  String? _value;

  @override
  String? read() => _value;

  @override
  void write(String value) => _value = value;
}

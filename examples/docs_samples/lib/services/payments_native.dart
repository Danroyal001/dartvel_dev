// The Dart surface of a module backed by a Rust crate, as the modules page
// shows it. Nothing here imports it: it is compiled by analysis, and a web
// build could not take dart:ffi anyway.
//
// docs:start modules-native-ffi
// modules/payments/lib/payments.dart
import 'dart:ffi';

// The crate's payments_fee, bound by its symbol. The module's build hook
// compiles the crate for the target being built and registers the library
// under this file's asset id, so no path or platform is written here.
@Native<Int64 Function(Int64)>(symbol: 'payments_fee')
external int _paymentsFee(int amountMinor);

/// The fee on [amountMinor], in the same minor units.
///
/// This is all the parent calls. It cannot tell a crate is underneath.
int paymentFee(int amountMinor) => _paymentsFee(amountMinor);
// docs:end

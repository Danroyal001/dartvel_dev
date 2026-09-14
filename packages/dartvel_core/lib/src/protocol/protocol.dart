/// Protocol versioning and client compatibility.
///
/// The backend deploys daily and installed binaries live for weeks. This is
/// the machinery that answers what a three-week-old binary gets when it calls
/// today's backend: a protocol version over the contract, a committed lockfile
/// holding its history, a window of versions the backend still serves, the
/// adaptations it may apply to them, the handshake a client runs, and the
/// deploy gate that refuses to strand the clients actually calling.
library dartvel_core.protocol;

export 'compatibility.dart';
export 'compatibility_check.dart';
export 'contract.dart';
export 'handshake.dart';

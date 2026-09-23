/// Global Privacy Control: a header that is an instruction, not a preference.
///
/// A browser, or an extension somebody installed deliberately, sends
/// `Sec-GPC: 1`. California's CPRA treats that as a valid opt-out of the sale
/// or sharing of personal information, and Colorado's and Connecticut's laws
/// followed. There is nothing to click and nothing to confirm: the signal
/// arrived, and the business honours it.
///
/// Dropping it is the quiet failure. Nothing throws, the page renders, the
/// events are collected, and the way anybody finds out is a regulator asking
/// why a signal the browser sent was ignored. So it is read once where the
/// request arrives, carried through everything that request does, and
/// answered where consent is already decided — `DVConsent.isGranted` — rather
/// than wherever somebody remembers to check.
///
/// What it opts out of is sale and sharing, which is what a consent category
/// declared `tracking: true` means here. A first-party measurement category
/// is untouched: denying that too would be a framework answering a question
/// the law did not ask.
library dartvel_core.privacy.opt_out;

import 'dart:async';

/// The header, as the specification spells it.
const String dvGlobalPrivacyControlHeader = 'Sec-GPC';

/// Zone key carrying the opt-out through [dvWithPrivacyOptOut] scopes.
const Symbol _zoneOptOut = #dartvelPrivacyOptOut;

/// Whether [headers] carry a Global Privacy Control signal.
///
/// One value counts. `Sec-GPC: 0` is a browser saying it is not sending the
/// signal, which is not consent to anything and is certainly not an opt-out,
/// and no other value is defined.
///
/// Header names are matched without case, because they arrive lower-cased
/// from every server this runs behind and are written `Sec-GPC` everywhere
/// else.
bool dvGlobalPrivacyControl(Map<String, String> headers) {
  for (final MapEntry<String, String> header in headers.entries) {
    if (header.key.toLowerCase() != 'sec-gpc') continue;
    if (header.value.trim() == '1') return true;
  }
  return false;
}

/// Whether the work in progress is for somebody who opted out.
///
/// False when nobody said, which is the answer for a job, a migration or a
/// test: no request, no signal, nothing to honour.
bool get dvPrivacyOptOut => Zone.current[_zoneOptOut] as bool? ?? false;

/// Runs [body] with [optedOut] in force for all of it.
///
/// A zone value rather than a field, for the reason the tenant scope is one:
/// a server has more than one request in flight, Dart hands the isolate over
/// at every await, and a field written at the top of a handler is the next
/// request's answer by the time this one comes back. That mistake here would
/// mean honouring one visitor's opt-out for another visitor, and collecting
/// from the one who sent it.
R dvWithPrivacyOptOut<R>(bool optedOut, R Function() body) => runZoned(
      body,
      zoneValues: <Object?, Object?>{_zoneOptOut: optedOut},
    );

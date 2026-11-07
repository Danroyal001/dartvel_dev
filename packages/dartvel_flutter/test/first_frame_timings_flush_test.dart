// The web engine reports frame timings in batches, and only when a frame
// finishes more than 100 ms after the last batch. waitUntilFirstFrameRasterized
// completes from those timings, so an application whose first frames all
// finish inside one 100 ms window and then goes idle never hears that its
// first frame was rasterized. Multi-threaded skwasm does exactly that, and the
// handover from the splash never happened: the splash and its loading bar
// stayed over a running app until something else drew a frame.
//
// The test binding draws frames its own way and never completes the
// first-frame future from timings, so the future is supplied here.
import 'dart:async';

import 'package:dartvel_flutter/src/routing/first_frame_gate.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'keeps producing frames until the first frame is reported rasterized',
    (tester) async {
      await tester.pumpWidget(const SizedBox());
      final Completer<void> rasterized = Completer<void>();
      bool done = false;
      unawaited(dvFlushFirstFrameTimings(tester.binding,
              rasterized: rasterized.future)
          .then((_) => done = true));

      // Idle: nothing is dirty, so without the flush no frame would come and
      // the engine would never send the batch holding the first frame.
      expect(tester.binding.hasScheduledFrame, isFalse);
      await tester.binding.delayed(const Duration(milliseconds: 150));
      expect(tester.binding.hasScheduledFrame, isTrue,
          reason: 'a later frame is what releases the batched timings');
      await tester.pump();
      await tester.binding.delayed(const Duration(milliseconds: 150));
      expect(tester.binding.hasScheduledFrame, isTrue,
          reason: 'and it keeps asking while nothing has been reported');
      expect(done, isFalse);

      rasterized.complete();
      await tester.pump();
      expect(done, isTrue);
      await tester.binding.delayed(const Duration(milliseconds: 300));
      expect(tester.binding.hasScheduledFrame, isFalse,
          reason: 'it stops once the first frame is reported');
    },
  );
}

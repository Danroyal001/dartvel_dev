import 'dart:async';
import 'dart:ui' show FrameTiming;

import 'package:dartvel_flutter/src/routing/first_frame_gate.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

FrameTiming timing(int start) => FrameTiming(
  vsyncStart: start,
  buildStart: start + 1,
  buildFinish: start + 2,
  rasterStart: start + 3,
  rasterFinish: start + 4,
  rasterFinishWallTime: start + 4,
);

void main() {
  testWidgets(
    'handover waits for a fresh post-layout raster, not an old batch',
    (tester) async {
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const .new(milliseconds: 10));
      final start = tester.binding.currentSystemFrameTimeStamp.inMicroseconds;
      bool complete = false;
      final waiting = dvWaitForPostLayoutRaster(tester.binding);
      unawaited(
        waiting.then((_) {
          complete = true;
        }),
      );
      try {
        await tester.pump();
        expect(
          complete,
          isFalse,
          reason: 'scroll metrics still need a rendered frame',
        );
        tester.binding.platformDispatcher.onReportTimings?.call([
          timing(start - 1),
        ]);
        await tester.pump();
        expect(
          complete,
          isFalse,
          reason: 'an earlier frame is not settled layout',
        );
        tester.binding.platformDispatcher.onReportTimings?.call([
          timing(start + 16667),
        ]);
        await tester.pump();
        expect(complete, isTrue);
        expect(
          tester.binding.hasScheduledFrame,
          isFalse,
          reason: 'the readiness pump stops once the frame has rendered',
        );
      } finally {
        tester.binding.platformDispatcher.onReportTimings?.call([
          timing(start + 100000),
        ]);
        await tester.pump();
        await waiting;
      }
    },
  );
}

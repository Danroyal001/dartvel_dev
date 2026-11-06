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

  testWidgets(
    'handover waits for a visible scrollbar thumb to finish fading in',
    (tester) async {
      final controller = ScrollController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        Directionality(
          textDirection: .ltr,
          child: MediaQuery(
            data: const .new(size: .new(400, 300)),
            child: RawScrollbar(
              controller: controller,
              thumbVisibility: true,
              fadeDuration: const .new(milliseconds: 300),
              child: SingleChildScrollView(
                controller: controller,
                child: const SizedBox(width: 400, height: 1200),
              ),
            ),
          ),
        ),
      );
      ScrollbarPainter painter() => tester
          .widgetList<CustomPaint>(find.byType(CustomPaint))
          .map((paint) => paint.foregroundPainter)
          .whereType<ScrollbarPainter>()
          .single;
      final start = tester.binding.currentSystemFrameTimeStamp.inMicroseconds;
      bool complete = false;
      final waiting = dvWaitForPostLayoutRaster(tester.binding);
      unawaited(
        waiting.then((_) {
          complete = true;
        }),
      );
      try {
        await tester.pump(const .new(milliseconds: 16));
        tester.binding.platformDispatcher.onReportTimings?.call([
          timing(start + 16667),
        ]);
        await tester.pump();
        expect(
          painter().fadeoutOpacityAnimation.value,
          lessThan(1.0),
        );
        expect(
          complete,
          isFalse,
          reason: 'the first frame after layout still has a fading thumb',
        );
        await tester.pump(const .new(milliseconds: 350));
        final settled =
            tester.binding.currentSystemFrameTimeStamp.inMicroseconds;
        expect(painter().fadeoutOpacityAnimation.value, 1.0);
        tester.binding.platformDispatcher.onReportTimings?.call([
          timing(settled + 1000),
        ]);
        await tester.pump();
        expect(complete, isTrue);
      } finally {
        await tester.pump(const .new(milliseconds: 400));
        final end = tester.binding.currentSystemFrameTimeStamp.inMicroseconds;
        tester.binding.platformDispatcher.onReportTimings?.call([
          timing(end + 100000),
        ]);
        await tester.pump();
        await waiting;
      }
    },
  );
}

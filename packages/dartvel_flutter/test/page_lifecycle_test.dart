// context.lifecycle.page, which nothing could reach.
//
// The specification writes `context.lifecycle.page.listen(...)` in a page,
// and a page's context is a BuildContext. There was no lifecycle extension
// on BuildContext at all, so that line did not compile; and
// DVContextLifecycle.page threw for want of a signal, because the only thing
// that ever built a DVContext was DV.transaction.
//
// The enum, the signal type, the getter and its refusal message all existed.
// What was missing is the one thing that makes any of it observable.
// DVPageLifecycle and DVLifecycleSignal come through the dartvel_flutter
// barrel, which is what an application imports; naming dartvel_core here as
// well is the import a page would not write.
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// A page that records every state its own lifecycle reaches.
class _Watcher extends StatefulWidget {
  const _Watcher(this.seen);

  final List<DVPageLifecycle> seen;

  @override
  State<_Watcher> createState() => _WatcherState();
}

class _WatcherState extends State<_Watcher> {
  bool _listening = false;

  @override
  Widget build(BuildContext context) {
    if (!_listening) {
      _listening = true;
      context.lifecycle.page.listen(widget.seen.add);
    }
    return const SizedBox.shrink();
  }
}

void main() {
  testWidgets('a page reaches active, and only after a frame', (tester) async {
    // Ready is "there is something to show"; active is "there is something on
    // screen". A page that reported active at the end of build would say so
    // before anybody could have seen it, which is the same mistake the
    // application signal made until it moved into the frame callback.
    final List<DVPageLifecycle> seen = <DVPageLifecycle>[];

    await tester.pumpWidget(
      DVPageLifecycleHost(child: _Watcher(seen)),
    );

    // The listener attaches during the first build, so `ready` may already
    // have been set; what must not have happened yet is the frame.
    expect(seen, isNot(contains(DVPageLifecycle.active)));

    await tester.pump();
    expect(seen, contains(DVPageLifecycle.active));
  });

  testWidgets('the signal a page reads is its own', (tester) async {
    // Two pages are alive at once whenever one is leaving as the next
    // enters, and in a tab workspace routinely. A process-wide signal would
    // report whichever moved last for both of them.
    late DVLifecycleSignal<DVPageLifecycle> first;
    late DVLifecycleSignal<DVPageLifecycle> second;

    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Column(
          children: <Widget>[
            DVPageLifecycleHost(
              child: Builder(builder: (BuildContext context) {
                first = context.lifecycle.page;
                return const SizedBox.shrink();
              }),
            ),
            DVPageLifecycleHost(
              child: Builder(builder: (BuildContext context) {
                second = context.lifecycle.page;
                return const SizedBox.shrink();
              }),
            ),
          ],
        ),
      ),
    );

    expect(identical(first, second), isFalse);
  });

  testWidgets('leaving is said before it is done', (tester) async {
    // disposed is the last thing a listener will ever see, so it has to
    // arrive; disposing before it is the difference between "this is ending"
    // and "this has ended".
    final List<DVPageLifecycle> seen = <DVPageLifecycle>[];

    await tester.pumpWidget(DVPageLifecycleHost(child: _Watcher(seen)));
    await tester.pump();
    await tester.pumpWidget(const SizedBox.shrink());

    final int disposing = seen.indexOf(DVPageLifecycle.disposing);
    final int disposed = seen.indexOf(DVPageLifecycle.disposed);
    expect(disposing, greaterThan(-1));
    expect(disposed, greaterThan(disposing));
  });

  testWidgets('outside a page it refuses rather than inventing one',
      (tester) async {
    // A widget that is not a page has no page lifecycle, and answering with
    // a signal that never moves would be worse than the refusal: it reads as
    // a page that is stuck.
    late BuildContext outside;

    await tester.pumpWidget(
      Builder(builder: (BuildContext context) {
        outside = context;
        return const SizedBox.shrink();
      }),
    );

    expect(() => outside.lifecycle.page, throwsStateError);
  });

  testWidgets('a request or a transaction is not a fact about a widget',
      (tester) async {
    late BuildContext inside;

    await tester.pumpWidget(
      DVPageLifecycleHost(
        child: Builder(builder: (BuildContext context) {
          inside = context;
          return const SizedBox.shrink();
        }),
      ),
    );

    expect(() => inside.lifecycle.request, throwsStateError);
    expect(() => inside.lifecycle.transaction, throwsStateError);
  });
}

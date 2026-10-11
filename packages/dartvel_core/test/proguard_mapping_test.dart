// Retracing an R8 stack trace.
//
// A release build renames every class and method and collapses line numbers,
// so a stack from a user's phone says `a.a.a.onCreate(SourceFile:2)`. These
// tests hold the retracer to R8's own rules for turning that back: a line in
// a range maps linearly into the original range, a single original line
// means every minified line in the range is that line, and a minified range
// shared by several entries is an inlined chain that expands to several
// frames. Each of those is silent when wrong -- a plausible method name on a
// wrong line is worse than the obfuscated one.
import 'package:dartvel_core/dartvel.dart';
import 'package:test/test.dart';

import 'fixtures/r8_mapping.dart';

void main() {
  late DVProguardMapping mapping;
  setUp(() => mapping = DVProguardMapping.parse(r8Mapping));

  group('classes', () {
    test('a minified class name maps back to the original', () {
      expect(mapping.originalClass('a.a.a'), 'com.example.shop.CheckoutActivity');
      expect(mapping.originalClass('a.a.b'),
          'com.example.shop.CheckoutActivity\$Companion');
    });

    test('a class the mapping does not name is returned as it was', () {
      // Framework and library classes are not renamed (or are kept by rule);
      // inventing a name for one would be a lie.
      expect(mapping.originalClass('android.os.Handler'), 'android.os.Handler');
    });

    test('comments and field lines do not break parsing', () {
      expect(mapping.classCount, 3);
    });
  });

  group('frames', () {
    test('a line in a range maps linearly into the original range', () {
      // 1:3 -> 12:14, so minified line 2 is original line 13.
      final List<DVRetracedFrame> frames =
          mapping.retraceFrame('a.a.a', 'onCreate', 2);
      expect(frames, hasLength(1));
      expect(frames.single.className, 'com.example.shop.CheckoutActivity');
      expect(frames.single.methodName, 'onCreate');
      expect(frames.single.line, 13);
    });

    test('the first line of a range is the first original line', () {
      expect(mapping.retraceFrame('a.a.a', 'onCreate', 1).single.line, 12);
      expect(mapping.retraceFrame('a.a.a', 'onCreate', 3).single.line, 14);
    });

    test('a single original line means every minified line is that line', () {
      // 5:9 -> 40:44 is linear; `:30` alone is "line 30, whichever".
      expect(mapping.retraceFrame('a.a.a', 'b', 7).single.line, 42);
      final List<DVRetracedFrame> inlined =
          mapping.retraceFrame('a.a.a', 'onCreate', 4);
      expect(inlined.first.line, 30);
    });

    test('an inlined chain expands innermost first', () {
      final List<DVRetracedFrame> frames =
          mapping.retraceFrame('a.a.a', 'onCreate', 4);
      expect(frames.map((DVRetracedFrame f) => f.methodName),
          <String>['validate', 'onCreate']);
      expect(frames.map((DVRetracedFrame f) => f.line), <int>[30, 15]);
    });

    test('the same original method on two minified ranges keeps both lines', () {
      expect(mapping.retraceFrame('a.b', 'b', 1).single.line, 10);
      expect(mapping.retraceFrame('a.b', 'b', 2).single.line, 11);
    });

    test('a method with no line information keeps the line it was given', () {
      final List<DVRetracedFrame> frames = mapping.retraceFrame('a.a.a', 'c', 77);
      expect(frames.single.methodName, 'reset');
      expect(frames.single.line, 77);
    });

    test('a line outside every range still names the method', () {
      final List<DVRetracedFrame> frames =
          mapping.retraceFrame('a.a.a', 'onCreate', 500);
      expect(frames, isNotEmpty);
      expect(frames.every((DVRetracedFrame f) => f.methodName.isNotEmpty), isTrue);
      expect(frames.first.line, 500);
    });

    test('an unknown method on a known class keeps its name and the class is mapped',
        () {
      final List<DVRetracedFrame> frames = mapping.retraceFrame('a.a.a', 'zzz', 3);
      expect(frames.single.className, 'com.example.shop.CheckoutActivity');
      expect(frames.single.methodName, 'zzz');
    });

    test('a class that is not in the mapping passes through untouched', () {
      final List<DVRetracedFrame> frames =
          mapping.retraceFrame('android.app.Activity', 'performCreate', 8000);
      expect(frames.single.className, 'android.app.Activity');
      expect(frames.single.methodName, 'performCreate');
      expect(frames.single.line, 8000);
    });

    test('the source file comes from the mapping, else from the outer class', () {
      expect(mapping.retraceFrame('a.a.a', 'onCreate', 1).single.fileName,
          'CheckoutActivity.kt');
      expect(mapping.retraceFrame('a.b', 'a', null).single.fileName,
          'PaymentGateway.java');
    });
  });

  group('stack traces', () {
    const String trace = '''
java.lang.IllegalStateException: cart is empty
\tat a.a.a.onCreate(SourceFile:2)
\tat a.a.a.onCreate(SourceFile:4)
\tat android.app.Activity.performCreate(Activity.java:8000)
Caused by: a.b: gateway down
\tat a.b.b(SourceFile:1)
\t... 12 more''';

    test('every frame and every named class is retraced', () {
      final String out = mapping.retrace(trace);
      expect(out, contains('at com.example.shop.CheckoutActivity.onCreate(CheckoutActivity.kt:13)'));
      expect(out, contains('Caused by: com.example.shop.PaymentGateway: gateway down'));
      expect(out, contains('at com.example.shop.PaymentGateway.charge(PaymentGateway.java:10)'));
    });

    test('an inlined frame expands into one line per original frame', () {
      final String out = mapping.retrace(trace);
      expect(out, contains('at com.example.shop.CheckoutActivity.validate(CheckoutActivity.kt:30)'));
      expect(out, contains('at com.example.shop.CheckoutActivity.onCreate(CheckoutActivity.kt:15)'));
    });

    test('lines that are not frames are kept as they were', () {
      final String out = mapping.retrace(trace);
      expect(out, contains('java.lang.IllegalStateException: cart is empty'));
      expect(out, contains('\t... 12 more'));
      expect(out, contains('at android.app.Activity.performCreate(Activity.java:8000)'));
    });

    test('indentation survives', () {
      expect(mapping.retrace('\tat a.b.a(SourceFile:1)'),
          startsWith('\tat com.example.shop.PaymentGateway.charge('));
    });

    test('an empty mapping retraces nothing and does not fail', () {
      expect(DVProguardMapping.parse('').retrace(trace), trace);
    });
  });

  group('parsing', () {
    test('a mapping line it cannot read is skipped, not fatal', () {
      final DVProguardMapping partial = DVProguardMapping.parse('''
com.example.A -> a.A:
    this is not a member line at all
    1:1:void ok():5:5 -> a
''');
      expect(partial.retraceFrame('a.A', 'a', 1).single.methodName, 'ok');
    });

    test('Windows line endings parse the same', () {
      final DVProguardMapping crlf =
          DVProguardMapping.parse(r8Mapping.replaceAll('\n', '\r\n'));
      expect(crlf.originalClass('a.a.a'), 'com.example.shop.CheckoutActivity');
      expect(crlf.retraceFrame('a.a.a', 'onCreate', 2).single.line, 13);
    });
  });
}

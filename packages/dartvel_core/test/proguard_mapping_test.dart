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
import 'fixtures/r8_real_mapping.dart';

void main() {
  realR8Tests();
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

// The expected frames below are what R8's own `retrace` printed for the same
// mapping excerpt and stack lines (fixtures/r8_real_mapping.dart).
void realR8Tests() {
  final DVProguardMapping mapping = DVProguardMapping.parse(r8RealMapping);
  String frames(String className, String method, int? line) =>
      mapping.retraceFrame(className, method, line).join('\n');

  group('against R8\'s own retrace', () {
    const String base = 'com.google.android.gms:play-services-base@@18.9.0';
    const String basement = 'com.google.android.gms:play-services-basement@@18.9.0';

    test('a minified range onto a single original line maps every line to it',
        () {
      // `5:14 -> :1:1` is line 1 for all of 5..14, not 1 + (line - 5).
      expect(frames('tx', 'a', 11),
          'com.google.android.gms.signin.internal.SignInClientImpl.createServiceInterface($base:1)');
    });

    test('an inlined method is a frame of its own class, in that class\'s file',
        () {
      expect(frames('tx', 'a', 21), '''
com.google.android.gms.signin.internal.zaf.<init>($base:1)
com.google.android.gms.signin.internal.SignInClientImpl.createServiceInterface($base:2)''');
    });

    test('line 0 means no line, and prints none', () {
      expect(frames('tx', 'e', 3), '''
com.google.android.gms.common.internal.ClientSettings.getRealClientPackageName($base)
com.google.android.gms.signin.internal.SignInClientImpl.getGetServiceRequestExtraArgs($base:1)''');
    });

    test('an inlined class\'s file is the one the mapping gives that class', () {
      expect(frames('tx', 'e', 7), '''
com.google.android.gms.common.internal.BaseGmsClient.getContext($basement)
com.google.android.gms.signin.internal.SignInClientImpl.getGetServiceRequestExtraArgs($base:2)''');
    });

    test('the method the line places is not listed twice', () {
      // The chain ends with the same method again at line 0.
      expect(frames('w1', '<clinit>', 4), '''
com.google.android.datatransport.runtime.AutoProtoEncoderDoNotUseEncoder\$ClientMetricsEncoder.<init>(AutoProtoEncoderDoNotUseEncoder.java:50)
com.google.android.datatransport.runtime.AutoProtoEncoderDoNotUseEncoder\$ClientMetricsEncoder.<clinit>(AutoProtoEncoderDoNotUseEncoder.java:51)''');
      expect(frames('w1', '<clinit>', 24),
          'com.google.android.datatransport.runtime.AutoProtoEncoderDoNotUseEncoder\$ClientMetricsEncoder.<clinit>(AutoProtoEncoderDoNotUseEncoder.java)');
    });

    test('a lambda class R8 made up shows the real method inlined into it, '
        'and not itself', () {
      const String store =
          'com.google.android.datatransport.runtime.scheduling.persistence';
      expect(frames('dv', 'apply', 13),
          '$store.SQLiteEventStore.lambda\$loadBatch\$8(SQLiteEventStore.java:354)');
      expect(frames('dv', 'apply', 15), '''
$store.AutoValue_EventStoreConfig.getLoadBatchSize(AutoValue_EventStoreConfig.java:38)
$store.SQLiteEventStore.lambda\$loadBatch\$8(SQLiteEventStore.java:354)''');
    });

    test('a frame that is only a made-up class is left out of a trace', () {
      expect(mapping.retrace('\tat dv.<init>(SourceFile:3)'), isEmpty);
    });

    test('a Kotlin facade class is in its .kt file', () {
      expect(frames('kotlin.collections.ArraysKt___ArraysJvmKt', 'a', 1),
          'kotlin.collections.ArraysKt___ArraysJvmKt.calculateMaximumDisplayMetrics(ArraysKt___ArraysJvm.kt:5)');
    });
  });
}

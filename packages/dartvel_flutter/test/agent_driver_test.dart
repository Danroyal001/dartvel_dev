// The agent driver on the headless host: one tree (the semantics tree) and a
// few operations an agent uses to see and use a page, the same on every host.
import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _Checkout extends StatefulWidget {
  const _Checkout();

  @override
  State<_Checkout> createState() => _CheckoutState();
}

class _CheckoutState extends State<_Checkout> {
  int orders = 0;
  bool spinning = false;

  @override
  Widget build(BuildContext context) => MaterialApp(
        home: Scaffold(
          body: ListView(
            children: <Widget>[
              Text('Orders: $orders'),
              ElevatedButton(onPressed: () => setState(() => orders++), child: const Text('Place order')),
              const ElevatedButton(onPressed: null, child: Text('Refund')),
              const TextField(decoration: InputDecoration(labelText: 'Email')),
              const TextField(obscureText: true, decoration: InputDecoration(labelText: 'Password')),
              ElevatedButton(onPressed: () => setState(() => spinning = true), child: const Text('Start spinner')),
              if (spinning) const CircularProgressIndicator(),
              for (int index = 0; index < 40; index++) Text('Row $index'),
            ],
          ),
        ),
      );
}

void main() {
  // The driver keeps the semantics tree alive; flutter_test checks that no
  // handle is left open when the body ends, before tear-downs run, so each
  // test closes its driver inside the body.
  void driverTest(String name, Future<void> Function(WidgetTester tester, DVDriver d) body) {
    testWidgets(name, (WidgetTester tester) async {
      await tester.pumpWidget(const _Checkout());
      final DVDriver driver = DV.Test.driver(pump: tester.pump);
      try {
        await tester.pump();
        await body(tester, driver);
      } finally {
        driver.dispose();
      }
    });
  }

  driverTest('the tree is the semantics tree, with refs, roles, labels and actions', (WidgetTester tester, DVDriver d) async {
    final DVDriverTree tree = d.tree();
    expect(tree.treeVersion, 1);
    expect(tree.host, 'vm');
    final DVDriverNode order = tree.nodes.firstWhere((DVDriverNode node) => node.label == 'Place order');
    expect(order.role, 'button');
    expect(order.actions, contains('tap'));
    expect(order.ref, matches(RegExp(r'^n\d+$')));
    expect(tree.toJson()['treeVersion'], 1);
  });

  driverTest('find returns a node by role and label', (WidgetTester tester, DVDriver d) async {
    expect(d.find(role: 'button', label: 'Place order'), isNotNull);
    expect(d.find(label: 'Nothing like this'), isNull);
  });

  driverTest('tap activates a node, and wait returns once the frame is drawn', (WidgetTester tester, DVDriver d) async {
    await d.tap(d.find(role: 'button', label: 'Place order')!);
    await d.wait();
    expect(d.tree().nodes.any((DVDriverNode node) => node.label == 'Orders: 1'), isTrue);
  });

  driverTest('type sets the text of a field', (WidgetTester tester, DVDriver d) async {
    final String email = d.find(role: 'textField', label: 'Email')!;
    await d.type(email, 'ada@example.com');
    await d.wait();
    expect(d.tree().nodes.firstWhere((DVDriverNode node) => node.ref == email).value, 'ada@example.com');
  });

  driverTest('a sensitive field is named, never valued', (WidgetTester tester, DVDriver d) async {
    final String password = d.find(role: 'textField', label: 'Password')!;
    await d.type(password, 'hunter2');
    await d.wait();
    final DVDriverNode node = d.tree().nodes.firstWhere((DVDriverNode n) => n.ref == password);
    expect(node.sensitive, isTrue);
    expect(node.value, isNull);
    expect(d.tree().toJson().toString(), isNot(contains('hunter2')));
  });

  driverTest('a ref for a node that is gone is DV-DRIVER-002, never a tap on something else', (WidgetTester tester, DVDriver d) async {
    await expectLater(d.tap('n999999'), throwsA(isA<DVDriverError>().having((DVDriverError e) => e.code, 'code', 'DV-DRIVER-002')));
  });

  driverTest('a disabled control says so: DV-DRIVER-003', (WidgetTester tester, DVDriver d) async {
    final String refund = d.find(label: 'Refund')!;
    await expectLater(
      d.tap(refund),
      throwsA(isA<DVDriverError>().having((DVDriverError e) => e.code, 'code', 'DV-DRIVER-003').having((DVDriverError e) => e.message, 'message', contains('disabled'))),
    );
  });

  driverTest('scroll brings a node into view', (WidgetTester tester, DVDriver d) async {
    expect(d.find(label: 'Row 39'), isNull);
    await d.scroll(d.find(label: 'Orders: 0')!, toward: DVScrollDirection.down);
    await d.wait();
    for (int attempt = 0; attempt < 10 && d.find(label: 'Row 39') == null; attempt++) {
      final String? anything = d.tree().nodes.where((DVDriverNode n) => n.actions.contains('scrollUp')).map((DVDriverNode n) => n.ref).firstOrNull;
      if (anything == null) break;
      await d.scroll(anything, toward: DVScrollDirection.down);
      await d.wait();
    }
    expect(d.find(label: 'Row 39'), isNotNull);
  });

  driverTest('wait that cannot settle fails with DV-DRIVER-004, naming what is pending', (WidgetTester tester, DVDriver d) async {
    await d.tap(d.find(label: 'Start spinner')!);
    // wait() pumps frames itself, and flutter_test refuses expectLater over a
    // future that is pumping, so the error is caught and then checked.
    DVDriverError? error;
    try {
      await d.wait(timeout: const Duration(milliseconds: 500));
    } on DVDriverError catch (caught) {
      error = caught;
    }
    expect(error?.code, 'DV-DRIVER-004');
    expect(error?.message, contains('animation'));
  });

  driverTest('status names the host and how many nodes the tree has', (WidgetTester tester, DVDriver d) async {
    final Map<String, Object?> status = d.status();
    expect(status['host'], 'vm');
    expect(status['nodes'] as int, greaterThan(5));
  });

  driverTest('logs returns records since a cursor, redacted as everywhere else', (WidgetTester tester, DVDriver d) async {
    final int cursor = d.logs().cursor;
    const DVLog().info('order placed', context: <String, Object?>{'password': 'hunter2'});
    final DVDriverLogs logs = d.logs(since: cursor);
    expect(logs.records.map((Map<String, Object?> r) => r['message']), contains('order placed'));
    expect(logs.records.toString(), isNot(contains('hunter2')));
    expect(logs.cursor, greaterThan(cursor));
  });

  testWidgets('Dartvel primitives are found and used the same way', (WidgetTester tester) async {
    String typed = '';
    int saves = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: StatefulBuilder(
          builder: (BuildContext context, StateSetter setState) => DVBox.list(<Widget>[
            DVText('Saved $saves times'),
            DVText(typed).modifier(DVModifier().input(label: 'Name', onChanged: (String v) => setState(() => typed = v))),
            DVText('Save').modifier(DVModifier().onTap(() => setState(() => saves++))),
          ]),
        ),
      ),
    ));
    final DVDriver d = DV.Test.driver(pump: tester.pump);
    try {
      await tester.pump();
      await d.type(d.find(label: 'Name')!, 'Ada');
      await d.tap(d.find(role: 'button', label: 'Save')!);
      await d.wait();
      expect(typed, 'Ada');
      expect(d.find(label: 'Saved 1 times'), isNotNull);
    } finally {
      d.dispose();
    }
  });
}

// Launch: the arguments an application was started with, and the launches
// that come after it.
//
// An OS-level request to open something -- a file association, a
// dartvel:// link, a second launch of a single-instance application --
// arrives as command-line arguments to a new process. The first process
// takes the lock and opens what it was given; every later one hands its
// arguments to the first and leaves. What the tests hold to: an argument
// maps to a route by a rule that never trusts it as a route outright; the
// primary opens its own arguments and then everything a secondary forwards;
// a secondary knows it is one; stopping stops.
import 'dart:io';

import 'package:dartvel_flutter/dartvel_flutter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('an argument becomes a route', () {
    test('a route is itself', () {
      expect(DVAppLaunch.routeFor('/orders/42'), '/orders/42');
      expect(DVAppLaunch.routeFor('/orders?tab=open'), '/orders?tab=open');
    });

    test('an app link keeps its path and query', () {
      expect(DVAppLaunch.routeFor('dartvel://orders/42?from=mail'), '/orders/42?from=mail');
      expect(DVAppLaunch.routeFor('https://shop.example/orders/42'), '/orders/42');
      expect(DVAppLaunch.routeFor('dartvel://'), '/');
    });

    test('a file goes to the open route, encoded, never as a path of its own', () {
      expect(DVAppLaunch.routeFor('/home/ada/report.pdf'), '/open?path=%2Fhome%2Fada%2Freport.pdf');
      expect(DVAppLaunch.routeFor('/home/ada/report.pdf', filesRoute: '/import'), '/import?path=%2Fhome%2Fada%2Freport.pdf');
      expect(DVAppLaunch.routeFor('file:///home/ada/a%20b.txt'), '/open?path=%2Fhome%2Fada%2Fa%20b.txt');
    });

    test('anything else is nothing', () {
      expect(DVAppLaunch.routeFor('--verbose'), isNull);
      expect(DVAppLaunch.routeFor(''), isNull);
      expect(DVAppLaunch.routeFor('javascript:alert(1)'), isNull);
    });
  });

  group('the process', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('dv_launch_'));
    tearDown(() => dir.deleteSync(recursive: true));

    test('the first launch is primary and opens what it was given', () async {
      final List<String> opened = <String>[];
      final DVAppLaunchResult outcome = await DVAppLaunch.start(
        appId: 'shop',
        arguments: <String>['/orders/42', '/home/ada/report.pdf', '--verbose'],
        lockPath: '${dir.path}/shop.lock',
        open: (String route) async => opened.add(route),
        poll: const Duration(milliseconds: 20),
      );
      addTearDown(outcome.stop);

      expect(outcome.isPrimary, isTrue);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(opened, <String>['/orders/42', '/open?path=%2Fhome%2Fada%2Freport.pdf']);
    });

    test('a later launch is secondary, hands over, and the primary opens it', () async {
      final List<String> opened = <String>[];
      final DVAppLaunchResult primary = await DVAppLaunch.start(
        appId: 'shop',
        arguments: const <String>[],
        lockPath: '${dir.path}/shop.lock',
        open: (String route) async => opened.add(route),
        poll: const Duration(milliseconds: 20),
      );
      addTearDown(primary.stop);

      final DVAppLaunchResult second = await DVAppLaunch.start(
        appId: 'shop',
        arguments: <String>['dartvel://orders/7'],
        lockPath: '${dir.path}/shop.lock',
        open: (String route) async => fail('a secondary opens nothing itself'),
      );
      expect(second.isPrimary, isFalse);
      expect(second.forwarded, <String>['/orders/7']);

      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(opened, <String>['/orders/7']);
    });

    test('stopped, the primary opens nothing more', () async {
      final List<String> opened = <String>[];
      final DVAppLaunchResult primary = await DVAppLaunch.start(
        appId: 'shop',
        arguments: const <String>[],
        lockPath: '${dir.path}/shop.lock',
        open: (String route) async => opened.add(route),
        poll: const Duration(milliseconds: 20),
      );
      primary.stop();
      final DVAppLaunchResult again = await DVAppLaunch.start(
        appId: 'shop',
        arguments: <String>['/orders/1'],
        lockPath: '${dir.path}/shop.lock',
        open: (String route) async => opened.add(route),
        poll: const Duration(milliseconds: 20),
      );
      addTearDown(again.stop);
      expect(again.isPrimary, isTrue, reason: 'the lock was released with the stop');
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(opened, <String>['/orders/1']);
    });

    test('a route written by another process is not trusted as one', () async {
      // The queue file is another process's word. A relative or scheme-ish
      // entry is dropped rather than opened.
      final List<String> opened = <String>[];
      final DVAppLaunchResult primary = await DVAppLaunch.start(
        appId: 'shop',
        arguments: const <String>[],
        lockPath: '${dir.path}/shop.lock',
        open: (String route) async => opened.add(route),
        poll: const Duration(milliseconds: 20),
      );
      addTearDown(primary.stop);
      File('${dir.path}/shop.lock.requests').writeAsStringSync('["orders/1", "//evil", "/fine"]');
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(opened, <String>['/fine']);
    });
  });
}

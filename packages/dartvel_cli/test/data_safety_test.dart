// The Play Data Safety answers, derived from what a project declares.
//
// The failure that matters is an answer nobody can defend. "Collected" means
// sent off the device, which a permission or a dependency does not show, so
// neither may turn into a confident row; and a row the Console cannot place
// (an identifier nobody confirmed) must be listed for a person rather than
// written into a file the Console imports without a word.
import 'package:dartvel_cli/src/store/data_safety.dart';
import 'package:test/test.dart';

DVDataSafetyReport reportFor(Map<String, Object?> dartvel,
        {Map<String, Object?> dependencies = const <String, Object?>{}}) =>
    dvDataSafetyFor(DVDataSafetyInputs.fromPubspec(<String, Object?>{
      'name': 'demo',
      'dependencies': dependencies,
      'dartvel': dartvel,
    }));

const String template = '''
Question ID (machine readable),Response (machine readable),Response value,Answer requirement,Human-friendly question label
PSL_DATA_TYPES_APP_PERFORMANCE,PSL_CRASH_LOGS_TEMPLATE,,MULTIPLE_CHOICE,App info and performance > Crash logs
PSL_DATA_TYPES_FINANCIAL,PSL_PURCHASE_TEMPLATE,,MULTIPLE_CHOICE,"Financial info > Purchase history"
''';

void main() {
  group('derived answers', () {
    test('a project that declares nothing derives nothing', () {
      final DVDataSafetyReport report = reportFor(<String, Object?>{});
      expect(report.collected, isEmpty);
    });

    test('crash reports sent to the backend are crash logs for analytics', () {
      final DVDataSafetyReport report = reportFor(<String, Object?>{
        'crashes': <String, Object?>{'sink': 'dartvel'},
      });
      final DVDataSafetyAnswer logs = report.collected.single;
      expect(logs.type, DVDataSafetyType.crashLogs);
      expect(logs.purposes, <DVDataSafetyPurpose>{DVDataSafetyPurpose.analytics});
      expect(logs.shared, isFalse);
      expect(logs.basis, contains('dartvel.crashes.sink'));
    });

    test('crash reporting that sends nowhere collects nothing', () {
      expect(
          reportFor(<String, Object?>{
            'crashes': <String, Object?>{'sink': 'none'}
          }).collected,
          isEmpty);
    });

    test('crash reporting switched off in release collects nothing', () {
      expect(
          reportFor(<String, Object?>{
            'crashes': <String, Object?>{
              'sink': 'dartvel',
              'disabledIn': <String>['release'],
            }
          }).collected,
          isEmpty);
    });

    test('analytics with a consent policy is optional app interaction data',
        () {
      final DVDataSafetyReport report = reportFor(<String, Object?>{
        'analytics': <String, Object?>{
          'consent': <String, Object?>{
            'version': 1,
            'categories': <Object?>[
              <String, Object?>{'name': 'usage', 'purpose': 'Product usage'},
            ],
          },
        },
      });
      final DVDataSafetyAnswer interactions = report.collected.single;
      expect(interactions.type, DVDataSafetyType.appInteractions);
      expect(interactions.userChoice, DVDataSafetyUserChoice.optional);
      expect(interactions.purposes, contains(DVDataSafetyPurpose.analytics));
    });

    test('purchases are purchase history the user cannot opt out of', () {
      final DVDataSafetyAnswer history = reportFor(<String, Object?>{
        'purchases': <String, Object?>{},
      }).collected.single;
      expect(history.type, DVDataSafetyType.purchaseHistory);
      expect(history.userChoice, DVDataSafetyUserChoice.required);
      expect(history.purposes, <DVDataSafetyPurpose>{
        DVDataSafetyPurpose.appFunctionality,
      });
    });

    test('auth is a user id for account management, and asks about the rest',
        () {
      final DVDataSafetyReport report =
          reportFor(<String, Object?>{'auth': <String, Object?>{}});
      expect(report.collected.single.type, DVDataSafetyType.userIds);
      expect(report.collected.single.purposes, contains(
          DVDataSafetyPurpose.accountManagement));
      expect(
          report.questions.map((DVDataSafetyQuestion q) => q.id),
          containsAll(<String>[
            'auth-identifiers',
            'account-creation-methods',
            'account-deletion',
          ]));
    });
  });

  group('what is not derived', () {
    test('a permission is access, not collection, so it becomes a question',
        () {
      final DVDataSafetyReport report = reportFor(<String, Object?>{
        'android': <String, Object?>{
          'permissions': <String>['camera', 'microphone', 'contacts'],
        },
      });
      expect(report.collected, isEmpty);
      final Iterable<String> ids =
          report.questions.map((DVDataSafetyQuestion q) => q.id);
      expect(ids, containsAll(<String>[
        'permission-camera',
        'permission-microphone',
        'permission-contacts',
      ]));
      final DVDataSafetyQuestion camera = report.questions
          .firstWhere((DVDataSafetyQuestion q) => q.id == 'permission-camera');
      expect(camera.text, contains('android.permission.CAMERA'));
    });

    test('location names whether the manifest asks for precise', () {
      final DVDataSafetyQuestion question = reportFor(<String, Object?>{
        'android': <String, Object?>{'permissions': <String>['location']},
      }).questions.firstWhere(
          (DVDataSafetyQuestion q) => q.id == 'permission-location');
      expect(question.text, contains('ACCESS_FINE_LOCATION'));
    });

    test('dartvel.fileStorage permissions are asked about too', () {
      final DVDataSafetyReport report = reportFor(<String, Object?>{
        'fileStorage': <String, Object?>{
          'access': <String>['photos'],
          'reason': 'Attach receipts.',
        },
      });
      expect(report.collected, isEmpty);
      expect(report.questions.map((DVDataSafetyQuestion q) => q.id),
          contains('permission-photos'));
    });

    test('a name Dartvel has no permission for is not guessed at', () {
      final DVDataSafetyReport report = reportFor(<String, Object?>{
        'android': <String, Object?>{'permissions': <String>['camrea']},
      });
      expect(report.questions.map((DVDataSafetyQuestion q) => q.id),
          contains('permission-unknown-camrea'));
    });

    test('a third-party SDK is named and left to its own disclosure', () {
      final DVDataSafetyReport report = reportFor(<String, Object?>{},
          dependencies: <String, Object?>{
            'firebase_messaging': '^15.0.0',
            'google_mobile_ads': '^5.0.0',
            'http': '^1.0.0',
          });
      final Iterable<String> ids =
          report.questions.map((DVDataSafetyQuestion q) => q.id);
      expect(ids, contains('sdk-firebase_messaging'));
      expect(ids, contains('sdk-google_mobile_ads'));
      expect(ids, isNot(contains('sdk-http')));
      expect(report.collected, isEmpty);
    });

    test('the questions only the developer can answer are always asked', () {
      final Iterable<String> ids = reportFor(<String, Object?>{})
          .questions
          .map((DVDataSafetyQuestion q) => q.id);
      expect(ids, containsAll(<String>[
        'collects-or-shares-any-data',
        'data-deletion',
        'ephemeral-processing',
        'sharing-with-third-parties',
        'app-code-network-calls',
      ]));
    });
  });

  group('encryption in transit', () {
    test('is derived when cleartext is refused', () {
      final DVDataSafetyReport report = reportFor(<String, Object?>{});
      expect(report.encryptedInTransit, isTrue);
    });

    test('is not claimed when a cleartext host is allowed', () {
      final DVDataSafetyReport report = reportFor(<String, Object?>{
        'android': <String, Object?>{
          'cleartextHosts': <String>['10.0.0.5'],
        },
      });
      expect(report.encryptedInTransit, isFalse);
      expect(report.questions.map((DVDataSafetyQuestion q) => q.id),
          contains('encryption-in-transit'));
    });
  });

  group('the CSV', () {
    final Map<String, Object?> everything = <String, Object?>{
      'crashes': <String, Object?>{'sink': 'dartvel'},
      'purchases': <String, Object?>{},
    };

    test('has the Console columns and no rows when no identifier is known', () {
      final String csv = reportFor(everything).toCsv();
      final List<String> lines = csv.trim().split('\n');
      expect(lines.single,
          'Question ID (machine readable),Response (machine readable),'
          'Response value,Answer requirement,Human-friendly question label');
    });

    test('leaves out a row whose identifier nobody confirmed, and says so', () {
      final DVDataSafetyReport report = reportFor(everything);
      expect(report.unplaced.map((DVDataSafetyAnswer a) => a.type),
          containsAll(<DVDataSafetyType>[
            DVDataSafetyType.crashLogs,
            DVDataSafetyType.purchaseHistory,
          ]));
    });

    test('takes identifiers from the Console\'s own exported template', () {
      final String csv = reportFor(everything).toCsv(template: template);
      expect(csv, contains('PSL_DATA_TYPES_APP_PERFORMANCE,PSL_CRASH_LOGS_TEMPLATE,TRUE,MULTIPLE_CHOICE'));
      expect(
          csv,
          contains('PSL_DATA_USAGE_RESPONSES:PSL_CRASH_LOGS_TEMPLATE:'
              'PSL_DATA_USAGE_COLLECTION_AND_SHARING,'
              'PSL_DATA_USAGE_ONLY_COLLECTED,TRUE,'));
      expect(
          csv,
          contains('PSL_DATA_USAGE_RESPONSES:PSL_CRASH_LOGS_TEMPLATE:'
              'DATA_USAGE_COLLECTION_PURPOSE,PSL_ANALYTICS,TRUE,'));
      expect(
          csv,
          contains('PSL_DATA_USAGE_RESPONSES:PSL_PURCHASE_TEMPLATE:'
              'DATA_USAGE_USER_CONTROL,PSL_DATA_USAGE_USER_CONTROL_REQUIRED,TRUE,'));
    });

    test('with a template, a type the template lacks stays unplaced', () {
      final DVDataSafetyReport report = reportFor(<String, Object?>{
        'auth': <String, Object?>{},
        'crashes': <String, Object?>{'sink': 'dartvel'},
      });
      final String csv = report.toCsv(template: template);
      expect(csv, isNot(contains('USER_ACCOUNT')));
      expect(report.unplacedWith(template).map((DVDataSafetyAnswer a) => a.type),
          <DVDataSafetyType>[DVDataSafetyType.userIds]);
    });

    test('identifiers from Google\'s help page need no template', () {
      // PSL_NAME and PSL_APPROX_LOCATION are the two the published table
      // names; nothing here derives either, so build the answer directly.
      final String csv = dvDataSafetyCsv(<DVDataSafetyAnswer>[
        const DVDataSafetyAnswer(
          type: DVDataSafetyType.name,
          purposes: <DVDataSafetyPurpose>{DVDataSafetyPurpose.accountManagement},
          shared: false,
          userChoice: DVDataSafetyUserChoice.required,
          basis: 'test',
        ),
      ]);
      expect(csv, contains('PSL_DATA_TYPES_PERSONAL,PSL_NAME,TRUE,MULTIPLE_CHOICE'));
      expect(csv, contains('PSL_DATA_USAGE_RESPONSES:PSL_NAME:DATA_USAGE_COLLECTION_PURPOSE,PSL_ACCOUNT_MANAGEMENT,TRUE'));
    });

    test('--unverified-ids uses the identifiers Google has not published', () {
      final String csv = reportFor(everything).toCsv(unverifiedIds: true);
      expect(csv, contains('PSL_DATA_TYPES_APP_PERFORMANCE,PSL_CRASH_LOGS,TRUE'));
      expect(csv, contains('PSL_DATA_TYPES_FINANCIAL,PSL_PURCHASE_HISTORY,TRUE'));
    });

    test('a field with a comma or a quote is quoted', () {
      final String csv = reportFor(everything).toCsv(template: template);
      expect(csv, contains('"'), reason: 'labels contain a comma');
      for (final String line in csv.trim().split('\n').skip(1)) {
        expect(line.split('"').length.isOdd, isTrue, reason: line);
      }
    });
  });

  group('the worksheet and JSON', () {
    test('every unanswered question and every derived row is written down', () {
      final DVDataSafetyReport report = reportFor(<String, Object?>{
        'purchases': <String, Object?>{},
      });
      final String sheet = report.toWorksheet();
      expect(sheet, contains('Purchase history'));
      expect(sheet, contains('TODO'));
      expect(sheet, contains('data-deletion'));
      expect(sheet, contains('dartvel.purchases'));
    });

    test('json carries the same facts', () {
      final Map<String, Object?> json = reportFor(<String, Object?>{
        'purchases': <String, Object?>{},
      }).toJson();
      expect((json['collected']! as List).single, containsPair('type', 'purchaseHistory'));
      expect((json['questions']! as List), isNotEmpty);
      expect(json['encryptedInTransit'], isTrue);
    });
  });
}

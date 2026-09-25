// dartvel.capture in pubspec.yaml: the only place an application says where
// its captured data models go.
//
// A declaration that cannot be honoured stops the build rather than being
// skipped into a server that delivers somewhere other than what the pubspec
// says -- or delivers nowhere, which looks exactly like a quiet day.
import 'package:dartvel_core/framework.dart';
import 'package:test/test.dart';

String _codeOf(Object? section) {
  try {
    DVCaptureConfig.parse(section);
  } on DVCaptureConfigError catch (error) {
    return error.code;
  }
  fail('$section was accepted');
}

void main() {
  test('absent is no capture configuration at all', () {
    expect(DVCaptureConfig.parse(null), isNull);
  });

  test('a full declaration reads back as written', () {
    final DVCaptureConfig config = DVCaptureConfig.parse(<String, Object?>{
      'retention': '7d',
      'destinations': <String, Object?>{
        'warehouse': <String, Object?>{
          'type': 'database',
          'connection': 'WAREHOUSE_URL',
          'models': <Object?>['Order', 'Refund'],
          'lagThreshold': '10m',
        },
      },
    })!;

    expect(config.retention, const Duration(days: 7));
    final DVCaptureDestination warehouse = config.destinations.single;
    expect(warehouse.name, 'warehouse');
    expect(warehouse.type, DVCaptureDestinationType.database);
    expect(warehouse.connection, 'WAREHOUSE_URL');
    expect(warehouse.models, <String>{'Order', 'Refund'});
    expect(warehouse.lagThreshold, const Duration(minutes: 10));
  });

  test('what is left out takes the documented defaults', () {
    final DVCaptureConfig config = DVCaptureConfig.parse(<String, Object?>{
      'destinations': <String, Object?>{
        'warehouse': <String, Object?>{
          'type': 'database',
          'connection': 'WAREHOUSE_URL',
        },
      },
    })!;

    expect(config.retention, const Duration(days: 7));
    expect(config.destinations.single.models, isNull,
        reason: 'no list is every captured data model');
    expect(config.destinations.single.lagThreshold, isNull);
  });

  test('round-trips through the form the generated server carries', () {
    final DVCaptureConfig config = DVCaptureConfig.parse(<String, Object?>{
      'retention': '30d',
      'destinations': <String, Object?>{
        'warehouse': <String, Object?>{
          'type': 'database',
          'connection': 'WAREHOUSE_URL',
          'models': <Object?>['Order'],
          'lagThreshold': '90s',
        },
      },
    })!;
    final DVCaptureConfig again = DVCaptureConfig.parse(config.toJson())!;

    expect(again.retention, config.retention);
    expect(again.destinations.single.connection, 'WAREHOUSE_URL');
    expect(again.destinations.single.models, <String>{'Order'});
    expect(again.destinations.single.lagThreshold,
        const Duration(seconds: 90));
  });

  group('DV-CDC-006: a declaration that cannot be honoured', () {
    test('an unknown key, where a misspelling would otherwise be ignored', () {
      expect(_codeOf(<String, Object?>{'retension': '7d'}), 'DV-CDC-006');
      expect(
        _codeOf(<String, Object?>{
          'destinations': <String, Object?>{
            'warehouse': <String, Object?>{
              'type': 'database',
              'connection': 'WAREHOUSE_URL',
              'lagTreshold': '10m',
            },
          },
        }),
        'DV-CDC-006',
      );
    });

    test('a destination type no adapter implements', () {
      expect(
        _codeOf(<String, Object?>{
          'destinations': <String, Object?>{
            'lake': <String, Object?>{
              'type': 'parquet',
              'connection': 'LAKE_URL',
            },
          },
        }),
        'DV-CDC-006',
      );
    });

    test('a retention or a threshold that is not a duration', () {
      expect(_codeOf(<String, Object?>{'retention': 'a week'}), 'DV-CDC-006');
      expect(_codeOf(<String, Object?>{'retention': '0d'}), 'DV-CDC-006');
      expect(
        _codeOf(<String, Object?>{
          'destinations': <String, Object?>{
            'warehouse': <String, Object?>{
              'type': 'database',
              'connection': 'WAREHOUSE_URL',
              'lagThreshold': 10,
            },
          },
        }),
        'DV-CDC-006',
      );
    });

    test('a destination with no type or no connection', () {
      expect(
        _codeOf(<String, Object?>{
          'destinations': <String, Object?>{
            'warehouse': <String, Object?>{'connection': 'WAREHOUSE_URL'},
          },
        }),
        'DV-CDC-006',
      );
      expect(
        _codeOf(<String, Object?>{
          'destinations': <String, Object?>{
            'warehouse': <String, Object?>{'type': 'database'},
          },
        }),
        'DV-CDC-006',
      );
    });

    test('a models entry that is not a list of data model names', () {
      expect(
        _codeOf(<String, Object?>{
          'destinations': <String, Object?>{
            'warehouse': <String, Object?>{
              'type': 'database',
              'connection': 'WAREHOUSE_URL',
              'models': 'Order',
            },
          },
        }),
        'DV-CDC-006',
      );
      expect(
        _codeOf(<String, Object?>{
          'destinations': <String, Object?>{
            'warehouse': <String, Object?>{
              'type': 'database',
              'connection': 'WAREHOUSE_URL',
              'models': <Object?>['orders table'],
            },
          },
        }),
        'DV-CDC-006',
      );
    });
  });

  group('DV-CDC-008: a destination takes only captured data models', () {
    final DVCaptureConfig config = DVCaptureConfig.parse(<String, Object?>{
      'destinations': <String, Object?>{
        'warehouse': <String, Object?>{
          'type': 'database',
          'connection': 'WAREHOUSE_URL',
          'models': <Object?>['Order', 'Invoice'],
        },
      },
    })!;

    test('a model that is not @DVModel(capture: true) is named', () {
      DVCaptureConfigError? error;
      try {
        config.checkModels(<String>{'Order', 'Customer'});
      } on DVCaptureConfigError catch (caught) {
        error = caught;
      }
      expect(error?.code, 'DV-CDC-008');
      expect('$error', contains('Invoice'));
      expect('$error', contains('warehouse'));
    });

    test('every model captured is accepted', () {
      config.checkModels(<String>{'Order', 'Invoice'});
    });
  });

  group('DV-CDC-007: a connection is named, never written down', () {
    test('a URL in the pubspec is refused, and is not repeated', () {
      DVCaptureConfigError? error;
      try {
        DVCaptureConfig.parse(<String, Object?>{
          'destinations': <String, Object?>{
            'warehouse': <String, Object?>{
              'type': 'database',
              'connection': 'postgres://etl:hunter2@db.internal/warehouse',
            },
          },
        });
      } on DVCaptureConfigError catch (caught) {
        error = caught;
      }
      expect(error?.code, 'DV-CDC-007');
      expect('$error', isNot(contains('hunter2')),
          reason: 'the refusal is printed, and a credential is not');
    });

    test('anything that is not the name of a secret is refused', () {
      expect(
        _codeOf(<String, Object?>{
          'destinations': <String, Object?>{
            'warehouse': <String, Object?>{
              'type': 'database',
              'connection': 'warehouse.db',
            },
          },
        }),
        'DV-CDC-007',
      );
    });
  });
}

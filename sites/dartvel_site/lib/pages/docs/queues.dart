import 'package:flutter/material.dart';

import '../../dartvel_client/dartvel_client.dart';

@DVPage(
  title: 'Dartvel queues and jobs: background work with retries',
  description: 'Send email, resize images and call slow APIs after the '
      'response, with retries. A job is a small class: dispatch it '
      'and a worker runs it.',
  showAppBar: false,
)
@pragma('vm:entry-point')
Widget _docsQueuesPage(BuildContext context) => const DocsArticle(
      page: DVRoutes.docsqueues,
      lead: <String>[
        'Send email, resize images and call slow APIs after the response, with '
            'retries.',
        'A job is a small class. Dispatch it and a worker runs it.',
      ],
      sections: <DocsSection>[
        DocsSection(
          id: 'declare',
          title: 'Declare a job and its handler',
          children: <Widget>[
            DocsCode('jobs-welcome'),
            Bullets(<String>[
              '@DVJob takes queue, priority, maxAttempts (3) and backoffSeconds '
                  '(30).',
              'Generation writes the public SendWelcomeEmail with dispatch().',
              'A handler that uses DV runs in the app only. Write it against '
                  'dartvel_core so a worker can run it.',
            ]),
          ],
        ),
        DocsSection(
          id: 'dispatch',
          title: 'Dispatch a job',
          children: <Widget>[
            DocsCode('jobs-dispatch'),
            DocsText('From a backend function, dispatch and return straight '
                'away.'),
            DocsCode('backend-background'),
          ],
        ),
        DocsSection(
          id: 'workers',
          title: 'Run workers',
          children: <Widget>[
            DocsText('Start the generated backend with these environment '
                'variables and it works jobs instead of serving HTTP.'),
            DocsShell(<String>[
              'DARTVEL_ROLE=worker',
              'DARTVEL_QUEUE=mail,default',
              'DATABASE_URL=postgres://app@db.internal/app',
            ]),
            Bullets(<String>[
              'A worker needs DATABASE_URL and at least one handler, or it '
                  'refuses to start.',
              'A failed job goes back on its queue until maxAttempts, then to '
                  'dead letters. Only the SQS and Pub/Sub adapters wait out the '
                  'backoff first.',
              'DARTVEL_HEALTH_PORT serves /healthz for a worker.',
            ]),
            DocsSubheading('Work a queue by hand'),
            DocsShell(<String>[
              'dartvel queue work --queue mail --max-jobs 10',
            ]),
            DocsText('This runs your project\'s worker, so DATABASE_URL must be '
                'set in your shell. The failed, retry and flush subcommands '
                'still read the CLI\'s own empty queue, so use the calls below '
                'for those.'),
            DocsCode('jobs-work'),
          ],
        ),
        DocsSection(
          id: 'adapters',
          title: 'Choose a queue adapter',
          children: <Widget>[
            DocsCode('jobs-adapter'),
            DocsTable(columns: <String>[
              'Adapter',
              'Stores jobs in',
            ], rows: <List<String>>[
              <String>['DVInMemoryQueueAdapter', 'Memory, for tests'],
              <String>['DVDatabaseQueueAdapter', 'Your database, table '
                  'dartvel_jobs'],
              <String>['DVRedisQueueAdapter', 'Redis'],
              <String>['DVSqsQueueAdapter', 'Amazon SQS'],
              <String>['DVAmqpQueueAdapter', 'RabbitMQ and other AMQP brokers'],
              <String>['DVPubSubQueueAdapter', 'Google Pub/Sub'],
              <String>['DVKafkaQueueAdapter', 'Kafka'],
            ]),
            DocsText('Only the database adapter is picked from DATABASE_URL. '
                'Set any other with DV.Jobs.useAdapter. The SQS and Pub/Sub '
                'adapters take a transport you write, and refuse job priorities.'),
          ],
        ),
        DocsSection(
          id: 'tenants',
          title: 'Jobs keep their tenant',
          children: <Widget>[
            DocsText('dispatch() records the current tenant. The worker runs '
                'the handler inside that tenant, so tenant-scoped models and '
                'cache keys behave as they did for the request.'),
          ],
        ),
        DocsSection(
          id: 'schedules',
          title: 'Schedule work with cron',
          children: <Widget>[
            DocsCode('jobs-cron'),
            Bullets(<String>[
              'catchUp: true runs a missed occurrence after a restart.',
              'Schedules tick in a process with no role or DARTVEL_ROLE=cron.',
              'With DATABASE_URL set, each occurrence is claimed in the '
                  'database, so two cron processes do not both run it. Without '
                  'one, a cron process refuses to start unless '
                  'DARTVEL_SCHEDULE_LEASE=none says it is the only one.',
            ]),
            DocsStatus('Scheduling', missing: <String>[
              'No per-target capability report or doctor check for schedules.',
            ]),
          ],
        ),
        DocsSection(
          id: 'status',
          title: 'Status',
          children: <Widget>[
            DocsStatus('Queues, Jobs, and Signals', missing: <String>[
              'Delayed jobs, exponential backoff, unique jobs and pausing a '
                  'queue are not built.',
              'The queue failed, retry and flush commands act on the CLI\'s own '
                  'process queue.',
            ]),
          ],
        ),
      ],
    );

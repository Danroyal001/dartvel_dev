import '../dartvel_client/dartvel_client.dart';

// docs:start ai-configure
void configureAI() {
  DV.AI.configure(AnthropicDVAIAdapter(
    apiKey: DV.Secrets.get('ANTHROPIC_API_KEY'),
  ));
}
// docs:end

Future<void> askAI(String ticket) async {
  // docs:start ai-chat
  final String summary = await DV.AI.chat('Summarise this ticket: $ticket');

  final DVJsonObject triage = await DV.AI.structuredOutput(
    'Triage this ticket: $ticket',
    const <String, DVJsonValue>{
      'type': DVJsonString('object'),
      'properties': DVJsonMap(<String, DVJsonValue>{
        'urgent': DVJsonMap(<String, DVJsonValue>{'type': DVJsonString('boolean')}),
      }),
    },
  );

  final List<double> vector = await DV.AI.embed(ticket);
  // docs:end
  DV.log('$summary $triage ${vector.length}');
}

Future<String?> summariseWithBudget(String body, String ticketId) async {
  // docs:start ai-feature
  final DVPrompts prompts = DVPrompts()
    ..register(
      const DVPrompt(id: 'ticket.summary', version: 4),
      const DVPromptTemplate(
        system: 'Summarise the ticket for a support agent.',
        input: <String, Type>{'body': String},
      ),
    );

  final DVAIFeatures features = DVAIFeatures(
    prompts: prompts,
    adapter: const LocalDVAIAdapter(),
    model: 'local',
  )..register(const DVAIFeature(
      prompt: 'ticket.summary',
      fallback: <DVAIFallback>[DVAIFallback.degrade],
    ));

  final DVAIFeatureResult result = await features.run(
    'ticket.summary',
    input: <String, Object?>{'body': body},
    idempotencyKey: 'summary:$ticketId',
  );
  final String? summary = switch (result) {
    DVAIAnswered(output: DVJsonString(:final String value)) => value,
    _ => null, // degraded, refused by a budget, or the provider was down
  };
  // docs:end
  return summary;
}

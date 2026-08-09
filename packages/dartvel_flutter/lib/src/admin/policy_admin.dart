import 'package:flutter/widgets.dart';

import '../../dartvel_flutter.dart';

/// The policy and permission explorer, and the model sync channel inspector.
///
/// Both answer the same shape of question: a policy that was never registered
/// denies exactly like one that considered the request and said no, and a
/// model with no sync channel is silent exactly like one whose updates simply
/// have not arrived. Listing what is registered is what tells those apart.
class DVPolicyAdmin extends StatefulWidget {
  const DVPolicyAdmin({super.key});

  @override
  State<DVPolicyAdmin> createState() => _DVPolicyAdminState();
}

class _DVPolicyAdminState extends State<DVPolicyAdmin> {
  void _refresh() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final policies = const DVAuthAuthorization().registeredPolicies.toList()
      ..sort();
    final synced = DVModelSync.syncedTypes
        .map((Type type) => type.toString())
        .toList()
      ..sort();
    final decodable = DVModelSync.decodableNames.toList()..sort();

    return DVBox.scrollableList(<Widget>[
      const DVText('Policies and Sync')
          .modifier(const DVModifier().fontSize(24).fontWeight(FontWeight.bold)),
      GestureDetector(
        key: const ValueKey<String>('dv-policy-refresh'),
        onTap: _refresh,
        child: const DVText('Refresh'),
      ),
      DVBox.list(<Widget>[
        DVText('Policies (${policies.length})').modifier(
            const DVModifier().fontSize(18).fontWeight(FontWeight.bold)),
        // An unregistered policy denies silently, so an empty list is the
        // explanation for an app where everything is forbidden.
        if (policies.isEmpty)
          const DVText('No policies registered — every check denies.'),
        for (final policy in policies) DVText(policy),
      ]).modifier(const DVModifier().card().padding(16)),
      DVBox.list(<Widget>[
        DVText('Model sync channels (${synced.length})').modifier(
            const DVModifier().fontSize(18).fontWeight(FontWeight.bold)),
        if (synced.isEmpty) const DVText('No model has an open channel.'),
        for (final type in synced) DVText(type),
        DVText('Decodable wire names (${decodable.length})'),
        // A channel without a codec receives nothing: the envelope arrives and
        // cannot be turned back into a model.
        if (decodable.isEmpty)
          const DVText('No codec registered — incoming envelopes are dropped.'),
        for (final name in decodable) DVText(name),
      ]).modifier(const DVModifier().card().padding(16)),
    ]);
  }
}

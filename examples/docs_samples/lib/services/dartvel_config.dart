// docs:start file-associations-config
// dartvel_config.dart, named by `dartvel: dartvel_config.dart` in pubspec.yaml.
// Exactly the same object as the YAML: same keys, defaults and validation.
import 'package:dartvel_core/config.dart';

class const ShopConfig() extends DartvelConfig {
  @override
  List<DVFileAssociation> get fileAssociations => const <DVFileAssociation>[
        DVFileAssociation(
          mimeType: 'application/x-shop-order',
          extensions: <String>['order'],
          description: 'Shop order',
        ),
        DVFileAssociation(mimeType: 'application/pdf', role: .viewer),
      ];
}
// docs:end

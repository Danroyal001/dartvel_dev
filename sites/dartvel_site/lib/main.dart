import 'components/app_root.dart';
import 'dartvel_client/dartvel_client.dart';

// TODO(dartvel): `void main(List<String> args) => DV.run(args);` with the
// root in an @DVAppRoot, once Application Entry is built (it is Designed in
// docs/spec-status.json). DV.run(Widget) is the entry that exists today.
void main() => DV.run(createDartvelApp());

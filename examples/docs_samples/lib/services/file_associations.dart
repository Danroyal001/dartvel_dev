import '../dartvel_client/dartvel_client.dart';

// docs:start file-associations-opened
// Every target delivers the same way: launched with a file, opened with one
// while running, or shared to the app.
void openOrders() {
  DV.Platform.associations.opened.listen((DVOpenedFile file) async {
    if (file.extension != 'order') return;
    final List<int> bytes = await file.read();
    DV.log('Opening ${file.name}, ${bytes.length} bytes');
  });
}

// Where nothing can open the app with a file -- a browser tab, webOS, a
// terminal build -- the picker feeds the same handler.
Future<void> openFromPicker() async {
  if (!DV.Platform.associations.canPick) return;
  await DV.Platform.associations.pick(
    types: const <DVFileType>[
      DVFileType(mimeType: 'application/x-shop-order', extensions: <String>['order']),
    ],
  );
}
// docs:end

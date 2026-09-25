// The coffees someone wants to remember.
import '../dartvel_client/dartvel_client.dart';

class const SavedCoffees([final Set<String> slugs = const <String>{}]) {
  bool contains(String slug) => slugs.contains(slug);

  SavedCoffees toggle(String slug) => SavedCoffees(
    contains(slug)
        ? (Set<String>.of(slugs)..remove(slug))
        : (Set<String>.of(slugs)..add(slug)),
  );
}

void toggleSaved(String slug) {
  DV.global<SavedCoffees>(DV.global<SavedCoffees>().toggle(slug));
}

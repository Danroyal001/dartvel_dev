// The coffees someone wants to remember.
import '../dartvel_client/dartvel_client.dart';

class SavedCoffees {
  const SavedCoffees([this.slugs = const <String>{}]);

  final Set<String> slugs;

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

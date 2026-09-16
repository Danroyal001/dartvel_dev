import 'package:flutter/widgets.dart';

import '../dartvel_client/dartvel_client.dart';

// docs:start models-page-from-id
@DVPage(title: 'Article')
Widget _articlePage(BuildContext context) => Article.Page.fromId(
      context.dvParams['slug'] ?? 'hello-world',
      findById: (String slug) async => (await Article.find(slug))!,
    );
// docs:end

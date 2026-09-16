// docs:start routing-params
// lib/pages/blog/[id].dart is served at /blog/:id.
import 'package:flutter/widgets.dart';

import '../../dartvel_client/dartvel_client.dart';

@DVPage(title: 'Blog post')
Widget _blogPostPage(BuildContext context) => DVBox.list(<Widget>[
      DVText('Post ${context.dvParams['id']}'),
      DVText('Sorted by ${context.dvQuery['sort'] ?? 'date'}'),
    ]);
// docs:end

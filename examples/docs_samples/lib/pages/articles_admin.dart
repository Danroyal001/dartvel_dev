import 'package:flutter/widgets.dart';

import '../dartvel_client/dartvel_client.dart';

// docs:start models-admin-page
@DVPage(title: 'Articles admin', policy: DVPolicies.viewAdmin)
Widget _articlesAdminPage(BuildContext context) => Article.Admin();
// docs:end

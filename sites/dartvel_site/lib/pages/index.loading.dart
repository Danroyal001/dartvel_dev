import 'package:flutter/material.dart';

import '../dartvel_client/dartvel_client.dart';

/// What the home page shows while its data loads.
@DVFunctionalWidget()
Widget _indexPageLoading(BuildContext context) => const DVBox(
      DVText('Loading...'),
    );

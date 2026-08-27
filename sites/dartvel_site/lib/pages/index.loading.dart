import 'package:flutter/material.dart';
import '../dartvel_client/dartvel_client.dart';

class IndexPageLoading extends StatelessWidget {
  const IndexPageLoading({super.key});

  @override
  Widget build(BuildContext context) {
    return const DVBox(
      DVText('Loading...'),
    );
  }
}

import 'package:basic_app/dartvel_client/dartvel_client.dart';
import 'package:flutter/material.dart';

class IndexPageLoading extends StatelessWidget {
  const IndexPageLoading({super.key});

  @override
  Widget build(BuildContext context) {
    return const DVBox(CircularProgressIndicator());
  }
}

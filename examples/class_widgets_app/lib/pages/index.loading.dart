import 'package:flutter/material.dart';

class IndexPageLoading extends StatelessWidget {
  const IndexPageLoading({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Loading...')),
      body: const Center(
        child: CircularProgressIndicator(),
      ),
    );
  }
}

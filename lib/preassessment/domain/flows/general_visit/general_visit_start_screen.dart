import 'package:flutter/material.dart';

class GeneralVisitStartScreen extends StatelessWidget {
  const GeneralVisitStartScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('General Visit')),
      body: const Padding(
        padding: EdgeInsets.all(24),
        child: Text(
          'TODO: Replace this with the first screen of generalVisit.v1 flow.\n\n'
          'Next: your generalVisit questions start here.',
        ),
      ),
    );
  }
}

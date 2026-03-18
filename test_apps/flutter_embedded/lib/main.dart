import 'package:flutter/material.dart';

/// Minimal host app required by the Flutter integration_test runner.
void main() => runApp(const _App());

class _App extends StatelessWidget {
  const _App();

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      home: Scaffold(
        body: Center(
          child: Text('knex-dart embedded driver integration tests'),
        ),
      ),
    );
  }
}

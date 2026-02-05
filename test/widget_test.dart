import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kineticdx_app_v3/app/app.dart';

void main() {
  testWidgets('App builds and shows MaterialApp', (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());

    expect(find.byType(MaterialApp), findsOneWidget);
  });
}

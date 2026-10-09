import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:motolock_analytics/main.dart';

void main() {
  testWidgets('shows trend metrics and section comparison', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MyApp());

    expect(find.text('Starting Value'), findsOneWidget);
    expect(find.text('Current Value'), findsOneWidget);
    expect(find.text('Percentage Change'), findsOneWidget);
    expect(find.text('Trend'), findsOneWidget);
    expect(find.text('Performance Trend'), findsOneWidget);
    expect(find.text('Student Records'), findsOneWidget);
    expect(find.text('Performance Summary'), findsOneWidget);
    expect(find.text('Needs Attention'), findsWidgets);
    expect(find.textContaining('Performance: Good'), findsNWidgets(3));
    expect(find.byKey(const ValueKey('performance-summary')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('performance-count-Good')),
      findsOneWidget,
    );
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('performance-count-Good')))
          .data,
      '3',
    );
    expect(find.text('SECTION COMPARISON'), findsOneWidget);
    expect(find.text('Difference'), findsOneWidget);
    expect(find.text('4.00'), findsOneWidget);
    expect(find.text('Higher Average'), findsOneWidget);
    expect(find.text('Section A'), findsNWidgets(2));
  });
}

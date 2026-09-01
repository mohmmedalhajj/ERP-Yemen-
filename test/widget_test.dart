import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integratederp/shared/widgets/app_scaffold.dart';

void main() {
  testWidgets('تعرض حالة الفراغ رسالة عربية واضحة', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: EmptyState(message: 'لا توجد بيانات للعرض')),
      ),
    );

    expect(find.text('لا توجد بيانات للعرض'), findsOneWidget);
    expect(find.byIcon(Icons.inbox_outlined), findsOneWidget);
  });
}

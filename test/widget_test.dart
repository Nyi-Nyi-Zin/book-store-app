import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_book_app/main.dart';

void main() {
  testWidgets('Book app renders the Myanmar home experience', (tester) async {
    await tester.pumpWidget(const BookApp());
    await tester.pumpAndSettle();

    expect(find.text('စာအုပ်တိုက်'), findsOneWidget);
    expect(find.text('ညသန်းခေါင်က မြစ်'), findsOneWidget);
    expect(find.text('စာအုပ်များကြည့်ရန်'), findsOneWidget);
  });

  testWidgets('Book app can switch to English', (tester) async {
    await tester.pumpWidget(const BookApp());
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.translate));
    await tester.pumpAndSettle();

    expect(find.text('Book House'), findsOneWidget);
    expect(find.text('Find your next chapter'), findsOneWidget);
  });
}

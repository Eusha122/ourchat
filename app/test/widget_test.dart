import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ourchat/app.dart';

void main() {
  testWidgets('App launches on the Chats tab', (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: OurChatApp()));
    await tester.pumpAndSettle();

    expect(find.text('Chats'), findsWidgets);
    expect(find.text('Chat list will appear here (Phase 5)'), findsOneWidget);
  });

  testWidgets('Bottom nav switches to the Feed tab', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const ProviderScope(child: OurChatApp()));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(NavigationDestination, 'Feed'));
    await tester.pumpAndSettle();

    expect(find.text('Post feed will appear here (Phase 3)'), findsOneWidget);
  });
}

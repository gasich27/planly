import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ai_planner_mobile/main.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  testWidgets('PLANLY opens the Today shell', (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());
    await tester.pump();

    expect(find.text('Today'), findsWidgets);
    expect(find.text('Goals'), findsOneWidget);
    expect(find.text('Profile'), findsOneWidget);
    expect(find.text('add plan'), findsOneWidget);
    expect(find.text('edit plan'), findsOneWidget);
    expect(find.text('Tomorrow'), findsOneWidget);
    expect(find.text('Week'), findsOneWidget);
    expect(find.text('Month'), findsOneWidget);

    final groupRect = tester.getRect(find.byKey(const Key('base_stories_group')));
    expect(groupRect.left, 28);
    expect(groupRect.right, tester.view.physicalSize.width / tester.view.devicePixelRatio - 28);
  });

  testWidgets('a custom story branch is saved and revealed',
      (WidgetTester tester) async {
    await tester.pumpWidget(const MyApp());
    await tester.pump(const Duration(seconds: 1));

    await tester.tap(find.byKey(const Key('create_story_branch')));
    await tester.pump(const Duration(seconds: 1));

    final nameField = find.byWidgetPredicate(
      (widget) =>
          widget is TextField &&
          widget.decoration?.labelText == 'Name, for example Berlin',
    );
    expect(nameField, findsOneWidget);
    await tester.enterText(nameField, '29.12-31.12');
    expect(
      tester.widget<TextField>(nameField).controller?.text,
      '29.12-31.12',
    );
    tester.testTextInput.hide();
    await tester.pump(const Duration(milliseconds: 300));

    final addButton = find.byKey(
      const ValueKey<String>('editor_action_Add story branch'),
    );
    await tester.scrollUntilVisible(
      addButton,
      420,
      scrollable: find
          .descendant(
            of: find.byType(SingleChildScrollView).last,
            matching: find.byType(Scrollable),
          )
          .first,
    );
    tester.widget<GestureDetector>(addButton).onTap!();
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(addButton, findsNothing);
    expect(find.text('29.12-31.12'), findsOneWidget);
  });
}

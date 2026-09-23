import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:splitwise_clone/main.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Pumps frames while letting real (database) futures complete.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.runAsync(
      () => Future.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfiNoIsolate;

  testWidgets('create group, add expense, see who owes who', (tester) async {
    await tester.runAsync(
      () async => databaseFactory.deleteDatabase(
        '${await databaseFactory.getDatabasesPath()}/splitwise_offline.db',
      ),
    );
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.5;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const SplitApp());
    await settle(tester);
    expect(find.text('No groups yet'), findsOneWidget);

    await tester.tap(find.text('New group'));
    await settle(tester);
    await tester.enterText(
      find.widgetWithText(TextField, 'Group name'),
      'Trip',
    );
    for (final name in ['Alice', 'Bob', 'Carol']) {
      await tester.enterText(
        find.widgetWithText(TextField, 'Type a name'),
        name,
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
    }
    await tester.tap(find.text('Save'));
    await settle(tester);

    // Now inside the group screen.
    expect(find.text('Everyone is settled up'), findsOneWidget);
    await tester.tap(find.text('Add expense'));
    await settle(tester);
    await tester.enterText(
      find.widgetWithText(TextField, 'Description'),
      'Dinner',
    );
    await tester.enterText(find.widgetWithText(TextField, 'Amount'), '90');
    await tester.pump();
    expect(find.textContaining('\$30.00/person'), findsOneWidget);

    // Exact split mode renders and validates.
    await tester.tap(find.text('Exact amounts'));
    await tester.pump();
    expect(find.textContaining('left of'), findsOneWidget);
    await tester.tap(find.text('Equally'));
    await tester.pump();

    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await settle(tester);

    expect(find.text('Who owes who'), findsOneWidget);
    expect(find.text('Simplified to 2 payments'), findsOneWidget);
    expect(find.text('gets back \$60.00'), findsOneWidget);
    expect(find.text('owes \$30.00'), findsNWidgets(2));

    // Settle one suggested payment.
    await tester.tap(find.text('Settle').first);
    await settle(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await settle(tester);
    expect(find.text('Simplified to 1 payment'), findsOneWidget);

    await tester.tap(find.text('Expenses'));
    await settle(tester);
    expect(find.text('Dinner'), findsOneWidget);
    await tester.tap(find.text('Members'));
    await settle(tester);
    expect(find.text('Add member'), findsOneWidget);

    await tester.pageBack();
    await settle(tester);
    expect(find.text('Trip'), findsOneWidget);
    expect(find.text('unsettled'), findsOneWidget);
  });
}

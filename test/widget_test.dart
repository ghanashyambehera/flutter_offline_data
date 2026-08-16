import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_offline_data/app.dart';

void main() {
  testWidgets('App loads user list screen', (tester) async {
    await tester.pumpWidget(const OfflineSyncApp());
    await tester.pumpAndSettle();

    expect(find.text('Users'), findsOneWidget);
    expect(find.text('No users yet. Tap + to create one.'), findsOneWidget);
  });
}

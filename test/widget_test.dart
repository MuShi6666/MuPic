// Basic smoke test for the MuPic entry screen.

import 'package:flutter_test/flutter_test.dart';

import 'package:mupic/main.dart';

void main() {
  testWidgets('Browser screen shows the pick-image entry', (WidgetTester tester) async {
    await tester.pumpWidget(const MuPicApp());

    expect(find.text('MuPic'), findsOneWidget);
    expect(find.text('选择图片'), findsOneWidget);
  });
}

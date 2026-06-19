import 'package:flutter_test/flutter_test.dart';

import 'package:face_attendance/main.dart';

void main() {
  testWidgets('App starts on the splash screen', (WidgetTester tester) async {
    await tester.pumpWidget(const FaceAttendanceApp());

    expect(find.text('ektaHr'), findsOneWidget);
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:black_pin/main.dart'; 

void main() {
  testWidgets('App loads smoke test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const BlackPinApp());

    // Verify that the title 'BlackPin' exists on the screen.
    expect(find.textContaining('BlackPin'), findsWidgets);
  });
}
import 'package:flutter_test/flutter_test.dart';
import 'package:charlie_kiosk/main.dart';

void main() {
  testWidgets('Kiosk app launches', (WidgetTester tester) async {
    await tester.pumpWidget(const CharlieKiosk());
    expect(find.text('Charlie Kiosk'), findsOneWidget);
  });
}

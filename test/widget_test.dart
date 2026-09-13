import 'package:flutter_test/flutter_test.dart';
import 'package:tensorsight/main.dart';

void main() {
  testWidgets('TensorSightApp boots and renders SplashScreen', (WidgetTester tester) async {
    await tester.pumpWidget(const TensorSightApp());
    expect(find.text('TensorSight'), findsOneWidget);
    expect(find.text('Edge AI Computer Vision'), findsOneWidget);
  });
}

import 'package:builder/main.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Builder opens its initial screen', (tester) async {
    await tester.pumpWidget(const BuilderApp());

    expect(find.text('Builder'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

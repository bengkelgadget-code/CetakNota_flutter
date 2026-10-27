import 'package:flutter_test/flutter_test.dart';
import 'package:scanner_nota_flutter/main.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const ScannerNotaApp());
    expect(find.text('SCANNER NOTA'), findsOneWidget);
  });
}

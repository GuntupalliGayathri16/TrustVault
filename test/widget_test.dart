
import 'package:flutter_test/flutter_test.dart';
import 'package:trustvault/main.dart';

void main() {
  testWidgets('TrustVault dashboard loads', (tester) async {
    await tester.pumpWidget(const TrustVaultApp());

    expect(find.text('TrustVault'), findsOneWidget);
    expect(find.text('Welcome to TrustVault'), findsOneWidget);
    expect(find.text('Recent Documents'), findsOneWidget);
  });
}

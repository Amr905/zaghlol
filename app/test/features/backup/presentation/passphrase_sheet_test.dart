import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zaghlol/core/ui/z_components.dart';
import 'package:zaghlol/features/backup/presentation/passphrase_sheet.dart';

import 'backup_fakes.dart';

void main() {
  test('strength: length and variety', () {
    expect(passphraseStrength('short'), PassphraseStrength.weak);
    expect(passphraseStrength('abcdefghij'), PassphraseStrength.fair);
    expect(passphraseStrength('Abcdef12345!'), PassphraseStrength.strong);
    expect(passphraseStrength('a' * 16), PassphraseStrength.strong);
  });

  for (final lang in ['ar', 'en']) {
    testWidgets('setup needs 10 chars, match and the tick ($lang)', (t) async {
      await t.binding.setSurfaceSize(const Size(360, 800));
      addTearDown(() => t.binding.setSurfaceSize(null));
      PassphraseResult? result;
      await t.pumpWidget(
        ProviderScope(
          overrides: baseOverrides(lang: lang),
          child: host(
            Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () async => result = await showPassphraseSheet(
                    context,
                    mode: PassphraseMode.setup,
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
            lang: lang,
            scale: 1.3,
          ),
        ),
      );
      await t.tap(find.text('open'));
      await t.pumpAndSettle();
      final fields = find.byType(TextField);
      expect(fields, findsNWidgets(2));
      await t.enterText(fields.at(0), 'short');
      await t.enterText(fields.at(1), 'other');
      final save = find.byType(ZButton).last;
      await t.ensureVisible(save);
      await t.tap(save);
      await t.pumpAndSettle();
      expect(result, isNull);
      expect(find.byType(Checkbox), findsOneWidget);
      await t.enterText(fields.at(0), 'abcdefghijkl');
      await t.enterText(fields.at(1), 'abcdefghijkl');
      await t.ensureVisible(find.byType(Checkbox));
      await t.tap(find.byType(Checkbox));
      await t.pumpAndSettle();
      await t.ensureVisible(save);
      await t.tap(save);
      await t.pumpAndSettle();
      expect(result?.passphrase, 'abcdefghijkl');
      expect(t.takeException(), isNull);
    });
  }
}

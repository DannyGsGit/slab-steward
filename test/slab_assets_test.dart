import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:slab_steward/src/model/difficulty.dart';

/// The signage chips and the brand mark are SLAB's own artwork, copied into
/// `assets/slab` from the sister app's handoff folder. A rating whose chip
/// isn't bundled draws nothing at all — no exception, no fallback glyph, just
/// a hole where the difficulty was — so it's worth failing here instead.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('every difficulty has its chip bundled', () async {
    for (final difficulty in Difficulty.values) {
      final bytes = await rootBundle.load(difficulty.assetPath);
      expect(
        bytes.lengthInBytes,
        greaterThan(0),
        reason: '${difficulty.label} has an empty ${difficulty.assetPath}',
      );
    }
  });

  test('the brand mark is bundled', () async {
    final bytes = await rootBundle.load('assets/slab/logo.png');
    expect(bytes.lengthInBytes, greaterThan(0));
  });
}

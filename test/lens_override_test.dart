import 'package:flutter_test/flutter_test.dart';
import 'package:slab_steward/src/map/otm_conventions.dart';
import 'package:slab_steward/src/map/steward_style.dart';
import 'package:slab_steward/src/model/lens.dart';

/// Evaluates the subset of MapLibre's expression language Steward's filters
/// use, so the style document can be checked without a browser.
///
/// The point isn't to reimplement MapLibre — it's that [TagSource.overriding]
/// rewrites filters that are otherwise only ever exercised at runtime, and a
/// substitution that silently misreads a deleted tag would show up as nothing
/// worse than a trail that stays the wrong colour.
Object? evaluate(Object? expr, Map<String, Object?> props) {
  if (expr is! List || expr.isEmpty) return expr;
  final args = expr.skip(1).toList();
  Object? arg(int i) => evaluate(args[i], props);

  switch (expr.first) {
    case 'literal':
      return args[0];
    case 'get':
      return props[args[0] as String];
    case 'has':
      return props.containsKey(args[0] as String);
    case 'to-string':
      final value = arg(0);
      return value == null ? '' : '$value';
    case 'all':
      return args.every((a) => evaluate(a, props) == true);
    case 'any':
      return args.any((a) => evaluate(a, props) == true);
    case '!':
      return arg(0) != true;
    case '==':
      return arg(0) == arg(1);
    case '!=':
      return arg(0) != arg(1);
    case 'in':
      final haystack = arg(1);
      return haystack is List && haystack.contains(arg(0));
    case 'match':
      final input = arg(0);
      for (var i = 1; i < args.length - 1; i += 2) {
        final labels = args[i];
        final matched = labels is List
            ? labels.contains(input)
            : labels == input;
        if (matched) return evaluate(args[i + 1], props);
      }
      return evaluate(args.last, props);
    case 'case':
      for (var i = 0; i < args.length - 1; i += 2) {
        if (evaluate(args[i], props) == true) {
          return evaluate(args[i + 1], props);
        }
      }
      return evaluate(args.last, props);
    default:
      fail(
        'The evaluator does not know "${expr.first}" — teach it, or the '
        'filter under test is not being checked at all.',
      );
  }
}

/// A style document with just enough shape for [buildStewardStyle].
Map<String, Object?> baseStyle() => {
  'version': 8,
  'sources': <String, Object?>{},
  // Typed the way a decoded style document is, so `layers` accepts the
  // overlay MapLibre would have spliced in.
  'layers': <Object?>[
    <String, Object?>{'id': 'qa_insertion_point', 'type': 'background'},
  ],
};

/// Which of the overlay's trail-line layers would draw [props].
Set<String> layersDrawing(
  Map<String, Object?> props, {
  required TravelMode mode,
  required Set<Lens> lenses,
  TagSource tags = const TagSource.tiles(),
}) {
  const lineLayers = {
    'paths',
    'informal-paths',
    'unspecified-paths',
    'unspecified-informal-paths',
    'disallowed-paths',
    'disallowed-informal-paths',
  };
  final style = buildStewardStyle(
    baseStyle(),
    mode: mode,
    lenses: lenses,
    tags: tags,
  );
  final layers = (style['layers'] as List).cast<Map<String, Object?>>();
  return {
    for (final layer in layers)
      if (lineLayers.contains(layer['id']) &&
          evaluate(layer['filter'], props) == true)
        layer['id'] as String,
  };
}

/// A deterministic spread over every tag the overlay's filters read.
Iterable<Map<String, Object?>> featureSpread() sync* {
  const highways = [null, 'path', 'footway', 'steps', 'service', 'residential'];
  const accesses = [null, 'yes', 'no', 'private', 'limited'];
  const modes = [null, 'yes', 'no', 'designated', 'unknown'];
  const ratings = [null, '2', 'unknown'];
  for (final highway in highways) {
    for (final access in accesses) {
      for (final mtb in modes) {
        for (final bicycle in modes) {
          for (final rating in ratings) {
            for (final informal in [null, 'yes', 'no']) {
              yield {
                'OSM_ID': 55,
                'highway': ?highway,
                'access': ?access,
                'mtb': ?mtb,
                'bicycle': ?bicycle,
                'mtb:scale:imba': ?rating,
                'informal': ?informal,
              };
            }
          }
        }
      }
    }
  }
}

void main() {
  test('the overlay covers exactly what its line layers draw', () {
    // buildStewardStyle hands its labels, hit targets, bridge casings and
    // no-entry symbols a single "everything we draw" filter, spelled as the
    // highway test rather than as the union of the six line layers it stands
    // for. That shortcut is worth ~75% of the style document once overrides
    // are substituted in — and it is only sound while the six really do
    // partition the trails. If a seventh layer arrives with a narrower
    // filter, this is what notices.
    const lineLayers = {
      'paths',
      'informal-paths',
      'unspecified-paths',
      'unspecified-informal-paths',
      'disallowed-paths',
      'disallowed-informal-paths',
    };
    final overriding = TagSource.overriding(const {
      55: {'highway': 'path', 'mtb': 'no', 'surface': 'dirt'},
    });

    // Not the whole powerset — the coverage argument turns on how many tests
    // the selection contributes (none, one, several) and whether one of them
    // is the access question, so these six stand for all sixteen.
    const selections = <Set<Lens>>[
      {},
      {Lens.access},
      {Lens.difficulty},
      {Lens.difficulty, Lens.surface, Lens.electricBicycle},
      {Lens.access, Lens.difficulty},
      {Lens.access, Lens.difficulty, Lens.surface, Lens.electricBicycle},
    ];

    for (final mode in TravelMode.values) {
      for (final lenses in selections) {
        for (final tags in [const TagSource.tiles(), overriding]) {
          final style = buildStewardStyle(
            baseStyle(),
            mode: mode,
            lenses: lenses,
            tags: tags,
          );
          final layers = (style['layers'] as List).cast<Map<String, Object?>>();
          final lines = [
            for (final layer in layers)
              if (lineLayers.contains(layer['id'])) layer['filter'],
          ];
          final coverage = layers.firstWhere(
            (l) => l['id'] == pointerTargetLayerId,
          )['filter'];

          for (final props in featureSpread()) {
            final drawn = lines.any((f) => evaluate(f, props) == true);
            expect(
              evaluate(coverage, props),
              drawn,
              reason:
                  'mode ${mode.name}, lenses ${lenses.map((l) => l.name)}, '
                  'props $props',
            );
          }
        }
      }
    }
  });

  // A formal trail anyone may ride, with no IMBA rating — the exact thing the
  // difficulty lens paints magenta and a steward is here to fix.
  Map<String, Object?> unrated({int id = 100}) => {
    'OSM_ID': id,
    'highway': 'path',
    'bicycle': 'designated',
  };

  group('the difficulty lens, straight off the tiles', () {
    test('an unrated trail draws as unspecified', () {
      expect(
        layersDrawing(
          unrated(),
          mode: TravelMode.mtb,
          lenses: {Lens.difficulty},
        ),
        {'unspecified-paths'},
      );
    });

    test('a rated trail draws as specified', () {
      expect(
        layersDrawing(
          {...unrated(), 'mtb:scale:imba': '4'},
          mode: TravelMode.mtb,
          lenses: {Lens.difficulty},
        ),
        {'paths'},
      );
    });
  });

  group('with an override standing in for a stale tile', () {
    test(
      'a rating Steward has seen recolours a trail the tiles call unrated',
      () {
        expect(
          layersDrawing(
            unrated(),
            mode: TravelMode.mtb,
            lenses: {Lens.difficulty},
            tags: const TagSource.overriding({
              100: {
                'highway': 'path',
                'bicycle': 'designated',
                'mtb:scale:imba': '4',
              },
            }),
          ),
          {'paths'},
          reason:
              'this is the submitted-then-refreshed case the cache exists for',
        );
      },
    );

    test('a tag the override drops goes back to unspecified', () {
      // The tile still carries the rating; OSM no longer does. Falling through
      // to the tile for a key the override lacks would keep drawing it teal.
      expect(
        layersDrawing(
          {...unrated(), 'mtb:scale:imba': '4'},
          mode: TravelMode.mtb,
          lenses: {Lens.difficulty},
          tags: const TagSource.overriding({
            100: {'highway': 'path', 'bicycle': 'designated'},
          }),
        ),
        {'unspecified-paths'},
      );
    });

    test('a trail nobody has looked at still reads from its tile', () {
      expect(
        layersDrawing(
          unrated(id: 999),
          mode: TravelMode.mtb,
          lenses: {Lens.difficulty},
          tags: const TagSource.overriding({
            100: {'highway': 'path', 'mtb:scale:imba': '4'},
          }),
        ),
        {'unspecified-paths'},
      );
    });

    test('someone else\'s access edit reaches the access lens too', () {
      // Nothing Steward writes touches access, so this can only arrive via a
      // read — source 2 of the cache.
      expect(
        layersDrawing(unrated(), mode: TravelMode.mtb, lenses: {Lens.access}),
        {'unspecified-paths'},
        reason:
            'bicycle=designated does not say whether *mountain biking* is '
            'sanctioned — that is what the mtb key is for',
      );
      expect(
        layersDrawing(
          unrated(),
          mode: TravelMode.mtb,
          lenses: {Lens.access},
          tags: const TagSource.overriding({
            100: {'highway': 'path', 'bicycle': 'designated', 'mtb': 'yes'},
          }),
        ),
        {'paths'},
      );
      expect(
        layersDrawing(
          unrated(),
          mode: TravelMode.mtb,
          lenses: {Lens.access},
          tags: const TagSource.overriding({
            100: {'highway': 'path', 'bicycle': 'no'},
          }),
        ),
        {'disallowed-paths'},
        reason: 'an override can close a trail as well as open one',
      );
    });

    test('the three attribute lenses need every key, override or not', () {
      Set<String> withTags(Map<String, String> override) => layersDrawing(
        unrated(),
        mode: TravelMode.mtb,
        lenses: {Lens.difficulty, Lens.surface, Lens.electricBicycle},
        tags: TagSource.overriding({100: override}),
      );
      expect(
        withTags({'highway': 'path', 'mtb:scale:imba': '4'}),
        {'unspecified-paths'},
        reason: 'rated but still no surface',
      );
      expect(
        withTags({'highway': 'path', 'mtb:scale:imba': '4', 'surface': 'dirt'}),
        {'unspecified-paths'},
        reason: 'rated and surfaced, but still silent about e-bikes',
      );
      expect(
        withTags({
          'highway': 'path',
          'mtb:scale:imba': '4',
          'surface': 'dirt',
          'electric_bicycle': 'no',
        }),
        {'paths'},
      );
    });

    test('an override drives informal-ness and hit-testing as well', () {
      final style = buildStewardStyle(
        baseStyle(),
        mode: TravelMode.mtb,
        lenses: {Lens.difficulty},
        tags: const TagSource.overriding({
          100: {'highway': 'path', 'informal': 'yes', 'mtb:scale:imba': '4'},
        }),
      );
      expect(
        layersDrawing(
          unrated(),
          mode: TravelMode.mtb,
          lenses: {Lens.difficulty},
          tags: const TagSource.overriding({
            100: {'highway': 'path', 'informal': 'yes', 'mtb:scale:imba': '4'},
          }),
        ),
        {'informal-paths'},
      );
      final pointer = (style['layers'] as List)
          .cast<Map<String, Object?>>()
          .firstWhere((l) => l['id'] == pointerTargetLayerId);
      expect(
        evaluate(pointer['filter'], unrated()),
        isTrue,
        reason: 'an overridden trail must stay clickable',
      );
    });
  });
}

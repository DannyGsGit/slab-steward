import 'package:flutter_test/flutter_test.dart';
import 'package:slab_steward/src/map/otm_conventions.dart';
import 'package:slab_steward/src/map/steward_style.dart';
import 'package:slab_steward/src/model/lens.dart';
import 'package:slab_steward/src/model/trail_filters.dart';

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
    case 'id':
      return props[featureIdKey];
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

/// Where [evaluate] reads a feature's own id from, standing in for the id an
/// MVT feature carries alongside its attributes.
const featureIdKey = r'$id';

/// A tile feature as MapLibre sees it: the tile's attributes, plus the id
/// identity actually rides on since the tileset dropped its `OSM_ID` column.
///
/// Fixtures still name the way under `OSM_ID` because that is how Steward
/// files it downstream; this is the one place it becomes a feature id, which
/// mirrors what the map view does with a real query result.
Map<String, Object?> tileFeature(Map<String, Object?> props) => {
  ...props,
  if (props['OSM_ID'] case final int wayId)
    featureIdKey: tileFeatureIdForWay(wayId),
};

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

/// The mode selections the coverage sweep stands on: nobody (no access
/// filtering at all), one mode, and both at once.
const _modeSelections = <Set<TravelMode>>[
  {},
  {TravelMode.mtb},
  {TravelMode.mtb, TravelMode.foot},
];

/// Which of the overlay's trail-line layers would draw [props].
Set<String> layersDrawing(
  Map<String, Object?> rawProps, {
  required Set<TravelMode> modes,
  required Set<Lens> lenses,
  Set<TrailKind> kinds = const {...TrailKind.values},
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
    modes: modes,
    lenses: lenses,
    kinds: kinds,
    tags: tags,
  );
  final layers = (style['layers'] as List).cast<Map<String, Object?>>();
  final props = tileFeature(rawProps);
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
              yield tileFeature({
                'OSM_ID': 55,
                'highway': ?highway,
                'access': ?access,
                'mtb': ?mtb,
                'bicycle': ?bicycle,
                'mtb:scale:imba': ?rating,
                'informal': ?informal,
              });
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
      {Lens.difficulty, Lens.electricBicycle},
      {Lens.access, Lens.difficulty},
      {Lens.access, Lens.difficulty, Lens.electricBicycle},
    ];

    for (final modes in _modeSelections) {
      for (final lenses in selections) {
        for (final tags in [const TagSource.tiles(), overriding]) {
          final style = buildStewardStyle(
            baseStyle(),
            modes: modes,
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
                  'modes ${modes.map((m) => m.name)}, lenses ${lenses.map((l) => l.name)}, '
                  'props $props',
            );
          }
        }
      }
    }
  });

  group('the rating a trail is drawn in', () {
    Object? colorOf(
      Map<String, Object?> props, {
      TagSource tags = const TagSource.tiles(),
    }) => evaluate(difficultyLineColor(tags), tileFeature(props));

    test('comes from the trail\'s own mtb:scale:imba', () {
      const expected = {
        '0': easyTrailColor,
        '1': easyTrailColor,
        '2': mediumTrailColor,
        '3': hardTrailColor,
        '4': veryHardTrailColor,
      };
      expected.forEach((scale, color) {
        expect(
          colorOf({'OSM_ID': 7, 'mtb:scale:imba': scale}),
          color,
          reason: 'mtb:scale:imba=$scale',
        );
      });
    });

    test('is purple where there is no rating, or none Steward can read', () {
      expect(colorOf({'OSM_ID': 7}), unspecifiedColor);
      expect(
        colorOf({'OSM_ID': 7, 'mtb:scale:imba': 'unknown'}),
        unspecifiedColor,
      );
    });

    test('follows the override, so a rating recolours before the next '
        'planet build', () {
      final overriding = TagSource.overriding(const {
        7: {'highway': 'path', 'mtb:scale:imba': '3'},
      });
      // The tile still says the trail is easy; Steward has since read it as
      // difficult, and the line has to say so.
      expect(
        colorOf({'OSM_ID': 7, 'mtb:scale:imba': '1'}, tags: overriding),
        hardTrailColor,
      );
      // A trail the override says nothing about keeps reading from the tile.
      expect(
        colorOf({'OSM_ID': 8, 'mtb:scale:imba': '1'}, tags: overriding),
        easyTrailColor,
      );
    });

    test('goes back to purple when an override drops the rating', () {
      final overriding = TagSource.overriding(const {
        7: {'highway': 'path'},
      });
      expect(
        colorOf({'OSM_ID': 7, 'mtb:scale:imba': '2'}, tags: overriding),
        unspecifiedColor,
      );
    });
  });

  group('the selection glow', () {
    Map<String, Object?> trail(int wayId, {String highway = 'path'}) =>
        tileFeature({'OSM_ID': wayId, 'highway': highway});

    bool glows(
      Map<String, Object?> feature,
      List<int> selected, {
      Set<TrailKind> kinds = const {...TrailKind.values},
      TagSource tags = const TagSource.tiles(),
    }) =>
        evaluate(
          selectionFilter(selected, kinds: kinds, tags: tags),
          feature,
        ) ==
        true;

    test('picks out exactly the ways in the working set', () {
      // The whole point of filtering on the id rather than drawing fetched
      // geometry: a box selection names thirty ways at once and none of them
      // has been read from the OSM API yet.
      const boxed = [7, 8, 9];
      expect(glows(trail(7), boxed), isTrue);
      expect(glows(trail(9), boxed), isTrue);
      expect(glows(trail(10), boxed), isFalse);
    });

    test('nothing glows when nothing is selected', () {
      expect(glows(trail(7), const []), isFalse);
    });

    test('a selected trail hidden by a kind toggle takes its glow with it', () {
      final sidewalk = trail(7, highway: 'footway');
      expect(glows(sidewalk, const [7]), isTrue);
      expect(
        glows(sidewalk, const [7], kinds: const {TrailKind.informal}),
        isFalse,
        reason: 'a glow with no line under it is a ghost',
      );
    });

    test('a feature that is not a trail at all never glows', () {
      // Same id, but the tileset also carries waterways and ferries.
      expect(glows(tileFeature({'OSM_ID': 7}), const [7]), isFalse);
    });
  });

  group('the kind toggles', () {
    Map<String, Object?> feature(Map<String, Object?> tags) => tileFeature({
      'OSM_ID': 7,
      'highway': 'path',
      'bicycle': 'designated',
      'mtb:scale:imba': '2',
      ...tags,
    });

    Set<String> drawnWith(Map<String, Object?> props, Set<TrailKind> kinds) =>
        layersDrawing(
          props,
          modes: {TravelMode.mtb},
          lenses: {Lens.difficulty},
          kinds: kinds,
        );

    test('a paved path is drawn only while pavement is switched on', () {
      final paved = feature({'surface': 'asphalt'});
      expect(drawnWith(paved, TrailKind.defaults), isEmpty);
      expect(drawnWith(paved, {...TrailKind.defaults, TrailKind.paved}), {
        'paths',
      });
      expect(
        drawnWith(feature({'surface': 'ground'}), TrailKind.defaults),
        {'paths'},
        reason: 'switching off pavement must not take dirt with it',
      );
    });

    test('sidewalks stay off the map until they are asked for', () {
      final sidewalk = feature({'highway': 'footway'});
      expect(drawnWith(sidewalk, TrailKind.defaults), isEmpty);
      expect(drawnWith(sidewalk, {...TrailKind.defaults, TrailKind.footway}), {
        'paths',
      });
    });

    test('informal lines are drawn by default; doubletrack is asked for', () {
      final track = feature({'highway': 'track'});
      final informal = feature({'informal': 'yes'});

      // Hard-coded rather than read off TrailKind.defaults: which kinds a
      // fresh session draws is a product decision, and this is what notices
      // when one changes.
      expect(TrailKind.defaults, {TrailKind.informal});
      expect(drawnWith(informal, TrailKind.defaults), {'informal-paths'});
      expect(drawnWith(track, TrailKind.defaults), isEmpty);

      expect(drawnWith(track, {TrailKind.track}), {'paths'});
      expect(drawnWith(informal, {TrailKind.track}), isEmpty);
    });

    test('a hidden trail is not clickable either', () {
      // The hit targets are a separate layer with a filter of their own, and
      // a trail nobody can see must not still be selectable through the line
      // that is no longer drawn.
      final style = buildStewardStyle(
        baseStyle(),
        modes: {TravelMode.mtb},
        lenses: {Lens.difficulty},
        kinds: TrailKind.defaults,
      );
      final pointer = (style['layers'] as List)
          .cast<Map<String, Object?>>()
          .firstWhere((l) => l['id'] == pointerTargetLayerId);
      expect(
        evaluate(pointer['filter'], feature({'highway': 'footway'})),
        isFalse,
      );
      expect(
        evaluate(pointer['filter'], feature({'surface': 'asphalt'})),
        isFalse,
      );
      expect(evaluate(pointer['filter'], feature({})), isTrue);
    });
  });

  // A formal trail anyone may ride, with no IMBA rating — the exact thing the
  // difficulty lens paints magenta and a steward is here to fix.
  Map<String, Object?> unrated({int id = 100}) =>
      tileFeature({'OSM_ID': id, 'highway': 'path', 'bicycle': 'designated'});

  group('the difficulty lens, straight off the tiles', () {
    test('an unrated trail draws as unspecified', () {
      expect(
        layersDrawing(
          unrated(),
          modes: {TravelMode.mtb},
          lenses: {Lens.difficulty},
        ),
        {'unspecified-paths'},
      );
    });

    test('a rated trail draws as specified', () {
      expect(
        layersDrawing(
          {...unrated(), 'mtb:scale:imba': '4'},
          modes: {TravelMode.mtb},
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
            modes: {TravelMode.mtb},
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
          modes: {TravelMode.mtb},
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
          modes: {TravelMode.mtb},
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
        layersDrawing(
          unrated(),
          modes: {TravelMode.mtb},
          lenses: {Lens.access},
        ),
        {'unspecified-paths'},
        reason:
            'bicycle=designated does not say whether *mountain biking* is '
            'sanctioned — that is what the mtb key is for',
      );
      expect(
        layersDrawing(
          unrated(),
          modes: {TravelMode.mtb},
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
          modes: {TravelMode.mtb},
          lenses: {Lens.access},
          tags: const TagSource.overriding({
            100: {'highway': 'path', 'bicycle': 'no'},
          }),
        ),
        {'disallowed-paths'},
        reason: 'an override can close a trail as well as open one',
      );
    });

    test('the attribute lenses need every key, override or not', () {
      Set<String> withTags(Map<String, String> override) => layersDrawing(
        unrated(),
        modes: {TravelMode.mtb},
        lenses: {Lens.difficulty, Lens.electricBicycle},
        tags: TagSource.overriding({100: override}),
      );
      expect(
        withTags({'highway': 'path', 'mtb:scale:imba': '4'}),
        {'unspecified-paths'},
        reason: 'rated, but still silent about e-bikes',
      );
      expect(
        withTags({'highway': 'path', 'electric_bicycle': 'no'}),
        {'unspecified-paths'},
        reason: 'answered on e-bikes, but still unrated',
      );
      expect(
        withTags({
          'highway': 'path',
          'mtb:scale:imba': '4',
          'electric_bicycle': 'no',
        }),
        {'paths'},
      );
    });

    test('an override drives informal-ness and hit-testing as well', () {
      final style = buildStewardStyle(
        baseStyle(),
        modes: {TravelMode.mtb},
        lenses: {Lens.difficulty},
        tags: const TagSource.overriding({
          100: {'highway': 'path', 'informal': 'yes', 'mtb:scale:imba': '4'},
        }),
      );
      expect(
        layersDrawing(
          unrated(),
          modes: {TravelMode.mtb},
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

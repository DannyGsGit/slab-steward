import 'package:flutter_test/flutter_test.dart';
import 'package:slab_steward/src/map/steward_style.dart';
import 'package:slab_steward/src/map/otm_conventions.dart';
import 'package:slab_steward/src/model/difficulty.dart';
import 'package:slab_steward/src/model/lens.dart';

/// A stand-in for the published OpenTrailMap stylesheet: just enough of it to
/// exercise the splice.
Map<String, Object?> fakeBaseStyle() => {
  'version': 8,
  'sources': <String, Object?>{
    'sourdough': {'type': 'vector', 'url': 'https://example.test/basemap.json'},
  },
  'layers': <Map<String, Object?>>[
    {'id': 'background', 'type': 'background'},
    {'id': 'trails_official', 'type': 'line', 'source': 'sourdough'},
    {'id': 'trails_informal', 'type': 'line', 'source': 'sourdough'},
    {'id': 'qa_insertion_point', 'type': 'background'},
    {'id': 'trail_labels', 'type': 'symbol', 'source': 'sourdough'},
    {'id': 'place_labels', 'type': 'symbol', 'source': 'sourdough'},
  ],
};

/// Both attribute lenses together — what used to be the single fixed
/// "Missing any" lens, and what the app selects by default.
const attributeLenses = {Lens.difficulty, Lens.electricBicycle};

List<Map<String, Object?>> layersOf(Map<String, Object?> style) =>
    (style['layers'] as List).cast<Map<String, Object?>>();

Map<String, Object?>? layerById(Map<String, Object?> style, String id) =>
    layersOf(style).where((l) => l['id'] == id).firstOrNull;

void main() {
  test('adds the trails and staged sources', () {
    final style = buildStewardStyle(
      fakeBaseStyle(),
      modes: {TravelMode.mtb},
      lenses: attributeLenses,
    );
    final sources = style['sources']! as Map<String, Object?>;
    expect(sources, contains('trails'));
    expect(sources, contains(stagedSourceId));
    // The selection glow needs no source of its own: it filters the tileset.
    expect(layerById(style, selectionLayerId)!['source'], trailsSourceId);
    // The basemap source must survive the splice.
    expect(sources, contains('sourdough'));
  });

  test('credits OSM and OSM US on the trails source', () {
    final style = buildStewardStyle(
      fakeBaseStyle(),
      modes: {TravelMode.mtb},
      lenses: const <Lens>{},
    );
    final trails = (style['sources']! as Map)['trails']! as Map;
    expect(trails['attribution'], contains('OpenStreetMap'));
  });

  test('hides the basemap trail layers so trails are not drawn twice', () {
    final style = buildStewardStyle(
      fakeBaseStyle(),
      modes: {TravelMode.mtb},
      lenses: const <Lens>{},
    );
    for (final id in ['trails_official', 'trails_informal', 'trail_labels']) {
      final layout = layerById(style, id)!['layout']! as Map<String, Object?>;
      expect(layout['visibility'], 'none', reason: '$id should be hidden');
    }
    // Everything else is left alone.
    expect(layerById(style, 'place_labels')!['layout'], isNull);
  });

  test('inserts the overlay above the basemap but below labels', () {
    final style = buildStewardStyle(
      fakeBaseStyle(),
      modes: {TravelMode.mtb},
      lenses: attributeLenses,
    );
    final ids = layersOf(style).map((l) => l['id']).toList();
    expect(ids.indexOf('background'), lessThan(ids.indexOf('paths')));
    expect(ids.indexOf('paths'), lessThan(ids.indexOf('place_labels')));
    // The hit-test layer has to sit on top of the drawn lines.
    expect(ids.indexOf('paths'), lessThan(ids.indexOf(pointerTargetLayerId)));
  });

  test('the glows stack under the trail lines, in reading order', () {
    final style = buildStewardStyle(
      fakeBaseStyle(),
      modes: {TravelMode.mtb},
      lenses: attributeLenses,
    );
    final ids = layersOf(style).map((l) => l['id']).toList();
    // What the Highlight rules found, then what has an edit waiting on it,
    // then what is in hand — and all of it under the lines themselves.
    const order = [
      'highlight-glow',
      'highlight-glow-core',
      'staged-glow',
      'staged-glow-core',
      selectionLayerId,
      'paths',
    ];
    for (var i = 1; i < order.length; i++) {
      expect(
        ids.indexOf(order[i - 1]),
        lessThan(ids.indexOf(order[i])),
        reason: '${order[i - 1]} should sit under ${order[i]}',
      );
    }

    // Blurred, or none of them is a glow.
    for (final id in order.where((id) => id != 'paths')) {
      final paint = layerById(style, id)!['paint']! as Map<String, Object?>;
      expect(paint['line-blur'], greaterThan(0), reason: id);
    }
  });

  group('the colour scheme — docs/specs/map_view.md', () {
    Map<String, Object?> paintOf(Map<String, Object?> style, String id) =>
        layerById(style, id)!['paint']! as Map<String, Object?>;

    test('every trail line is coloured by its IMBA rating', () {
      final style = buildStewardStyle(
        fakeBaseStyle(),
        modes: {TravelMode.mtb},
        lenses: attributeLenses,
      );
      const lineLayers = [
        'paths',
        'informal-paths',
        'unspecified-paths',
        'unspecified-informal-paths',
        'disallowed-paths',
        'disallowed-informal-paths',
      ];
      for (final id in lineLayers) {
        expect(
          paintOf(style, id)['line-color'],
          difficultyLineColor(const TagSource.tiles()),
          reason: '$id should read mtb:scale:imba, not the lens selection',
        );
      }
    });

    test('the rating colours are the five the spec names', () {
      final colors = difficultyLineColor(const TagSource.tiles());
      expect(colors, contains(easyTrailColor));
      expect(colors, contains(mediumTrailColor));
      expect(colors, contains(hardTrailColor));
      expect(colors, contains(veryHardTrailColor));
      // The fallback: no rating reads as purple, the same purple "OSM doesn't
      // know" has always been.
      expect(colors.last, unspecifiedColor);
      expect(difficultyColor(Difficulty.unrated), unspecifiedColor);
    });

    test('the highlight glow is gold and follows the lens selection', () {
      final style = buildStewardStyle(
        fakeBaseStyle(),
        modes: {TravelMode.mtb},
        lenses: {Lens.difficulty},
      );
      for (final id in ['highlight-glow', 'highlight-glow-core']) {
        expect(paintOf(style, id)['line-color'], highlightGlowColor);
        // The trails it picks out are the ones the rules are hunting: the
        // same set the unspecified layers draw.
        expect(
          layerById(style, id)!['filter'].toString(),
          contains('mtb:scale:imba'),
        );
      }
    });

    test('nothing glows gold when no rule is ticked', () {
      final style = buildStewardStyle(
        fakeBaseStyle(),
        modes: const <TravelMode>{},
        lenses: const <Lens>{},
      );
      final filter = layerById(style, 'highlight-glow')!['filter']! as List;
      expect(filter[1], isFalse);
    });

    test('the selection glow is teal', () {
      final style = buildStewardStyle(
        fakeBaseStyle(),
        modes: {TravelMode.mtb},
        lenses: attributeLenses,
      );
      expect(paintOf(style, selectionLayerId)['line-color'], selectionColor);
      expect(
        paintOf(style, selectionLayerId)['line-color'],
        isNot(highlightGlowColor),
      );
    });

    test(
      'the staged glow takes its colour from the feature, purple absent',
      () {
        final style = buildStewardStyle(
          fakeBaseStyle(),
          modes: {TravelMode.mtb},
          lenses: attributeLenses,
        );
        for (final id in ['staged-glow', 'staged-glow-core']) {
          expect(paintOf(style, id)['line-color'], [
            'coalesce',
            ['get', stagedGlowColorKey],
            difficultyColor(Difficulty.unrated),
          ]);
        }
      },
    );

    test('dashed stays dashed, and shut trails fade rather than recolour', () {
      final style = buildStewardStyle(
        fakeBaseStyle(),
        modes: {TravelMode.mtb},
        lenses: attributeLenses,
      );
      for (final id in [
        'informal-paths',
        'unspecified-informal-paths',
        'disallowed-paths',
        'disallowed-informal-paths',
      ]) {
        expect(paintOf(style, id)['line-dasharray'], [2, 2], reason: id);
      }
      for (final id in ['disallowed-paths', 'disallowed-informal-paths']) {
        expect(paintOf(style, id)['line-opacity'], disallowedOpacity);
      }
      // The trails a rider may ride are drawn at full strength.
      expect(paintOf(style, 'paths')['line-opacity'], isNull);
      expect(paintOf(style, 'paths')['line-dasharray'], isNull);
    });
  });

  group('the selection glow', () {
    test('starts empty — the working set is applied at runtime', () {
      final style = buildStewardStyle(
        fakeBaseStyle(),
        modes: {TravelMode.mtb},
        lenses: attributeLenses,
      );
      expect(
        layerById(style, selectionLayerId)!['filter'],
        selectionFilter(const []),
      );
    });

    test('sits directly under the lowest trail line', () {
      final style = buildStewardStyle(
        fakeBaseStyle(),
        modes: {TravelMode.mtb},
        lenses: attributeLenses,
      );
      final ids = layersOf(style).map((l) => l['id']).toList();
      // [selectionBelowLayerId] is what the map view re-adds the layer
      // against, so a reordering of the lines has to be noticed here.
      expect(
        ids[ids.indexOf(selectionLayerId) + 1],
        selectionBelowLayerId,
        reason: 'the glow must stay immediately under the first line layer',
      );
    });
  });

  test('throws rather than silently drawing nothing if the marker is gone', () {
    final base = fakeBaseStyle();
    (base['layers'] as List).removeWhere(
      (l) => l['id'] == 'qa_insertion_point',
    );
    expect(
      () => buildStewardStyle(base, modes: {TravelMode.mtb}, lenses: const {}),
      throwsStateError,
    );
  });

  group('layer coverage', () {
    // Every trail in the tileset has to land in exactly one line layer.
    // The filters are MapLibre expressions, so this checks their shape rather
    // than evaluating them: disallowed trails must not be gated on the lenses,
    // or a restricted trail with missing tags would match nothing at all.
    test('disallowed layers ignore the lenses', () {
      final style = buildStewardStyle(
        fakeBaseStyle(),
        modes: {TravelMode.mtb},
        lenses: attributeLenses,
      );
      final filter = layerById(style, 'disallowed-paths')!['filter'].toString();
      expect(filter, isNot(contains('mtb:scale:imba')));
    });

    test('the lenses gate the allowed layers', () {
      final style = buildStewardStyle(
        fakeBaseStyle(),
        modes: {TravelMode.mtb},
        lenses: attributeLenses,
      );
      final filter = layerById(
        style,
        'unspecified-paths',
      )!['filter'].toString();
      expect(filter, contains('mtb:scale:imba'));
      expect(filter, contains('electric_bicycle'));
    });
  });

  test('no lens selected means nothing renders as missing', () {
    final style = buildStewardStyle(
      fakeBaseStyle(),
      modes: const <TravelMode>{},
      lenses: const <Lens>{},
    );
    // The layer still exists, but its filter is switched off outright.
    final filter = layerById(style, 'unspecified-paths')!['filter']! as List;
    expect(filter[1], isFalse);
  });
}

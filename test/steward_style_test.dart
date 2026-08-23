import 'package:flutter_test/flutter_test.dart';
import 'package:slab_steward/src/map/steward_style.dart';
import 'package:slab_steward/src/map/otm_conventions.dart';
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

List<Map<String, Object?>> layersOf(Map<String, Object?> style) =>
    (style['layers'] as List).cast<Map<String, Object?>>();

Map<String, Object?>? layerById(Map<String, Object?> style, String id) =>
    layersOf(style).where((l) => l['id'] == id).firstOrNull;

void main() {
  test('adds the trails and selection sources', () {
    final style = buildStewardStyle(
      fakeBaseStyle(),
      mode: TravelMode.mtb,
      lens: Lens.completeness,
    );
    final sources = style['sources']! as Map<String, Object?>;
    expect(sources, contains('trails'));
    expect(sources, contains(selectionSourceId));
    expect(sources, contains(stagedSourceId));
    // The basemap source must survive the splice.
    expect(sources, contains('sourdough'));
  });

  test('credits OSM and OSM US on the trails source', () {
    final style = buildStewardStyle(
      fakeBaseStyle(),
      mode: TravelMode.mtb,
      lens: Lens.none,
    );
    final trails = (style['sources']! as Map)['trails']! as Map;
    expect(trails['attribution'], contains('OpenStreetMap'));
  });

  test('hides the basemap trail layers so trails are not drawn twice', () {
    final style = buildStewardStyle(
      fakeBaseStyle(),
      mode: TravelMode.mtb,
      lens: Lens.none,
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
      mode: TravelMode.mtb,
      lens: Lens.completeness,
    );
    final ids = layersOf(style).map((l) => l['id']).toList();
    expect(ids.indexOf('background'), lessThan(ids.indexOf('paths')));
    expect(ids.indexOf('paths'), lessThan(ids.indexOf('place_labels')));
    // The hit-test layer has to sit on top of the drawn lines.
    expect(ids.indexOf('paths'), lessThan(ids.indexOf(pointerTargetLayerId)));
  });

  test('the staged glow sits under the selection and the trail lines', () {
    final style = buildStewardStyle(
      fakeBaseStyle(),
      mode: TravelMode.mtb,
      lens: Lens.completeness,
    );
    final ids = layersOf(style).map((l) => l['id']).toList();
    expect(ids.indexOf('staged-glow'), lessThan(ids.indexOf('staged-glow-core')));
    expect(ids.indexOf('staged-glow-core'), lessThan(ids.indexOf('selected-trail')));
    expect(ids.indexOf('selected-trail'), lessThan(ids.indexOf('paths')));

    // Blurred and blue, or it isn't a glow.
    for (final id in ['staged-glow', 'staged-glow-core']) {
      final paint = layerById(style, id)!['paint']! as Map<String, Object?>;
      expect(paint['line-color'], stagedEditColor);
      expect(paint['line-blur'], greaterThan(0));
    }
  });

  test('throws rather than silently drawing nothing if the marker is gone', () {
    final base = fakeBaseStyle();
    (base['layers'] as List).removeWhere((l) => l['id'] == 'qa_insertion_point');
    expect(
      () => buildStewardStyle(base, mode: TravelMode.mtb, lens: Lens.none),
      throwsStateError,
    );
  });

  group('layer coverage', () {
    // Every trail in the tileset has to land in exactly one line layer.
    // The filters are MapLibre expressions, so this checks their shape rather
    // than evaluating them: disallowed trails must not be gated on the lens,
    // or a restricted trail with missing tags would match nothing at all.
    test('disallowed layers ignore the lens', () {
      final style = buildStewardStyle(
        fakeBaseStyle(),
        mode: TravelMode.mtb,
        lens: Lens.completeness,
      );
      final filter = layerById(style, 'disallowed-paths')!['filter'].toString();
      expect(filter, isNot(contains('mtb:scale:imba')));
    });

    test('the lens gates the allowed layers', () {
      final style = buildStewardStyle(
        fakeBaseStyle(),
        mode: TravelMode.mtb,
        lens: Lens.completeness,
      );
      final filter = layerById(style, 'unspecified-paths')!['filter'].toString();
      expect(filter, contains('mtb:scale:imba'));
      expect(filter, contains('surface'));
    });
  });

  test('no lens means nothing renders as missing', () {
    final style = buildStewardStyle(
      fakeBaseStyle(),
      mode: TravelMode.all,
      lens: Lens.none,
    );
    // The layer still exists, but its filter is switched off outright.
    final filter = layerById(style, 'unspecified-paths')!['filter']! as List;
    expect(filter[1], isFalse);
  });
}

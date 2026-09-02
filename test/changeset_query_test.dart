import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:slab_steward/src/osm/osm_api.dart';

/// `OsmApi.fetchChangesets` filters on the hashtag *itself*, because
/// `changesets.json` accepts a `hashtag` parameter and silently ignores it.
/// See docs/specs/analytics.md §5.

/// One changeset as `changesets.json` returns it.
Map<String, Object?> _changeset(int id, Map<String, String> tags) => {
  'id': id,
  'created_at': '2026-08-0${id}T12:00:00Z',
  'closed_at': '2026-08-0${id}T12:00:05Z',
  'changes_count': 3,
  'tags': tags,
};

/// An [OsmApi] answering `changesets.json` with [changesets], and recording
/// the query it was asked.
(OsmApi, List<Uri>) _apiReturning(List<Map<String, Object?>> changesets) {
  final asked = <Uri>[];
  final api = OsmApi(
    client: MockClient((request) async {
      asked.add(request.url);
      return http.Response(
        jsonEncode({'version': '0.6', 'changesets': changesets}),
        200,
      );
    }),
  );
  return (api, asked);
}

void main() {
  test('keeps only the changesets actually tagged with the hashtag', () async {
    final (api, _) = _apiReturning([
      _changeset(1, {
        'comment': 'Rated three trails #slabsteward',
        'hashtags': '#slabsteward',
        'created_by': 'SLAB Steward/0.1.0',
      }),
      // The years of other mapping this pane exists to keep out.
      _changeset(2, {'comment': 'Added a bus stop', 'created_by': 'JOSM/1.5'}),
      _changeset(3, {'comment': 'Mapped a park #missingmaps'}),
    ]);

    final result = await api.fetchChangesets(
      userId: 7,
      hashtag: 'slabsteward',
      bearerToken: 'token',
    );

    expect(result.map((c) => c.id), [1]);
  });

  test('does not send a hashtag parameter the server would ignore', () async {
    final (api, asked) = _apiReturning([]);

    await api.fetchChangesets(
      userId: 7,
      hashtag: 'slabsteward',
      bearerToken: 'token',
    );

    expect(asked.single.queryParameters, {'user': '7', 'closed': 'true'});
  });

  test('a hashtag only in the comment still counts', () async {
    // What OSM itself does, and what ensureHashtag guarantees: a comment
    // carrying #slabsteward makes the changeset tagged, `hashtags` tag or not.
    final (api, _) = _apiReturning([
      _changeset(1, {'comment': 'Set surface on two trails #slabsteward'}),
    ]);

    final result = await api.fetchChangesets(
      userId: 7,
      hashtag: 'slabsteward',
      bearerToken: 'token',
    );

    expect(result, hasLength(1));
  });

  test('matching ignores case and a leading hash', () async {
    final (api, _) = _apiReturning([
      _changeset(1, {'hashtags': '#SlabSteward'}),
      _changeset(2, {'hashtags': 'slabsteward'}),
    ]);

    final result = await api.fetchChangesets(
      userId: 7,
      hashtag: '#slabsteward',
      bearerToken: 'token',
    );

    expect(result, hasLength(2));
  });

  test('a longer hashtag that merely starts the same does not match', () async {
    final (api, _) = _apiReturning([
      _changeset(1, {'hashtags': '#slabstewardship'}),
      _changeset(2, {'comment': 'Tidied up #slabstewardship'}),
    ]);

    final result = await api.fetchChangesets(
      userId: 7,
      hashtag: 'slabsteward',
      bearerToken: 'token',
    );

    expect(result, isEmpty);
  });

  test('one changeset among several hashtags is still ours', () async {
    final (api, _) = _apiReturning([
      _changeset(1, {'hashtags': '#trailwork;#slabsteward;#pnw'}),
    ]);

    final result = await api.fetchChangesets(
      userId: 7,
      hashtag: 'slabsteward',
      bearerToken: 'token',
    );

    expect(result, hasLength(1));
  });

  test('a changeset with no tags at all is not a crash', () async {
    final (api, _) = _apiReturning([
      {'id': 1, 'created_at': '2026-08-01T12:00:00Z', 'changes_count': 1},
    ]);

    final result = await api.fetchChangesets(
      userId: 7,
      hashtag: 'slabsteward',
      bearerToken: 'token',
    );

    expect(result, isEmpty);
  });
}

import 'dart:convert';

import 'package:http/http.dart' as http;

/// Thin client for the slice of OSM API v0.6 that Steward needs.
///
/// Called directly from the browser, no proxy — see the product description §7.
/// Today that's read-only; the changeset half (open / upload / close, under the
/// user's own OAuth token) lands with the editor.
class OsmApi {
  OsmApi({http.Client? client, this.baseUrl = productionApi})
    : _client = client ?? http.Client();

  static const productionApi = 'https://api.openstreetmap.org';

  /// The OSM dev sandbox. Point at this while wiring up editing so test
  /// changesets never reach the live map.
  static const developmentApi = 'https://api06.dev.openstreetmap.org';

  final http.Client _client;
  final String baseUrl;

  /// Fetches a way with its nodes resolved into coordinates.
  ///
  /// Throws [OsmApiException] on anything other than a clean read — including
  /// 410 Gone, which is what a deleted way returns and which the caller should
  /// surface as "this trail no longer exists" rather than as a network error.
  Future<OsmWay> fetchWay(int wayId) async {
    final uri = Uri.parse('$baseUrl/api/0.6/way/$wayId/full.json');
    final http.Response response;
    try {
      response = await _client.get(uri);
    } catch (e) {
      throw OsmApiException('Could not reach the OSM API', cause: e);
    }
    if (response.statusCode != 200) {
      throw OsmApiException(
        'OSM API returned ${response.statusCode} for way $wayId',
        statusCode: response.statusCode,
      );
    }

    final body = jsonDecode(response.body) as Map<String, Object?>;
    final elements = (body['elements'] as List).cast<Map<String, Object?>>();

    final nodes = <int, List<double>>{};
    Map<String, Object?>? way;
    for (final element in elements) {
      switch (element['type']) {
        case 'node':
          nodes[(element['id'] as num).toInt()] = [
            (element['lon'] as num).toDouble(),
            (element['lat'] as num).toDouble(),
          ];
        case 'way':
          way = element;
      }
    }
    if (way == null) {
      throw OsmApiException('OSM API response contained no way $wayId');
    }

    final nodeIds = (way['nodes'] as List).cast<num>();
    return OsmWay(
      id: (way['id'] as num).toInt(),
      version: (way['version'] as num).toInt(),
      tags: ((way['tags'] as Map<String, Object?>?) ?? const {})
          .map((k, v) => MapEntry(k, v.toString())),
      geometry: [for (final nodeId in nodeIds) ?nodes[nodeId.toInt()]],
      nodeIds: [for (final nodeId in nodeIds) nodeId.toInt()],
    );
  }

  void dispose() => _client.close();
}

class OsmWay {
  const OsmWay({
    required this.id,
    required this.version,
    required this.tags,
    required this.geometry,
    required this.nodeIds,
  });

  final int id;
  final int version;
  final Map<String, String> tags;
  final List<List<double>> geometry;

  /// The way's member nodes, in order. A changeset upload has to send these
  /// back verbatim — omitting even one turns a tag edit into a way truncation.
  final List<int> nodeIds;
}

class OsmApiException implements Exception {
  const OsmApiException(this.message, {this.statusCode, this.cause});

  final String message;
  final int? statusCode;
  final Object? cause;

  /// The way was deleted or redacted.
  bool get isGone => statusCode == 410 || statusCode == 404;

  @override
  String toString() => message;
}

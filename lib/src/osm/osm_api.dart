import 'dart:convert';

import 'package:http/http.dart' as http;

import 'osm_change_xml.dart';
import 'osm_environment.dart';
import 'submission_gate.dart' show ResolvedWrite;

/// Thin client for the slice of OSM API v0.6 that Steward needs.
///
/// Called directly from the browser, no proxy — see the product description
/// §7. Reads and the changeset write path (open / upload / close, under the
/// rider's own OAuth token) both go through here.
class OsmApi {
  OsmApi({http.Client? client, String? baseUrl})
    : _client = client ?? http.Client(),
      baseUrl = baseUrl ?? osmApiHost;

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
      tags: ((way['tags'] as Map<String, Object?>?) ?? const {}).map(
        (k, v) => MapEntry(k, v.toString()),
      ),
      geometry: [for (final nodeId in nodeIds) ?nodes[nodeId.toInt()]],
      nodeIds: [for (final nodeId in nodeIds) nodeId.toInt()],
    );
  }

  /// Resolves the signed-in rider's OSM identity — the display name shown
  /// next to "signed in as", and the id nothing here actually needs yet but
  /// which is cheap to carry along.
  Future<OsmIdentity> fetchUserDetails({required String bearerToken}) async {
    final uri = Uri.parse('$baseUrl/api/0.6/user/details.json');
    final response = await _authorized(bearerToken).get(uri);
    _checkOk(response, action: 'reading your OSM profile');
    final body = jsonDecode(response.body) as Map<String, Object?>;
    final user = body['user'] as Map<String, Object?>;
    return OsmIdentity(
      id: (user['id'] as num).toInt(),
      displayName: user['display_name'] as String,
    );
  }

  /// Opens a changeset carrying [tags] and returns its id. The first of the
  /// three calls a submission makes — see
  /// docs/specs/slab-steward-osm-changeset-spec.md §1.
  Future<int> openChangeset({
    required Map<String, String> tags,
    required String bearerToken,
  }) async {
    final uri = Uri.parse('$baseUrl/api/0.6/changeset/create');
    final response = await _authorized(bearerToken).put(
      uri,
      headers: {'Content-Type': 'text/xml; charset=utf-8'},
      body: changesetCreateXml(tags),
    );
    _checkOk(response, action: 'opening a changeset');
    return int.parse(response.body.trim());
  }

  /// Uploads the diff for [writes] as one atomic transaction — an
  /// `osmChange` document, not per-element PUTs, so a partial failure can't
  /// leave some trails written and others not. See the spec's "Diff upload
  /// vs. per-element PUT".
  Future<void> uploadChangeset({
    required int changesetId,
    required List<ResolvedWrite> writes,
    required String bearerToken,
  }) async {
    final uri = Uri.parse('$baseUrl/api/0.6/changeset/$changesetId/upload');
    final response = await _authorized(bearerToken).post(
      uri,
      headers: {'Content-Type': 'text/xml; charset=utf-8'},
      body: osmChangeXml(changesetId: changesetId, writes: writes),
    );
    _checkOk(response, action: 'uploading the changeset');
  }

  Future<void> closeChangeset({
    required int changesetId,
    required String bearerToken,
  }) async {
    final uri = Uri.parse('$baseUrl/api/0.6/changeset/$changesetId/close');
    final response = await _authorized(bearerToken).put(uri);
    _checkOk(response, action: 'closing the changeset');
  }

  http.Client _authorized(String bearerToken) =>
      _BearerClient(_client, bearerToken);

  void _checkOk(http.Response response, {required String action}) {
    if (response.statusCode ~/ 100 == 2) return;
    throw OsmApiException(
      'OSM API returned ${response.statusCode} while $action'
      '${response.body.isEmpty ? '' : ': ${response.body}'}',
      statusCode: response.statusCode,
    );
  }

  void dispose() => _client.close();
}

/// Adds the bearer token to every request without needing every call site to
/// build its own headers map by hand.
class _BearerClient extends http.BaseClient {
  _BearerClient(this._inner, this._token);

  final http.Client _inner;
  final String _token;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    request.headers['Authorization'] = 'Bearer $_token';
    return _inner.send(request);
  }
}

/// The rider's OSM account, as returned by `/api/0.6/user/details` — the
/// name displayed for "signed in as", cached alongside the token so it
/// survives a page reload without another round trip.
class OsmIdentity {
  const OsmIdentity({required this.id, required this.displayName});

  final int id;
  final String displayName;

  Map<String, Object?> toJson() => {'id': id, 'displayName': displayName};

  factory OsmIdentity.fromJson(Map<String, Object?> json) => OsmIdentity(
    id: (json['id'] as num).toInt(),
    displayName: json['displayName'] as String,
  );
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

  /// The access token is dead — revoked, or never valid. The only reliable
  /// "you're signed out now" signal OSM's OAuth tokens give, since they
  /// don't expire on a schedule Steward can predict ahead of time.
  bool get isUnauthorized => statusCode == 401;

  @override
  String toString() => message;
}

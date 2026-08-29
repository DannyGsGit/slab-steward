import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'oauth_popup.dart';
import 'oauth_storage.dart';
import 'osm_api.dart';
import 'osm_environment.dart';
import 'pkce.dart';

/// The scopes the sign-in flow requests. `write_api` covers changeset
/// creation and comments; `write_notes` is requested now — even though
/// there's no note-leaving feature yet — so that feature won't need a
/// second consent screen later. See
/// docs/specs/slab-steward-osm-changeset-spec.md §1 for why each is needed.
const _scope = 'read_prefs write_api write_notes';

/// Sign-in state for the rider's own OSM account, via OAuth 2.0
/// Authorization Code + PKCE — no client secret, since a browser has nowhere
/// safe to keep one. One instance lives for the app's lifetime, held by
/// [StewardState].
class OsmAuthState extends ChangeNotifier {
  OsmAuthState({http.Client? client, String? clientId})
    : _client = client ?? http.Client(),
      clientId = clientId ?? osmClientId;

  final http.Client _client;

  /// The OAuth client id, compiled in at build time. See [osmClientId] and
  /// the README's "OSM API environment".
  final String clientId;

  static const _tokenKey = 'osm_oauth_token';
  static const _identityKey = 'osm_oauth_identity';

  String? _accessToken;
  OsmIdentity? _identity;
  bool _isSigningIn = false;

  String? get bearerToken => _accessToken;
  OsmIdentity? get identity => _identity;
  bool get isSignedIn => _accessToken != null;
  bool get isSigningIn => _isSigningIn;

  /// Loads a cached session from local storage, if there is one, so the
  /// rider isn't asked to sign in again on every page load. Trusts the
  /// cache rather than re-verifying it up front — a token that's actually
  /// been revoked surfaces the first time it's used for a real call, via
  /// [clearOnUnauthorized].
  void restoreSession() {
    final token = readStorage(_tokenKey);
    final identityJson = readStorage(_identityKey);
    if (token == null || identityJson == null) return;
    _accessToken = token;
    _identity = OsmIdentity.fromJson(
      jsonDecode(identityJson) as Map<String, Object?>,
    );
    notifyListeners();
  }

  /// Opens the OSM authorize page in a popup, exchanges the resulting code
  /// for a token, and resolves the rider's display name. Throws (a
  /// [StateError] or [OAuthPopupCancelled]) rather than leaving [isSignedIn]
  /// in a half-true state on failure.
  Future<void> signIn() async {
    if (clientId.isEmpty) {
      throw StateError(
        'No OSM client id compiled in. Run via tool/run.sh, or pass '
        '--dart-define=OSM_CLIENT_ID=... — see the README\'s "OSM API '
        'environment" section.',
      );
    }
    _isSigningIn = true;
    notifyListeners();
    try {
      final verifier = generateCodeVerifier();
      final challenge = codeChallengeFor(verifier);
      final requestState = generateState();
      // Always the origin root, never the current path: OSM matches redirect
      // URIs exactly against the registered list, and Firebase Hosting
      // rewrites every path to index.html — so a rider who deep-linked to
      // /something would otherwise send an unregistered URI and be rejected.
      final redirectUri = '${Uri.base.origin}/';

      // Authorize and token live on the *website* host, not the API host —
      // genuinely different machines. See osmWebHost.
      final authorizeUrl = Uri.parse('$osmWebHost/oauth2/authorize').replace(
        queryParameters: {
          'client_id': clientId,
          'redirect_uri': redirectUri,
          'response_type': 'code',
          'scope': _scope,
          'state': requestState,
          'code_challenge': challenge,
          'code_challenge_method': 'S256',
        },
      );

      final result = await runOAuthPopup(authorizeUrl);
      if (result.error != null) {
        throw StateError(
          'OpenStreetMap sign-in was not granted: ${result.error}',
        );
      }
      if (result.state != requestState) {
        throw StateError(
          'Sign-in response did not match the request that started it.',
        );
      }
      final code = result.code;
      if (code == null) {
        throw StateError('OpenStreetMap did not return an authorization code.');
      }

      final token = await _exchangeCode(
        code: code,
        verifier: verifier,
        redirectUri: redirectUri,
      );
      final identity = await OsmApi(
        client: _client,
      ).fetchUserDetails(bearerToken: token);

      _accessToken = token;
      _identity = identity;
      writeStorage(_tokenKey, token);
      writeStorage(_identityKey, jsonEncode(identity.toJson()));
    } finally {
      _isSigningIn = false;
      notifyListeners();
    }
  }

  Future<String> _exchangeCode({
    required String code,
    required String verifier,
    required String redirectUri,
  }) async {
    final response = await _client.post(
      Uri.parse('$osmWebHost/oauth2/token'),
      body: {
        'grant_type': 'authorization_code',
        'client_id': clientId,
        'redirect_uri': redirectUri,
        'code': code,
        'code_verifier': verifier,
      },
    );
    if (response.statusCode != 200) {
      throw StateError(
        'OpenStreetMap rejected the sign-in (${response.statusCode}).',
      );
    }
    final body = jsonDecode(response.body) as Map<String, Object?>;
    return body['access_token'] as String;
  }

  /// Abandons an in-flight [signIn]. The popup can't be closed from here —
  /// COOP severs the handle — so this just stops waiting; the rider closes
  /// the window themselves.
  void cancelSignIn() {
    if (_isSigningIn) cancelOAuthPopup();
  }

  void signOut() {
    if (!isSignedIn) return;
    _accessToken = null;
    _identity = null;
    removeStorage(_tokenKey);
    removeStorage(_identityKey);
    notifyListeners();
  }

  /// Called after an OSM API call comes back 401 — the stored token is no
  /// longer good for anything, so drop it rather than let the rider hit a
  /// silent dead end on the next attempt.
  void clearOnUnauthorized() => signOut();

  /// Seeds a signed-in session directly, bypassing the popup — for tests
  /// that need [isSignedIn] and [bearerToken] without a browser to open a
  /// popup in.
  @visibleForTesting
  void debugSignIn({required String token, required OsmIdentity identity}) {
    _accessToken = token;
    _identity = identity;
    notifyListeners();
  }

  @override
  void dispose() {
    _client.close();
    super.dispose();
  }
}

import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

/// PKCE (RFC 7636) helpers for the OAuth 2.0 authorization code flow — the
/// only flow a browser-only client can use safely, since there's nowhere to
/// keep a client secret.
final _random = Random.secure();

/// 32 secure-random bytes, base64url-encoded with padding stripped: 43
/// characters, satisfying RFC 7636's 43-128 char minimum without needing to
/// pick a length.
String _randomToken() {
  final bytes = List<int>.generate(32, (_) => _random.nextInt(256));
  return base64UrlEncode(bytes).replaceAll('=', '');
}

/// The PKCE code verifier — kept client-side, never sent until the token
/// exchange, which is what makes the auth code alone useless to an attacker
/// who intercepts the redirect.
String generateCodeVerifier() => _randomToken();

/// The PKCE code challenge sent with the authorize request: base64url(SHA-256(verifier)).
String codeChallengeFor(String verifier) {
  final digest = sha256.convert(utf8.encode(verifier));
  return base64UrlEncode(digest.bytes).replaceAll('=', '');
}

/// A CSRF token echoed back by OSM on redirect, so the popup's response can
/// be matched to the request that opened it.
String generateState() => _randomToken();

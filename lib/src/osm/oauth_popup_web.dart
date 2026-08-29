import 'dart:async';
import 'dart:convert';

import 'package:web/web.dart' as web;

import 'oauth_popup.dart';
import 'oauth_storage.dart';

/// How long to wait for the rider to finish authorizing before giving up.
/// Generous: they may have to create an account, or find their password.
const _timeout = Duration(minutes: 5);
const _pollInterval = Duration(milliseconds: 250);

/// Set by [cancelOAuthPopup]. Module-level rather than passed in because the
/// only caller that can cancel is the one already awaiting this future.
bool _cancelRequested = false;

/// Abandons an in-flight sign-in. The popup itself is not closed — a
/// COOP-severed handle can't be closed from here — so the rider closes it,
/// and any result it later writes is discarded on the next attempt.
void cancelOAuthPopup() => _cancelRequested = true;

/// Opens [authorizeUrl] in a popup and waits for the redirect page to leave
/// its result in localStorage. See [oauthResultKey] for why the handshake
/// works this way rather than through `postMessage`.
Future<OAuthPopupResult> runOAuthPopup(Uri authorizeUrl) async {
  // A result left behind by an abandoned attempt would otherwise be picked
  // up instantly as though it belonged to this one.
  removeStorage(oauthResultKey);
  _cancelRequested = false;

  final popup = web.window.open(
    authorizeUrl.toString(),
    'osm-oauth',
    'width=620,height=760',
  );
  if (popup == null) {
    throw StateError(
      "Couldn't open the sign-in window — check your browser's popup blocker.",
    );
  }

  final deadline = DateTime.now().add(_timeout);
  while (DateTime.now().isBefore(deadline)) {
    if (_cancelRequested) {
      removeStorage(oauthResultKey);
      throw const OAuthPopupCancelled();
    }

    final raw = readStorage(oauthResultKey);
    if (raw != null) {
      removeStorage(oauthResultKey);
      final payload = jsonDecode(raw) as Map<String, Object?>;
      return OAuthPopupResult(
        code: payload['code'] as String?,
        state: payload['state'] as String?,
        error: payload['error'] as String?,
      );
    }

    await Future<void>.delayed(_pollInterval);
  }

  removeStorage(oauthResultKey);
  throw StateError(
    'Timed out waiting for OpenStreetMap sign-in. If the window is still '
    'open, close it and try again.',
  );
}

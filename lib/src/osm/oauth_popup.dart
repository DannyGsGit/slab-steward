// Drives the OAuth 2.0 authorize step in a popup window and waits for the
// redirect page's result.
//
// Web is the only platform Steward ships to (see README), so the web version
// below is the real implementation, and the io stub only exists so
// `flutter test` — which runs on the Dart VM, never a browser — can link
// against this file without a browser to open a popup in.
export 'oauth_popup_web.dart' if (dart.library.io) 'oauth_popup_io.dart';

/// Where the popup leaves its result for the window that opened it.
///
/// **Why localStorage and not `postMessage`.** OSM serves its pages with
/// `Cross-Origin-Opener-Policy: same-origin`. The moment the popup navigates
/// to OSM the browser severs the opener relationship, so by the time the
/// popup lands back on our origin `window.opener` is null, `postMessage` has
/// nowhere to go, and the opener's handle reports the popup as already
/// closed. localStorage is shared by every same-origin document regardless,
/// which makes it the one channel COOP leaves intact.
const oauthResultKey = 'osm_oauth_pending_result';

/// What the popup reported: either an authorization [code] and the [state]
/// it was opened with, or an [error] OSM returned instead (the rider denied
/// access, or something went wrong on OSM's side).
class OAuthPopupResult {
  const OAuthPopupResult({this.code, this.state, this.error});

  final String? code;
  final String? state;
  final String? error;
}

/// Thrown when the rider closes the popup before it reports back.
class OAuthPopupCancelled implements Exception {
  const OAuthPopupCancelled();

  @override
  String toString() => 'Sign-in was cancelled.';
}

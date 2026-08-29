import 'oauth_popup.dart';

/// Never reached off the web — see `oauth_popup.dart` for why this stub
/// exists at all.
Future<OAuthPopupResult> runOAuthPopup(Uri authorizeUrl) {
  throw UnsupportedError('OSM sign-in is only available in a browser.');
}

void cancelOAuthPopup() {}

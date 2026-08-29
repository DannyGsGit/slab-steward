// The popup-side half of the OAuth handshake: when the popup that
// `oauth_popup.dart` opened gets redirected back to us by OSM, the app boots
// fresh in that popup (same URL Steward is always served from — there is no
// separate static callback page, since `firebase.json` rewrites every path
// to `index.html` anyway). `tryHandleOAuthCallback` recognizes that
// situation at startup, hands the result to the opener via `postMessage`,
// and closes the popup instead of building the normal UI.
//
// Web-only, same conditional-export split as `changeset_download.dart` and
// `oauth_popup.dart` — `flutter test` runs on the Dart VM, never a browser.
export 'oauth_callback_web.dart' if (dart.library.io) 'oauth_callback_io.dart';

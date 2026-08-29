// Where the OSM access token and cached identity live between page loads.
//
// Web-only (real browser storage); the io stub backs it with an in-memory
// map purely so this file links under `flutter test`, which never persists
// anything across runs anyway — tests seed a session via
// `OsmAuthState.debugSignIn` instead of going through storage at all.
export 'oauth_storage_web.dart' if (dart.library.io) 'oauth_storage_io.dart';

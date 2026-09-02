// The analytics sink, chosen per platform — the same shape the OAuth helpers
// use (`oauth_storage.dart`, `oauth_popup.dart`, `oauth_callback.dart`).
//
// Web talks to PostHog. The io side records events in memory and sends
// nothing, which is what `flutter test` links against and what any future
// `flutter create --platforms=ios,android` would get until there's a native
// SDK worth wiring up. Callers never branch on which one they got.
//
// Both files declare the *same* public API, including the debug recorder, so
// the analyzer resolves either branch — see analytics_stub.dart's note.
export 'analytics_web.dart' if (dart.library.io) 'analytics_stub.dart';

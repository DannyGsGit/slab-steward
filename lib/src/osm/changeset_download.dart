// Saves a rendered changeset preview somewhere the rider can read it back.
//
// Web is the only platform Steward ships to, so the web downloader below is
// the fallback, and the dart:io writer only takes over under `flutter test`
// — no browser to download into there, but a real filesystem to write to
// instead, which a test can then assert against.
export 'changeset_download_web.dart'
    if (dart.library.io) 'changeset_download_io.dart';

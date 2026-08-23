import 'dart:io';

/// Writes [content] straight to `osm_api_calls/[filename]` relative to
/// wherever the process is running (the project root under `flutter test`).
/// Selected instead of the web downloader whenever `dart:io` is available —
/// see `changeset_download.dart`.
String saveChangesetPreview(String filename, String content) {
  final file = File('osm_api_calls/$filename');
  file.parent.createSync(recursive: true);
  file.writeAsStringSync(content);
  return file.path;
}

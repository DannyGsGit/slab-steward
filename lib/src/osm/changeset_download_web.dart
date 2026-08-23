import 'dart:js_interop';

import 'package:web/web.dart' as web;

/// Triggers a browser download of [content] as [filename].
///
/// A page can't pick where a download lands — that's the browser's call, per
/// its own download settings — so this can only suggest the name, not the
/// `osm_api_calls/` folder the caller asks for. Chrome does honor a `/` in
/// the suggested name by nesting it under the default downloads folder;
/// other browsers may flatten it to a bare filename instead.
String saveChangesetPreview(String filename, String content) {
  final blob = web.Blob(
    [content.toJS].toJS,
    web.BlobPropertyBag(type: 'text/plain;charset=utf-8'),
  );
  final url = web.URL.createObjectURL(blob);
  final anchor = web.document.createElement('a') as web.HTMLAnchorElement
    ..href = url
    ..download = filename;
  web.document.body!.appendChild(anchor);
  anchor.click();
  anchor.remove();
  web.URL.revokeObjectURL(url);
  return 'your browser\'s downloads, as $filename';
}

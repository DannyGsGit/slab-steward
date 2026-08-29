import 'package:web/web.dart' as web;

/// Chosen over sessionStorage or memory-only: a rider who signs in once
/// shouldn't have to again just because they closed the tab. The tradeoff —
/// a bearer token sitting in browser storage for longer than a session — was
/// a deliberate call, not an oversight; see the product description §11.
String? readStorage(String key) => web.window.localStorage.getItem(key);

void writeStorage(String key, String value) =>
    web.window.localStorage.setItem(key, value);

void removeStorage(String key) => web.window.localStorage.removeItem(key);

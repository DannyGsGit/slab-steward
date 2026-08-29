import 'dart:convert';

import 'package:web/web.dart' as web;

import 'oauth_popup.dart';
import 'oauth_storage.dart';

/// If this page load is the OAuth redirect landing back on our origin, leaves
/// the result where the opener will find it and closes the window. Returns
/// true when that happened, so `main()` can skip building the app.
///
/// Deliberately does **not** consult `window.opener`: OSM's
/// `Cross-Origin-Opener-Policy: same-origin` guarantees it will be null here
/// (see [oauthResultKey]). The presence of OAuth parameters in the URL is the
/// only signal available, and the only one needed — nothing else navigates
/// this app to `?code=`.
bool tryHandleOAuthCallback() {
  final params = Uri.base.queryParameters;
  final code = params['code'];
  final error = params['error'];
  if (code == null && error == null) return false;

  writeStorage(
    oauthResultKey,
    jsonEncode({'code': code, 'state': params['state'], 'error': error}),
  );

  // Also severed by COOP, so this may be refused; the message below is what
  // the rider sees when it is.
  web.window.close();
  _showClosableMessage(
    error == null
        ? 'Signed in. You can close this window.'
        : 'Sign-in was not completed: $error',
  );
  return true;
}

/// Replaces the blank page with something readable, for the case where the
/// browser won't let this window close itself.
void _showClosableMessage(String message) {
  final body = web.document.body;
  if (body == null) return;
  body
    ..textContent = ''
    ..setAttribute(
      'style',
      'margin:0;display:flex;align-items:center;justify-content:center;'
          'height:100vh;font:16px/1.5 system-ui,sans-serif;color:#4F2E28;'
          'background:#FDFBF8;text-align:center;padding:24px',
    );
  final p = web.document.createElement('p')..textContent = message;
  body.appendChild(p);
}

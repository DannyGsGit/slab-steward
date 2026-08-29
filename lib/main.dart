import 'package:flutter/material.dart';

import 'src/osm/oauth_callback.dart';
import 'src/steward_app.dart';

void main() {
  // This load might be the OAuth popup OSM just redirected back to, rather
  // than a normal app open — see oauth_callback.dart. If so, hand the result
  // to the opener and stop here instead of building the whole app in the
  // popup.
  if (tryHandleOAuthCallback()) return;

  runApp(const StewardApp());
}

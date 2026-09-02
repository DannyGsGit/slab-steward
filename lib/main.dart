import 'package:flutter/material.dart';

import 'src/analytics/analytics.dart';
import 'src/analytics/analytics_environment.dart';
import 'src/analytics/steward_events.dart';
import 'src/osm/oauth_callback.dart';
import 'src/osm/osm_environment.dart';
import 'src/steward_app.dart';

void main() {
  // This load might be the OAuth popup OSM just redirected back to, rather
  // than a normal app open — see oauth_callback.dart. If so, hand the result
  // to the opener and stop here instead of building the whole app in the
  // popup.
  //
  // Analytics starts *after* this check, and deliberately: the popup is a
  // second page load of the same app, and counting it would put a phantom
  // `app_opened` in the funnel for every rider who signs in — inflating the
  // top of the funnel with exactly the people who got furthest down it.
  if (tryHandleOAuthCallback()) return;

  initAnalytics(
    apiKey: posthogApiKey,
    apiHost: posthogApiHost,
    // On every event: what this build would actually do with a submission is
    // worth knowing permanently. It does not separate development from
    // production while osmEnvironment is `live` — it is true in both — so
    // excluding your own traffic is a `$host` filter's job, not this.
    superProperties: {'writes_to_osm': osmEnvironment.writesToOsm},
  );
  trackAppOpened();

  runApp(const StewardApp());
}

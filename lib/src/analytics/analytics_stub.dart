import 'package:flutter/foundation.dart';

import 'analytics_event.dart';

export 'analytics_event.dart';

/// The non-web sink: records what would have been sent and sends nothing.
///
/// This is what `flutter test` links against, which makes it the assertion
/// surface for the instrumentation tests — a test can stage an edit and then
/// read back that `edit_staged` was captured with the right properties,
/// without a browser or a network. It is also what a future native build
/// would get; recording into a bounded list is the right no-op there too.
final List<AnalyticsEvent> _events = [];

/// Bounded for the same reason the web queue is: a long-lived native session
/// must not accumulate events nobody will ever read.
const _maxRecorded = 1000;

void initAnalytics({
  required String apiKey,
  required String apiHost,
  Map<String, Object?> superProperties = const {},
}) {
  captureEvent('_init', {
    'has_key': apiKey.isNotEmpty,
    'api_host': apiHost,
    ...superProperties,
  });
}

void captureEvent(String event, [Map<String, Object?> properties = const {}]) {
  if (_events.length >= _maxRecorded) return;
  _events.add(AnalyticsEvent(event, properties));
}

void identifyRider(String distinctId) =>
    captureEvent('_identify', {'distinct_id': distinctId});

void resetAnalytics() => captureEvent('_reset');

/// Everything captured so far, oldest first. Underscore-prefixed names are
/// lifecycle records the web side handles through PostHog's own API rather
/// than as events; the rider-facing events of docs/specs/analytics.md §2
/// carry their real names.
@visibleForTesting
List<AnalyticsEvent> get debugAnalyticsEvents => List.unmodifiable(_events);

@visibleForTesting
void debugClearAnalytics() => _events.clear();

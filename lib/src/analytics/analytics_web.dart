import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

import 'analytics_event.dart';

export 'analytics_event.dart';

@JS('posthog')
external JSObject? get _posthog;

/// Whether [initAnalytics] found a key and got the library loaded. Until it
/// does, captured events wait in [_pending] rather than being dropped — the
/// very first event (`app_opened`) is fired before any network round trip
/// could possibly have finished.
bool _ready = false;

/// Set when there is no key, or the library failed to load — an ad blocker,
/// an offline tab, a bad host. Everything after it is a no-op, quietly: an
/// analytics failure must never be something the rider can see.
bool _disabled = false;

/// Bounded on purpose. If the library never loads, this holds a session's
/// worth of closures forever; a cap keeps that from growing without limit in
/// a tab left open for a day.
final _pending = <void Function()>[];
const _maxPending = 100;

/// Loads the PostHog browser library from [apiHost] and configures it.
///
/// Nothing about PostHog appears in `web/index.html` — no snippet, no key,
/// no host. The library is fetched from here instead, which keeps the region
/// and the key single-sourced from `secrets/vault.env` (see
/// `analytics_environment.dart`) and keeps a third-party script off the critical path to
/// first paint.
void initAnalytics({
  required String apiKey,
  required String apiHost,
  Map<String, Object?> superProperties = const {},
}) {
  if (apiKey.isEmpty) {
    _disabled = true;
    return;
  }

  final script = web.document.createElement('script') as web.HTMLScriptElement
    ..src = '$apiHost/static/array.js'
    ..async = true;

  script.addEventListener(
    'load',
    ((web.Event _) {
      final posthog = _posthog;
      if (posthog == null) {
        _disabled = true;
        _pending.clear();
        return;
      }
      posthog.callMethod(
        'init'.toJS,
        apiKey.toJS,
        {
          'api_host': apiHost,
          // Every one of these is off because Flutter web draws to a canvas
          // and there is no DOM to observe — see docs/specs/analytics.md §0.
          // Left on, they would cost bandwidth to report one pageview and
          // nothing else.
          'autocapture': false,
          'capture_pageview': false,
          'capture_pageleave': false,
          'disable_session_recording': true,
          // A person profile only for riders who signed in to OSM. Everyone
          // else stays an anonymous funnel step.
          'person_profiles': 'identified_only',
        }.jsify(),
      );
      if (superProperties.isNotEmpty) {
        posthog.callMethod('register'.toJS, superProperties.jsify());
      }
      _ready = true;
      for (final send in _pending) {
        send();
      }
      _pending.clear();
    }).toJS,
  );

  script.addEventListener(
    'error',
    ((web.Event _) {
      _disabled = true;
      _pending.clear();
    }).toJS,
  );

  web.document.head!.appendChild(script);
}

void captureEvent(String event, [Map<String, Object?> properties = const {}]) =>
    _send(() {
      _posthog?.callMethod('capture'.toJS, event.toJS, properties.jsify());
    });

/// Ties everything this browser has done to one OSM account.
///
/// The distinct id is the OSM *numeric* user id, not the display name: it's
/// stable across renames, and it's the id the changesets carry anyway.
void identifyRider(String distinctId) =>
    _send(() => _posthog?.callMethod('identify'.toJS, distinctId.toJS));

/// Drops the identity on sign-out, so a second rider signing in on the same
/// browser starts a new person rather than being merged into the first.
void resetAnalytics() => _send(() => _posthog?.callMethod('reset'.toJS));

void _send(void Function() action) {
  if (_disabled) return;
  if (_ready) {
    action();
    return;
  }
  if (_pending.length < _maxPending) _pending.add(action);
}

/// Always empty on web — events go to PostHog, not to a list. Declared so
/// this file and analytics_stub.dart present the same API to the analyzer
/// whichever branch of the conditional export it resolves.
List<AnalyticsEvent> get debugAnalyticsEvents => const [];

void debugClearAnalytics() {}

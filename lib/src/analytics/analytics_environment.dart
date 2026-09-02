/// Where product analytics goes, and whether it goes anywhere at all — **the
/// one place to change it.** Deliberately its own file, importing nothing, so
/// `main` and the platform implementations can read it without an import
/// cycle, exactly as `osm_environment.dart` is arranged.
library;

/// PostHog's project API key, supplied at build time via `--dart-define`
/// (empty when it wasn't).
///
/// Not a secret. It ships to every browser and is readable in devtools, the
/// same way `osmClientId` is — a *publishable* key is what PostHog's browser
/// SDK is designed around. It's kept out of source for the same reason the
/// client id is: it's a per-deployment id, and the project already has one
/// gitignored place for those (`secrets/vault.env`, read by `tool/run.sh`).
///
/// **Empty disables analytics entirely** — no script fetched, no events
/// queued, no network at all. That is what keeps `flutter test` and a bare
/// `flutter run` from writing development traffic into the funnel.
const posthogApiKey = String.fromEnvironment('POSTHOG_API_KEY');

/// PostHog's ingestion host, and the origin the browser library itself is
/// loaded from.
///
/// The region baked into this value is the one setting that can't be changed
/// later without standing up a new PostHog project — see
/// docs/specs/analytics.md §3.
const posthogApiHost = String.fromEnvironment(
  'POSTHOG_API_HOST',
  defaultValue: 'https://us.i.posthog.com',
);

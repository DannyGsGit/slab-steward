/// Where Steward talks to OpenStreetMap, and whether this build actually
/// commits — **the one place to change it.** Deliberately its own file,
/// importing nothing, so every layer (API client, OAuth, permalinks, the
/// submission gate) can read it without an import cycle.
///
/// There is only one OpenStreetMap here. Steward used to point a whole
/// configuration at OSM's dev sandbox, but that sandbox is a *separate
/// database* holding none of the trails the map draws: every read 404'd until
/// a seeder had copied a park into it, real way ids meant nothing, and what
/// you exercised was never quite the thing that would ship. Both
/// configurations below now use the production hosts, the production OAuth
/// app, and real trail data.
///
/// See the README's "OSM API environment" section for the full picture.
library;

/// Host for `/api/0.6/...` calls — reads and changeset writes alike.
const osmApiHost = 'https://api.openstreetmap.org';

/// Host for the *website*: OAuth's `/oauth2/authorize` and `/oauth2/token`,
/// and the human-facing `/way/{id}` and `/changeset/{id}` permalinks.
///
/// A genuinely different machine from [osmApiHost], which is why this is a
/// second constant rather than a path off the first.
const osmWebHost = 'https://www.openstreetmap.org';

/// The OAuth app's client id, supplied at build time via `--dart-define`
/// (empty when it wasn't).
///
/// A client id is not a secret — it's public by design in an Authorization
/// Code + PKCE flow, and ends up in the authorize URL either way — but it is
/// per-app, so it's kept out of source. The value lives in the gitignored
/// `secrets/vault.env`; `tool/run.sh` reads it out and passes it. See the
/// README.
///
/// The matching client *secret* is deliberately unused: this is a public
/// client with nowhere to keep one, which is exactly what PKCE is for.
const osmClientId = String.fromEnvironment('OSM_CLIENT_ID');

/// What to call the map in a sentence, so a rider is never unsure what they
/// just edited.
const osmLabel = 'OpenStreetMap';

/// The same, short enough for a chip in the map chrome.
const osmShortLabel = 'openstreetmap.org';

/// The two configurations Steward ships in. They differ in exactly one way:
/// whether a submission's last three API calls are made.
enum OsmEnvironment {
  /// The full commitment path. The changeset is opened, uploaded and closed
  /// for real — the edit is live, immediately, and permanent.
  live(writesToOsm: true),

  /// Identical right up to the point of no return, and then it simply doesn't
  /// happen. Same hosts, same OAuth app, same authoritative reads, same
  /// conflict gate, same screens, same staging cleared afterwards — only the
  /// open/upload/close calls are skipped.
  ///
  /// This is what development runs against: everything worth exercising is
  /// exercised, against the real trails the map draws, with nothing left
  /// behind on the map to clean up.
  dryRun(writesToOsm: false);

  const OsmEnvironment({required this.writesToOsm});

  /// Whether `SubmissionGate.submit` writes the changeset or stops short.
  final bool writesToOsm;
}

/// **The switch.**
///
/// Currently [OsmEnvironment.dryRun], on purpose: day-to-day work must not be
/// able to leave edits on the real map.
///
/// Flip to [OsmEnvironment.live] only once the Organised Editing Guidelines
/// wiki page and the two-week community notice are live — see
/// docs/slab-steward-osm-changeset-spec.md §9-10. Nothing else about the
/// build changes; the same OAuth app and the same reads serve both.
const osmEnvironment = OsmEnvironment.dryRun;

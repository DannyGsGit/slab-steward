import 'package:flutter/material.dart';

/// SLAB's e-bike permission picker and its mapping onto OSM
/// `electric_bicycle=*`.
///
/// See https://wiki.openstreetmap.org/wiki/Key:electric_bicycle. The key is an
/// access key like any other — `bicycle=*` with the e-bike carve-out made
/// explicit — so the full access vocabulary is available to it. Steward offers
/// two values of that vocabulary and no more.
///
/// Three things worth knowing:
///
///  * '''Yes and no only.''' `designated` and `permissive` are real and
///    correct on some trails, but neither is something a rider can read off a
///    sign without interpreting it: `designated` means the trail is built or
///    signposted *for* e-bikes rather than merely open to them, and
///    `permissive` is a claim about a landowner's intent. A picker that offers
///    a choice its user cannot reliably make collects confident wrong answers,
///    which is worse for the map than a narrower question answered well.
///  * `electric_bicycle` is a *sub-class* of `bicycle`, so both options are
///    about e-bikes specifically: "allowed" does not mean the trail allows
///    bikes, and "not allowed" can be true on a trail that welcomes them. Each
///    option carries a [description] saying so, shown while choosing.
///  * It covers pedelecs — motor assists while pedalling, cut off around
///    25 km/h. Faster machines are `speed_pedelec=*`, which Steward does not
///    write.
enum EbikeAccess {
  allowed(
    'Allowed',
    'yes',
    'E-bikes may ride here, the same as any other bike.',
  ),
  notAllowed(
    'Not allowed',
    'no',
    'E-bikes are shut out of this trail, whether or not regular bikes are.',
  );

  const EbikeAccess(this.label, this.osmValue, this.description);

  final String label;

  /// The `electric_bicycle` value this writes.
  final String osmValue;

  /// One line saying what this option actually claims about the trail. Shown
  /// beside the option in the picker, and under the picker once it's chosen:
  /// this key is about e-bikes alone, and a bare "allowed" doesn't say that.
  final String description;

  /// The one OSM key this picker reads and writes.
  static const osmKey = 'electric_bicycle';

  /// Everything a rider can pick. Absence of the tag is the "not recorded"
  /// state and is deliberately not an option — clearing an access tag someone
  /// else set is a destructive edit dressed up as a dropdown entry, the same
  /// reason the difficulty picker leaves out "un-rated".
  static List<EbikeAccess> get selectable => values;

  /// What to say while the field is still empty.
  static const pickerNote =
      'Answer from the trailhead sign or the land manager\'s rules — not from '
      'what riders do.';

  /// Resolves a raw OSM `electric_bicycle` value to a SLAB option.
  ///
  /// Returns null for everything else in the access vocabulary —
  /// `designated`, `permissive`, `destination`, `private` and friends are all
  /// real values on real paths. The panel shows those raw and read-only rather
  /// than calling them missing, and never quietly flattens one into "allowed":
  /// a value Steward can't offer is still a value somebody meant.
  static EbikeAccess? fromOsm(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    return switch (raw.trim()) {
      'yes' => EbikeAccess.allowed,
      'no' => EbikeAccess.notAllowed,
      _ => null,
    };
  }
}

/// The glyph for an e-bike permission: the same allowed / not-allowed reading
/// a rider gets off a sign, in the one place the picker shows a value.
class EbikeIcon extends StatelessWidget {
  const EbikeIcon(this.access, {super.key, this.size = 16});

  /// Null draws the "not recorded" outline.
  final EbikeAccess? access;
  final double size;

  @override
  Widget build(BuildContext context) {
    final (icon, color) = switch (access) {
      EbikeAccess.allowed => (Icons.electric_bike, const Color(0xFF2E9E4F)),
      EbikeAccess.notAllowed => (
        Icons.do_not_disturb_on_outlined,
        const Color(0xFFB3261E),
      ),
      null => (Icons.electric_bike_outlined, null),
    };
    return Icon(
      icon,
      size: size,
      color: color ?? Theme.of(context).textTheme.bodySmall?.color,
    );
  }
}

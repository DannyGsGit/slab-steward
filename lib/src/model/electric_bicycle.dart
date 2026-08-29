import 'package:flutter/material.dart';

import '../ui/slab_theme.dart';
import 'ebike_class.dart';

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
///  * '''Which e-bike is a separate question.''' The bottom rung of a
///    jurisdiction's ladder — a Class 1, a pedelec, a snorfiets — and the
///    faster machines above it each ride under a key of their own. Which rung
///    a rider is answering about is [EbikeJurisdiction]'s job, asked by its
///    own picker once this one says yes. This enum is only "may they, or may
///    they not".
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
  ///
  /// Deliberately says nothing about *which* class. This picker answers one
  /// question — may they ride, or may they not — and the class is the next
  /// question, asked by [EbikeJurisdiction]'s own picker and only once the
  /// answer here is yes. Folding the two together made "Allowed" read as a
  /// claim about Class 1 before the rider had said anything about classes.
  final String description;

  /// The one OSM key this picker reads and writes.
  static const osmKey = 'electric_bicycle';

  /// Everything a rider can pick. Absence of the tag is the "not recorded"
  /// state and is deliberately not an option — clearing an access tag someone
  /// else set is a destructive edit dressed up as a dropdown entry, the same
  /// reason the difficulty picker leaves out "un-rated".
  static List<EbikeAccess> get selectable => values;

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
///
/// A lightning bolt rather than a bicycle, because the key is about the motor
/// and not the bike — and because at 14px beside a difficulty glyph a bolt
/// still reads as a bolt where a bicycle turns to mush. "Not allowed" wears
/// the signage slash over it, so the two options differ in shape and not in
/// colour alone.
class EbikeIcon extends StatelessWidget {
  const EbikeIcon(this.access, {super.key, this.size = 16});

  /// Null draws the bolt in the muted body colour: nothing recorded yet, so
  /// neither the green nor the red claim is being made.
  final EbikeAccess? access;
  final double size;

  /// SLAB's own two: the green it paints an easy trail, and the one accent
  /// the design system reserves for "no" — see `slab_theme.dart`.
  static const _allowedColor = SlabColors.diffEasy;
  static const _notAllowedColor = SlabColors.rust;

  @override
  Widget build(BuildContext context) {
    final color = switch (access) {
      EbikeAccess.allowed => _allowedColor,
      EbikeAccess.notAllowed => _notAllowedColor,
      null => Theme.of(context).textTheme.bodySmall?.color ?? Colors.black54,
    };
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Icon(Icons.bolt, size: size, color: color),
          if (access == EbikeAccess.notAllowed)
            CustomPaint(
              size: Size.square(size),
              painter: _SlashPainter(_notAllowedColor),
            ),
        ],
      ),
    );
  }
}

/// The prohibition slash, top-left to bottom-right the way signage draws it.
///
/// Painted twice: an ink line underneath so the slash stays visible where it
/// crosses the bolt, and the rust one on top of that.
class _SlashPainter extends CustomPainter {
  _SlashPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final start = Offset(size.width * 0.16, size.height * 0.16);
    final end = Offset(size.width * 0.84, size.height * 0.84);
    canvas.drawLine(
      start,
      end,
      Paint()
        ..color = SlabColors.ink950
        ..strokeCap = StrokeCap.round
        ..strokeWidth = size.shortestSide * 0.19,
    );
    canvas.drawLine(
      start,
      end,
      Paint()
        ..color = color
        ..strokeCap = StrokeCap.round
        ..strokeWidth = size.shortestSide * 0.11,
    );
  }

  @override
  bool shouldRepaint(_SlashPainter oldDelegate) => oldDelegate.color != color;
}

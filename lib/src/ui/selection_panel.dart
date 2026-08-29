import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../model/difficulty.dart';
import '../model/ebike_class.dart';
import '../model/electric_bicycle.dart';
import '../model/staged_edit.dart';
import '../model/trail.dart';
import '../state/steward_state.dart';
import 'fields.dart';

/// The bulk editor: one guided value per attribute, applied across every trail
/// in the working set.
///
/// Per-trail overrides are deliberately not offered here — product description
/// §4. A batch that needs different values per trail is two batches, not a
/// spreadsheet. What the batch *does* produce is one staged edit per trail, so
/// the review list can show, prune and explain each one on its own.
///
/// Lives in the sidebar's Selection pane, which supplies the heading and the
/// close control.
class SelectionPanel extends StatefulWidget {
  const SelectionPanel({super.key, required this.state});

  final StewardState state;

  @override
  State<SelectionPanel> createState() => _SelectionPanelState();
}

/// What one attribute's application did, in the words the report needs:
/// which field, what it was set to, and how the batch actually landed.
typedef _Applied = ({String attribute, String value, BatchResult result});

class _SelectionPanelState extends State<SelectionPanel> {
  Difficulty? _difficulty;
  EbikeAccess? _ebike;

  /// The class cap the rider picked, when they picked one. Null falls back to
  /// [_jurisdiction]'s own cap, which is what almost every batch uses.
  EbikeClass? _cap;

  /// Non-null while authoritative tags are being read: `(done, total)`.
  (int, int)? _progress;
  bool _isApplying = false;
  List<_Applied>? _report;

  /// The trails [_report] describes. A report is only true of the selection it
  /// was produced from, so it's dropped once that selection changes — but not
  /// merely because the panel rebuilt, which staging itself causes.
  Set<int>? _reportedOn;

  @override
  void didUpdateWidget(SelectionPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_report == null || _isApplying) return;
    if (setEquals(_reportedOn, _selectedIds)) return;
    setState(() {
      _report = null;
      _reportedOn = null;
    });
  }

  Set<int> get _selectedIds => {
    for (final trail in widget.state.selectedTrails) trail.osmWayId,
  };

  /// The vocabulary the batch is written in: the one every selected trail
  /// shares, or the neutral one when a selection straddles a border. A batch
  /// spanning two jurisdictions is answered in the words both agree on rather
  /// than in whichever trail happened to be clicked first.
  EbikeJurisdiction get _jurisdiction {
    final found = <EbikeJurisdiction>{
      for (final trail in widget.state.selectedTrails) trail.ebikeJurisdiction,
    };
    return found.length == 1 ? found.single : EbikeJurisdiction.elsewhere;
  }

  /// Whether there is anything to stage — either picker having a value is
  /// enough, and a batch that sets both fields is still one pass over the
  /// selection.
  bool get _hasDraft => _difficulty != null || _ebike != null;

  Future<void> _apply() async {
    if (!_hasDraft || _isApplying) return;

    setState(() {
      _isApplying = true;
      _report = null;
    });
    // Nothing is composed against tile data, in bulk any more than singly: a
    // changeset built on a stale version clobbers someone else's edit.
    await widget.state.resolveSelection(
      onProgress: (done, total) {
        if (mounted) setState(() => _progress = (done, total));
      },
    );
    if (!mounted) return;

    final trails = widget.state.selectedTrails;
    final applied = <_Applied>[
      if (_difficulty case final value?)
        (
          attribute: TrailAttribute.difficulty.label,
          value: 'rated ${value.label.toLowerCase()}',
          result: widget.state.applyDifficulty(trails, value),
        ),
      if (_ebike case final value?)
        (
          attribute: TrailAttribute.electricBicycle.label,
          value: 'set to ${value.label.toLowerCase()}',
          result: widget.state.applyElectricBicycle(
            trails,
            value,
            // Every trail in the batch is asked about the same machine, in
            // the words the batch was composed in.
            cap: value == EbikeAccess.allowed
                ? _cap ?? _jurisdiction.cap
                : null,
          ),
        ),
    ];
    setState(() {
      _isApplying = false;
      _progress = null;
      _report = applied;
      _reportedOn = _selectedIds;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = widget.state;
    final trails = state.selectedTrails;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
          child: Text(
            '$multiSelectModifier-click a trail to add or remove it, or\n'
            '$multiSelectModifier-drag a box to add every trail it crosses.',
            style: theme.textTheme.bodySmall,
          ),
        ),
        Flexible(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 0, 8, 8),
            shrinkWrap: true,
            children: [
              for (final trail in trails)
                _SelectedTrailRow(trail: trail, state: state),
            ],
          ),
        ),
        const Divider(height: 1),
        // Scrolls on its own so a short window shrinks the editor rather than
        // clipping the button off the bottom of it.
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
            child: _buildEditor(theme, trails),
          ),
        ),
      ],
    );
  }

  Widget _buildEditor(ThemeData theme, List<Trail> trails) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Field(
          label: 'Difficulty on all ${trails.length}',
          child: DifficultyDropdown(
            value: _difficulty,
            hint: 'Choose one rating for every trail',
            onChanged: _isApplying
                ? null
                : (value) => setState(() {
                    _difficulty = value;
                    _report = null;
                  }),
          ),
        ),
        if (_difficulty?.isCommonsOnly ?? false) ...[
          const SizedBox(height: 6),
          Text(Difficulty.commonsOnlyNote, style: theme.textTheme.bodySmall),
        ],
        const SizedBox(height: 12),
        Field(
          label: 'E-bike access on all ${trails.length}',
          child: ElectricBicycleDropdown(
            value: _ebike,
            hint: 'Leave alone',
            onChanged: _isApplying
                ? null
                : (value) => setState(() {
                    _ebike = value;
                    _report = null;
                  }),
          ),
        ),
        if (_ebike == EbikeAccess.allowed) ...[
          const SizedBox(height: 10),
          Field(
            label: 'Up to — ${_jurisdiction.label}',
            child: EbikeClassDropdown(
              value: _cap ?? _jurisdiction.cap,
              jurisdiction: _jurisdiction,
              onChanged: _isApplying
                  ? null
                  : (value) => setState(() {
                      _cap = value;
                      _report = null;
                    }),
            ),
          ),
        ],
        if (_ebike case final access?) ...[
          const SizedBox(height: 6),
          Text(access.description, style: theme.textTheme.bodySmall),
        ],
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            icon: const Icon(Icons.done_all, size: 17),
            label: Text('Stage on ${trails.length} trails'),
            onPressed: !_hasDraft || _isApplying ? null : _apply,
          ),
        ),
        if (_progress case (final done, final total)) ...[
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              minHeight: 5,
              value: total == 0 ? null : done / total,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Reading $done of $total trails from OpenStreetMap…',
            style: theme.textTheme.bodySmall,
          ),
        ],
        if (_report case final report?) ...[
          const SizedBox(height: 10),
          Text(_describe(report), style: theme.textTheme.bodySmall),
        ],
      ],
    );
  }
}

/// Plain language about what a batch actually did — a batch is rarely uniform,
/// and a rider who isn't told which trails were skipped has to audit the review
/// list by hand to find out.
///
/// One line per attribute, because "staged 3" over a selection of 40 means
/// something quite different for difficulty than for e-bike access, and a
/// merged total would hide that.
String _describe(List<_Applied> applied) {
  if (applied.isEmpty) return 'Nothing to change.';

  var unreadable = 0;
  final lines = <String>[];
  for (final (attribute: attribute, value: value, result: result) in applied) {
    unreadable = math.max(unreadable, result.unreadable);
    final parts = <String>[
      if (result.staged > 0)
        'staged ${result.staged} ${result.staged == 1 ? 'change' : 'changes'}.',
      if (result.unchanged > 0) '${result.unchanged} already $value.',
      if (result.protected > 0)
        '${result.protected} already answer this with a value Steward cannot '
            'write, and were left as they are.',
    ];
    lines.add(
      '$attribute — ${parts.isEmpty ? 'nothing to change.' : parts.join(' ')}',
    );
  }
  // Unreadable trails are a property of the selection, not of the attribute:
  // the same trails are skipped by every field in the batch.
  if (unreadable > 0) {
    lines.add(
      '$unreadable could not be read from OpenStreetMap and were left alone.',
    );
  }
  return lines.join('\n');
}

/// One line of the working set: what it is, what it's rated, and whether
/// something is already pending on it.
class _SelectedTrailRow extends StatelessWidget {
  const _SelectedTrailRow({required this.trail, required this.state});

  final Trail trail;
  final StewardState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final staged = state.stagedEditFor(
      trail.osmWayId,
      TrailAttribute.difficulty,
    );
    final shown = staged?.difficulty ?? trail.difficulty;

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          DifficultyIcon(shown, size: 17),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              trail.name ?? 'Unnamed trail',
              style: theme.textTheme.bodyMedium,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (staged != null) ...[
            const StatusBadge.staged(),
            const SizedBox(width: 4),
          ],
          IconAction(
            icon: Icons.remove_circle_outline,
            tooltip: 'Drop this trail from the selection',
            onPressed: () => state.setSelected(trail.osmWayId, false),
          ),
        ],
      ),
    );
  }
}

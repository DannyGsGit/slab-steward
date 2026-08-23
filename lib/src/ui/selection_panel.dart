import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../model/difficulty.dart';
import '../model/staged_edit.dart';
import '../model/trail.dart';
import '../state/steward_state.dart';
import 'fields.dart';

/// The bulk editor: one guided value, applied across every trail in the
/// working set.
///
/// Per-trail overrides are deliberately not offered here — product description
/// §4. A batch that needs different values per trail is two batches, not a
/// spreadsheet. What the batch *does* produce is one staged edit per trail, so
/// the review list can show, prune and explain each one on its own.
class SelectionPanel extends StatefulWidget {
  const SelectionPanel({super.key, required this.state});

  final StewardState state;

  @override
  State<SelectionPanel> createState() => _SelectionPanelState();
}

class _SelectionPanelState extends State<SelectionPanel> {
  Difficulty? _draft;

  /// Non-null while authoritative tags are being read: `(done, total)`.
  (int, int)? _progress;
  bool _isApplying = false;
  BatchResult? _report;

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

  Set<int> get _selectedIds =>
      {for (final trail in widget.state.selectedTrails) trail.osmWayId};

  Future<void> _apply() async {
    final value = _draft;
    if (value == null || _isApplying) return;

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

    final report = widget.state.applyDifficulty(
      widget.state.selectedTrails,
      value,
    );
    setState(() {
      _isApplying = false;
      _progress = null;
      _report = report;
      _reportedOn = _selectedIds;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = widget.state;
    final trails = state.selectedTrails;

    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 340, maxHeight: 560),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '${trails.length} trails selected',
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    tooltip: 'Clear selection',
                    onPressed: state.clearSelection,
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Text(
                '$multiSelectModifier-click a trail to add or remove it.',
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
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
              child: _buildEditor(theme, trails),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEditor(ThemeData theme, List<Trail> trails) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Field(
          label: 'Set difficulty on all ${trails.length}',
          child: DifficultyDropdown(
            value: _draft,
            hint: 'Choose one rating for every trail',
            onChanged: _isApplying
                ? null
                : (d) => setState(() {
                    _draft = d;
                    _report = null;
                  }),
          ),
        ),
        if (_draft?.isCommonsOnly ?? false) ...[
          const SizedBox(height: 6),
          Text(Difficulty.commonsOnlyNote, style: theme.textTheme.bodySmall),
        ],
        const SizedBox(height: 12),
        FilledButton.icon(
          icon: const Icon(Icons.done_all, size: 18),
          label: Text('Stage on ${trails.length} trails'),
          onPressed: _draft == null || _isApplying ? null : _apply,
        ),
        if (_progress case (final done, final total)) ...[
          const SizedBox(height: 10),
          LinearProgressIndicator(value: total == 0 ? null : done / total),
          const SizedBox(height: 6),
          Text(
            'Reading $done of $total trails from OpenStreetMap…',
            style: theme.textTheme.bodySmall,
          ),
        ],
        if (_report case final report?) ...[
          const SizedBox(height: 10),
          Text(
            _describe(report, _draft),
            style: theme.textTheme.bodySmall,
          ),
        ],
      ],
    );
  }
}

/// Plain language about what a batch actually did — a batch is rarely uniform,
/// and a rider who isn't told which trails were skipped has to audit the review
/// list by hand to find out.
String _describe(BatchResult report, Difficulty? value) {
  final parts = <String>[
    if (report.staged > 0)
      'Staged ${report.staged} ${report.staged == 1 ? 'change' : 'changes'}.',
    if (report.unchanged > 0)
      '${report.unchanged} already '
          '${value == null ? 'had that rating' : 'rated ${value.label.toLowerCase()}'}.',
    if (report.unreadable > 0)
      '${report.unreadable} could not be read from OpenStreetMap and were '
          'left alone.',
  ];
  return parts.isEmpty ? 'Nothing to change.' : parts.join(' ');
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
          DifficultyIcon(shown, size: 14),
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

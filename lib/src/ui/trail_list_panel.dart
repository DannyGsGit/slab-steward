import 'package:flutter/material.dart';

import '../model/difficulty.dart';
import '../model/staged_edit.dart';
import '../model/trail.dart';
import '../state/steward_state.dart';
import 'fields.dart';
import 'slab_theme.dart';

/// Every trail the map is currently drawing, as a list.
///
/// Two jobs, per product description §4. It's a discovery surface — the same
/// completeness questions the lenses ask, but as a working list you can read
/// down one row at a time — and it's the selection surface for a bulk edit,
/// because "tick the twelve trails missing a rating" is a thing you can do in
/// a list and cannot sanely do by clicking twelve lines on a map.
///
/// It edits nothing. Every row shows its rating and every row can be ticked;
/// what happens to the ticked trails is the Selection pane's business.
///
/// The list is the viewport: it's re-read whenever the camera settles, and it
/// inherits every filter the map is already applying — it shows exactly what
/// the map shows, and narrows nothing further on its own. Switch off paved
/// paths in the Map pane and they leave this list too.
class TrailListPanel extends StatelessWidget {
  const TrailListPanel({super.key, required this.state});

  final StewardState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final trails = state.visibleTrails;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Divider(height: 1),
        _SelectAllRow(state: state, trails: trails),
        const Divider(height: 1),
        Flexible(child: _buildList(theme, trails)),
        if (state.visibleTrailsTruncated)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
            child: Text(
              'Showing the first ${StewardState.maxVisibleTrails} trails. '
              'Zoom in to narrow this down.',
              style: theme.textTheme.bodySmall,
            ),
          ),
      ],
    );
  }

  Widget _buildList(ThemeData theme, List<Trail> trails) {
    if (trails.isEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
        child: Text(
          state.hasListedVisibleTrails
              ? 'No trails in view. Pan or zoom in until some appear.'
              : 'Reading the map…',
          style: theme.textTheme.bodyMedium,
        ),
      );
    }
    return ListView.builder(
      padding: EdgeInsets.zero,
      itemCount: trails.length,
      itemBuilder: (context, i) => _TrailRow(
        key: ValueKey(trails[i].osmWayId),
        trail: trails[i],
        state: state,
      ),
    );
  }
}

/// Tick every trail the list is currently showing — the whole point of the
/// list as a bulk-selection surface. Selections made elsewhere, or scrolled out
/// of view, are left alone either way.
class _SelectAllRow extends StatelessWidget {
  const _SelectAllRow({required this.state, required this.trails});

  final StewardState state;
  final List<Trail> trails;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final listed = {for (final trail in trails) trail.osmWayId};
    final selectedHere = listed.where(state.isSelected).length;
    final value = switch (selectedHere) {
      0 => false,
      _ when selectedHere == listed.length => true,
      _ => null,
    };

    void toggle() {
      final selection = {
        for (final trail in state.selectedTrails) trail.osmWayId,
      };
      state.setSelection(
        value == true ? selection.difference(listed) : selection.union(listed),
      );
    }

    return InkWell(
      onTap: listed.isEmpty ? null : toggle,
      child: Container(
        color: SlabColors.ink900,
        padding: const EdgeInsets.fromLTRB(12, 6, 16, 6),
        child: Row(
          children: [
            Checkbox(
              tristate: true,
              value: value,
              onChanged: listed.isEmpty ? null : (_) => toggle(),
            ),
            Expanded(
              child: Text(
                'Select all ${listed.length}',
                style: theme.textTheme.bodyMedium,
              ),
            ),
            if (state.selectionCount > 0)
              Text(
                '${state.selectionCount} selected',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: SlabColors.gold,
                  fontWeight: FontWeight.w600,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// One trail in the list: what it is, how it's rated, and a box to tick it
/// into the working set with.
///
/// A selector, not an editor. The list's job is to answer "which trails am I
/// working on?" — and a live picker on every row answered a different question
/// badly: it made a 250-row list of dropdowns, each of which quietly spent an
/// OSM API call the moment it was touched. Editing happens in the Selection
/// pane, on the trails picked here.
class _TrailRow extends StatelessWidget {
  const _TrailRow({super.key, required this.trail, required this.state});

  final Trail trail;
  final StewardState state;

  /// The pending rating when there is one, so a trail rated in the editor
  /// reads as rated here rather than as whatever the tiles still say.
  Difficulty get _shown =>
      state
          .stagedEditFor(trail.osmWayId, TrailAttribute.difficulty)
          ?.difficulty ??
      trail.difficulty;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isSelected = state.isSelected(trail.osmWayId);
    final staged = state.stagedEditFor(
      trail.osmWayId,
      TrailAttribute.difficulty,
    );

    return InkWell(
      // The whole row is the target: ticking twelve trails should not be
      // twelve trips to a 20px box.
      onTap: () => state.setSelected(trail.osmWayId, !isSelected),
      child: Container(
        decoration: BoxDecoration(
          // A ticked row wears the gold wash the design system puts behind any
          // active control.
          color: isSelected ? SlabColors.goldSoft : null,
          border: const Border(bottom: BorderSide(color: SlabColors.line)),
        ),
        padding: const EdgeInsets.fromLTRB(8, 6, 16, 8),
        child: Row(
          children: [
            Checkbox(
              value: isSelected,
              onChanged: (checked) =>
                  state.setSelected(trail.osmWayId, checked ?? false),
            ),
            const SizedBox(width: 2),
            // The signage glyph, which is how a rider reads a rating
            // everywhere else in both apps.
            DifficultyIcon(_shown, size: 18),
            const SizedBox(width: 12),
            Expanded(child: _buildLabel(theme, staged)),
          ],
        ),
      ),
    );
  }

  Widget _buildLabel(ThemeData theme, StagedEdit? staged) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          trail.name ?? 'Unnamed trail',
          style: theme.textTheme.bodyMedium,
          overflow: TextOverflow.ellipsis,
        ),
        Row(
          children: [
            if (staged != null) ...[
              const StatusBadge.staged(),
              const SizedBox(width: 6),
            ],
            Expanded(
              child: Text(
                staged?.summary ?? _describe(),
                style: theme.textTheme.bodySmall,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ],
    );
  }

  String _describe() {
    final surface = trail.surface?.label ?? trail.rawSurface;
    return switch ((trail.hasDifficulty, surface)) {
      (false, null) => 'No rating, no surface',
      (false, final s?) => 'No rating · $s',
      (true, null) => '${trail.difficulty.label} · no surface',
      (true, final s?) => '${trail.difficulty.label} · $s',
    };
  }
}

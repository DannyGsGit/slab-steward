import 'package:flutter/material.dart';

import '../state/steward_state.dart';
import 'activity_chart.dart';
import 'contribution_heatmap.dart';
import 'fields.dart';
import 'slab_chrome.dart';
import 'slab_theme.dart';

/// What the rider has actually done through Steward, tallied up — the top of
/// the sidebar's Account pane.
///
/// A section rather than a pane of its own. Stats, the submitted changesets
/// and the sign-out control are all answers to "what has this account done
/// here", and they were fed by one fetch even while they lived behind two
/// rail buttons — so the trophy button was a second door onto the same room.
/// It builds a column, not a scroll view: the pane it sits in does the
/// scrolling, so the sections beneath it scroll with it rather than inside it.
///
/// Scoped to Steward's own changesets rather than the rider's whole OSM
/// history: see [StewardState.stewardHashtag]. A mapper who's edited OSM for
/// a decade would otherwise open this to a "streak" that has nothing to do
/// with using this tool.
class StatsSection extends StatelessWidget {
  const StatsSection({super.key, required this.state});

  final StewardState state;

  @override
  Widget build(BuildContext context) {
    if (!state.auth.isSignedIn) return const _SignedOutNotice();

    final theme = Theme.of(context);
    final stats = state.stats;
    final error = state.statsError;
    final isLoading = state.isLoadingStats;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text('YOUR STATS', style: theme.textTheme.labelSmall),
            ),
            // One refresh for the whole pane: the tallies below and the
            // changeset list under them come back from the same read.
            IconAction(
              icon: Icons.refresh,
              tooltip: 'Refresh your stats and changesets',
              onPressed: isLoading ? null : state.loadStats,
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (isLoading && stats == null)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 32),
            child: Center(
              child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          )
        else if (error != null && stats == null)
          Text(
            error,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.error,
            ),
          )
        else if (stats != null && stats.isEmpty)
          const _EmptyNotice()
        else if (stats != null) ...[
          Row(
            children: [
              Expanded(
                child: _StatTile(
                  icon: Icons.push_pin_outlined,
                  value: '${stats.changesetCount}',
                  label: 'CHANGESETS',
                  badge: 'new',
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _StatTile(
                  icon: Icons.route_outlined,
                  value: '${stats.elementsChanged}',
                  label: 'TRAILS TOUCHED',
                  badge: 'new',
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _StatTile(
                  icon: Icons.local_fire_department_outlined,
                  value: '${stats.currentStreakDays}',
                  label: 'DAY STREAK',
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _StatTile(
                  icon: Icons.calendar_month_outlined,
                  value: '${stats.daysActive}',
                  label: 'DAYS ACTIVE',
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ActivitySection(stats: stats),
          const SizedBox(height: 14),
          ContributionHeatmap(stats: stats),
          if (stats.firstEditAt != null) ...[
            const SizedBox(height: 14),
            SlabSurface(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.info_outline,
                    size: 15,
                    color: SlabColors.gold,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'First edit ${formatSlabDate(stats.firstEditAt!)}, '
                      'most recent ${formatSlabDate(stats.lastEditAt!)}.',
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
        if (error != null && stats != null) ...[
          const SizedBox(height: 14),
          Text(
            error,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.error,
            ),
          ),
        ],
      ],
    );
  }
}

/// One number, its glyph, and what it counts — the section's whole vocabulary.
class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.icon,
    required this.value,
    required this.label,
    this.badge,
  });

  final IconData icon;
  final String value;
  final String label;

  /// A small pill in the tile's top-right corner, flagging a stat that's
  /// newly shown here rather than the rider's actual best — see the "new"
  /// tags on Changesets/Trails touched in the SLAB mockup.
  final String? badge;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SlabSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 17, color: SlabColors.gold),
              const Spacer(),
              if (badge case final badge?) _NewBadge(label: badge),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            value,
            style: theme.textTheme.titleLarge?.copyWith(fontSize: 24),
          ),
          const SizedBox(height: 2),
          Text(label, style: theme.textTheme.labelSmall),
        ],
      ),
    );
  }
}

class _NewBadge extends StatelessWidget {
  const _NewBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: SlabColors.ink600,
      borderRadius: BorderRadius.circular(SlabRadii.pill),
    ),
    child: Text(
      label,
      style: const TextStyle(
        fontSize: 9.5,
        fontWeight: FontWeight.w700,
        color: SlabColors.sage,
        letterSpacing: 0.4,
      ),
    ),
  );
}

class _SignedOutNotice extends StatelessWidget {
  const _SignedOutNotice();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Sign in to see what you\'ve done through Steward.',
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 8),
        Text(
          'Stats are tallied from the changesets you\'ve submitted, so '
          'there\'s nothing to show until you\'re signed in to an '
          'OpenStreetMap account.',
          style: theme.textTheme.bodySmall,
        ),
      ],
    );
  }
}

class _EmptyNotice extends StatelessWidget {
  const _EmptyNotice();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('No changesets yet.', style: theme.textTheme.bodyMedium),
        const SizedBox(height: 8),
        Text(
          'Rate a trail and submit it from the Staged changes pane — your '
          'first changeset will show up here.',
          style: theme.textTheme.bodySmall,
        ),
      ],
    );
  }
}

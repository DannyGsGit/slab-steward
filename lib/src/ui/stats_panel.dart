import 'package:flutter/material.dart';

import '../state/steward_state.dart';
import 'slab_chrome.dart';
import 'slab_theme.dart';

/// What the rider has actually done through Steward, tallied up — the
/// sidebar's stats pane.
///
/// Scoped to Steward's own changesets rather than the rider's whole OSM
/// history: see [StewardState.stewardHashtag]. A mapper who's edited OSM for
/// a decade would otherwise open this pane to a "streak" that has nothing to
/// do with using this tool.
class StatsPanel extends StatefulWidget {
  const StatsPanel({super.key, required this.state});

  final StewardState state;

  @override
  State<StatsPanel> createState() => _StatsPanelState();
}

class _StatsPanelState extends State<StatsPanel> {
  @override
  void initState() {
    super.initState();
    widget.state.auth.addListener(_onAuthChanged);
    // Deferred a frame: loadStats's first act is a synchronous
    // notifyListeners to flip on the loading flag, and calling that from
    // initState — reentrant into the build that's mounting this very
    // widget — trips Flutter's "don't mark a tree dirty while it's still
    // being built" assertion.
    if (widget.state.auth.isSignedIn) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.state.loadStats();
      });
    }
  }

  @override
  void dispose() {
    widget.state.auth.removeListener(_onAuthChanged);
    super.dispose();
  }

  // Signing in while this pane is already open should fill it in; signing
  // out should drop the last rider's numbers rather than leave them showing
  // under a new name.
  void _onAuthChanged() {
    if (widget.state.auth.isSignedIn) {
      widget.state.loadStats();
    } else {
      widget.state.clearStats();
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.state,
      builder: (context, _) {
        if (!widget.state.auth.isSignedIn) {
          return const _SignedOutNotice();
        }
        return _StatsBody(state: widget.state);
      },
    );
  }
}

class _StatsBody extends StatelessWidget {
  const _StatsBody({required this.state});

  final StewardState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final stats = state.stats;
    final error = state.statsError;
    final isLoading = state.isLoadingStats;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
      children: [
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
                  icon: Icons.emoji_events_outlined,
                  value: '${stats.changesetCount}',
                  label: 'CHANGESETS',
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _StatTile(
                  icon: Icons.route_outlined,
                  value: '${stats.elementsChanged}',
                  label: 'TRAILS TOUCHED',
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
                      'First edit ${_formatDate(stats.firstEditAt!)}, '
                      'most recent ${_formatDate(stats.lastEditAt!)}.',
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
        const SizedBox(height: 16),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            icon: const Icon(Icons.refresh, size: 15),
            label: const Text('Refresh'),
            onPressed: isLoading ? null : state.loadStats,
          ),
        ),
      ],
    );
  }
}

/// One number, its glyph, and what it counts — the pane's whole vocabulary.
class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.icon,
    required this.value,
    required this.label,
  });

  final IconData icon;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SlabSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 17, color: SlabColors.gold),
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

class _SignedOutNotice extends StatelessWidget {
  const _SignedOutNotice();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      child: Column(
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
      ),
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

const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

String _formatDate(DateTime date) =>
    '${_months[date.month - 1]} ${date.day}, ${date.year}';

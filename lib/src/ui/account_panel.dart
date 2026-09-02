import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../osm/oauth_popup.dart' show OAuthPopupCancelled;
import '../osm/osm_api.dart' show OsmChangeset;
import '../osm/osm_environment.dart';
import '../state/steward_state.dart';
import 'slab_chrome.dart';
import 'slab_theme.dart';
import 'stats_panel.dart';

/// Sign in to OpenStreetMap, and see who you're signed in as — the sidebar's
/// Account pane.
///
/// Its own pane rather than a step inside the submit flow. Sign-in can't be
/// something you only find once you have edits to submit: a rider wants to
/// know whose account they're about to write under *before* doing the work.
///
/// Always names the map, because "whose account, on which map" is the one
/// question this tool must never leave ambiguous.
///
/// Everything about the account lives here, in the order a rider asks for it:
/// who they are, what they have done through Steward ([StatsSection]), the
/// changesets it went out in — the receipts for everything that has actually
/// left this machine, each one a link out to OSM's own page for it — and the
/// way out. Stats had a rail button of its own until they were folded in;
/// both were fed by one read of the same changesets, so the second button was
/// a second door onto the same room.
class AccountPanel extends StatefulWidget {
  const AccountPanel({super.key, required this.state});

  final StewardState state;

  @override
  State<AccountPanel> createState() => _AccountPanelState();
}

class _AccountPanelState extends State<AccountPanel> {
  @override
  void initState() {
    super.initState();
    widget.state.auth.addListener(_onAuthChanged);
    // Deferred a frame: loadStats's first act is a synchronous
    // notifyListeners to flip on the loading flag, and calling that from
    // initState — reentrant into the build that's mounting this very widget
    // — trips Flutter's "don't mark a tree dirty while it's still being
    // built" assertion.
    if (widget.state.auth.isSignedIn) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _loadStats();
      });
    }
  }

  @override
  void dispose() {
    widget.state.auth.removeListener(_onAuthChanged);
    super.dispose();
  }

  /// Only when there's nothing loaded yet. One read feeds the stats, the
  /// changeset list and the count on its fold, so re-opening the pane should
  /// not spend a call on an answer already in hand — the Refresh beside the
  /// stats heading is how a rider asks for a fresh one.
  void _loadStats() {
    if (widget.state.stats == null) widget.state.loadStats();
  }

  // Signing in while this pane is open should fill the stats and the list in;
  // signing out has to empty them, so one rider's numbers never sit under
  // another's name.
  void _onAuthChanged() {
    if (widget.state.auth.isSignedIn) {
      _loadStats();
    } else {
      widget.state.clearStats();
    }
  }

  Future<void> _signIn() async {
    try {
      await widget.state.auth.signIn();
    } on OAuthPopupCancelled {
      // The rider closed the popup — they know, no need to tell them.
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$e'),
          behavior: SnackBarBehavior.floating,
          showCloseIcon: true,
          duration: const Duration(seconds: 8),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Both: the identity comes from auth, the changeset list from the state
    // the fetch lands in.
    return ListenableBuilder(
      listenable: Listenable.merge([widget.state, widget.state.auth]),
      builder: (context, _) {
        final auth = widget.state.auth;
        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          children: [
            Row(
              children: [
                AccountAvatar(
                  isSignedIn: auth.isSignedIn,
                  isSigningIn: auth.isSigningIn,
                  displayName: auth.identity?.displayName,
                  size: 44,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        auth.isSignedIn
                            ? auth.identity?.displayName ?? 'Signed in'
                            : auth.isSigningIn
                            ? 'Signing in…'
                            : 'Not signed in',
                        style: theme.textTheme.titleMedium,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        auth.isSigningIn
                            ? 'Finish in the popup, or cancel below'
                            : osmShortLabel,
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            // Signed out, the one thing this pane is for is the way in, so it
            // comes before the empty stats it would otherwise sit under.
            if (!auth.isSignedIn) ...[
              FilledButton.icon(
                icon: const Icon(Icons.login, size: 17),
                label: Text(
                  auth.isSigningIn
                      ? 'Cancel signing in'
                      : 'Sign in to OpenStreetMap',
                ),
                // While signing in, pressing abandons the attempt — the popup
                // is COOP-severed and can't be closed from here, so without
                // this a rider who gives up has a spinner and no way out.
                onPressed: auth.isSigningIn ? auth.cancelSignIn : _signIn,
              ),
              const SizedBox(height: 18),
            ],
            // Signed in, the pane reads as the account's record, top to
            // bottom: what has been done, the changesets it went out in, and
            // the way out last — a control nobody is looking for until they
            // have read everything above it.
            StatsSection(state: widget.state),
            if (auth.isSignedIn) ...[
              const SizedBox(height: 16),
              _SubmittedChangesets(state: widget.state),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                icon: const Icon(Icons.logout, size: 17),
                label: const Text('Sign out'),
                onPressed: auth.signOut,
              ),
            ],
            const SizedBox(height: 24),
            const _PrivacyNote(),
          ],
        );
      },
    );
  }
}

/// What Steward counts, said plainly, at the foot of the pane about the
/// rider's own account.
///
/// Here rather than behind a link because this is the pane where someone asks
/// what the tool knows about them, and an OSM audience is entitled to a
/// straight answer without leaving the app. Short on purpose: the honest
/// version is genuinely this short — no autocapture, no session recording,
/// nothing about the map itself. See docs/specs/analytics.md §3.
class _PrivacyNote extends StatelessWidget {
  const _PrivacyNote();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(color: SlabColors.line, height: 1),
        const SizedBox(height: 14),
        Text(
          'Privacy',
          style: theme.textTheme.labelLarge?.copyWith(color: SlabColors.sage),
        ),
        const SizedBox(height: 6),
        Text(
          'Steward counts how the tool gets used — visits, trails selected, '
          'edits staged and submitted — so we can see where it gets in your '
          "way. It doesn't record your screen, and it collects nothing about "
          'where you are or which trails you looked at.',
          style: theme.textTheme.bodySmall?.copyWith(color: SlabColors.sageDim),
        ),
        const SizedBox(height: 6),
        Text(
          'Once you sign in, those counts are linked to your OpenStreetMap '
          'user number — the one already public on every changeset you make. '
          'Signing out unlinks them.',
          style: theme.textTheme.bodySmall?.copyWith(color: SlabColors.sageDim),
        ),
      ],
    );
  }
}

/// The design system's account avatar: a gold-ringed disc carrying the
/// mapper's initials once there is a name to take them from.
///
/// Initials rather than a generic silhouette because this button answers
/// "whose account am I about to write under" — and a face-shaped icon answers
/// that with "somebody's".
class AccountAvatar extends StatelessWidget {
  const AccountAvatar({
    super.key,
    required this.isSignedIn,
    required this.isSigningIn,
    required this.displayName,
    this.size = 32,
  });

  final bool isSignedIn;
  final bool isSigningIn;
  final String? displayName;

  /// The rail wears it at its default size; the pane wears a larger one.
  final double size;

  /// At most two letters, from the first and last word of the name.
  static String? _initials(String? name) {
    final words = (name ?? '').trim().split(RegExp(r'[\s_.-]+'))
      ..removeWhere((w) => w.isEmpty);
    if (words.isEmpty) return null;
    final letters = words.length == 1
        ? words.first.substring(0, 1)
        : '${words.first[0]}${words.last[0]}';
    return letters.toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final initials = isSignedIn ? _initials(displayName) : null;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: SlabColors.goldSoft,
        shape: BoxShape.circle,
        border: Border.all(
          color: isSignedIn ? SlabColors.gold : SlabColors.line,
          width: 1.5,
        ),
      ),
      child: switch ((isSigningIn, initials)) {
        (true, _) => SizedBox(
          width: size / 2,
          height: size / 2,
          child: const CircularProgressIndicator(strokeWidth: 2),
        ),
        (_, final initials?) => Text(
          initials,
          style: TextStyle(
            fontSize: size * 0.375,
            fontWeight: FontWeight.w700,
            color: SlabColors.gold,
          ),
        ),
        _ => Icon(
          isSignedIn ? Icons.person : Icons.person_outline,
          size: size / 2,
          color: SlabColors.gold,
        ),
      },
    );
  }
}

/// The rider's submitted changesets, folded away until asked for.
///
/// Collapsed by default, because this pane's first question is "whose account
/// am I writing under" and a list of forty changesets in front of the answer
/// buries it. The header still carries the count, so the fold advertises what
/// is behind it rather than hiding it.
///
/// Every row is a link out to OSM's own page for that changeset — the diff,
/// the discussion and the revert button all live there, and none of them are
/// Steward's job to reimplement. This is the receipt; the record is theirs.
///
/// Scoped to Steward's own changesets, exactly like the stats pane, and fed by
/// the same fetch: see [StewardState.stewardHashtag].
class _SubmittedChangesets extends StatefulWidget {
  const _SubmittedChangesets({required this.state});

  final StewardState state;

  @override
  State<_SubmittedChangesets> createState() => _SubmittedChangesetsState();
}

class _SubmittedChangesetsState extends State<_SubmittedChangesets> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    return SlabSurface(
      padding: EdgeInsets.zero,
      // The rows fill the card edge to edge, so their hover and splash have
      // to be clipped to its corners or they square them off.
      child: ClipRRect(
        borderRadius: BorderRadius.circular(SlabRadii.card),
        child: Material(
          type: MaterialType.transparency,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _ChangesetsHeader(
                count: state.changesets.length,
                isLoading: state.isLoadingStats,
                isExpanded: _isExpanded,
                onTap: () => setState(() => _isExpanded = !_isExpanded),
              ),
              if (_isExpanded) ...[
                const Divider(height: 1),
                _ChangesetsBody(state: state),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// The fold's handle: what's inside, how much of it, and which way it turns.
class _ChangesetsHeader extends StatelessWidget {
  const _ChangesetsHeader({
    required this.count,
    required this.isLoading,
    required this.isExpanded,
    required this.onTap,
  });

  final int count;
  final bool isLoading;
  final bool isExpanded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 11, 8, 11),
        child: Row(
          children: [
            const Icon(
              Icons.receipt_long_outlined,
              size: 17,
              color: SlabColors.gold,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Submitted changesets',
                style: theme.textTheme.titleSmall,
              ),
            ),
            // The count is the reason to open the fold, so it stays visible
            // while it's shut — a spinner only until there's a number.
            if (isLoading && count == 0)
              const SizedBox(
                width: 13,
                height: 13,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              Text(
                '$count',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: SlabColors.gold,
                  fontWeight: FontWeight.w700,
                ),
              ),
            AnimatedRotation(
              turns: isExpanded ? 0.5 : 0,
              duration: const Duration(milliseconds: 150),
              child: const Icon(
                Icons.expand_more,
                size: 20,
                color: SlabColors.sage,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// What the fold holds: the changesets, or the reason there are none to show.
class _ChangesetsBody extends StatelessWidget {
  const _ChangesetsBody({required this.state});

  final StewardState state;

  @override
  Widget build(BuildContext context) {
    final changesets = state.changesets;

    // Only when there are no rows to show. The read behind this pane reports
    // its failures in full under the stats heading, where the Refresh that
    // retries it also lives; down here all a failure has to explain is why
    // the fold is empty.
    if (changesets.isEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
        child: switch ((state.isLoadingStats, state.statsError)) {
          (true, _) => const Center(
            child: SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
          (_, final _?) => const _ChangesetsNote(
            text: 'Couldn\'t read your changesets.',
            isError: true,
          ),
          _ => const _ChangesetsNote(
            text:
                'Nothing submitted yet. Rate a trail and send it from the '
                'Staged changes pane — the changeset shows up here.',
          ),
        },
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final changeset in changesets) ...[
          _ChangesetRow(changeset: changeset),
          const Divider(height: 1),
        ],
      ],
    );
  }
}

class _ChangesetsNote extends StatelessWidget {
  const _ChangesetsNote({required this.text, this.isError = false});

  final String text;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      text,
      style: theme.textTheme.bodySmall?.copyWith(
        color: isError ? theme.colorScheme.error : null,
      ),
    );
  }
}

/// One changeset: what the rider said they were doing, when, how much of it,
/// and a tap that opens the changeset on OpenStreetMap itself.
class _ChangesetRow extends StatelessWidget {
  const _ChangesetRow({required this.changeset});

  final OsmChangeset changeset;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final comment = changeset.comment;
    final count = changeset.changesCount;
    return Tooltip(
      message: changeset.osmUrl,
      child: InkWell(
        onTap: () => launchUrl(Uri.parse(changeset.osmUrl)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      // The comment is what the rider wrote; the id is what
                      // OSM will call it if they didn't.
                      comment == null || comment.isEmpty
                          ? 'Changeset #${changeset.id}'
                          : comment,
                      style: theme.textTheme.bodyMedium,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${formatSlabDate(changeset.createdAt)} · '
                      '#${changeset.id} · '
                      '$count ${count == 1 ? 'trail' : 'trails'}',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(
                Icons.open_in_new,
                size: 14,
                color: SlabColors.sageDim,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

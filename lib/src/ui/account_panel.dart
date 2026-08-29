import 'package:flutter/material.dart';

import '../osm/oauth_popup.dart' show OAuthPopupCancelled;
import '../osm/osm_environment.dart';
import '../state/steward_state.dart';
import 'slab_chrome.dart';
import 'slab_theme.dart';

/// Sign in to OpenStreetMap, and see who you're signed in as — the sidebar's
/// Account pane.
///
/// Its own pane rather than a step inside the submit flow. Sign-in can't be
/// something you only find once you have edits to submit: a rider wants to
/// know whose account they're about to write under *before* doing the work.
///
/// Always names the map, because "whose account, on which map" is the one
/// question this tool must never leave ambiguous.
class AccountPanel extends StatefulWidget {
  const AccountPanel({super.key, required this.state});

  final StewardState state;

  @override
  State<AccountPanel> createState() => _AccountPanelState();
}

class _AccountPanelState extends State<AccountPanel> {
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
    return ListenableBuilder(
      listenable: widget.state.auth,
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
            if (auth.isSignedIn)
              OutlinedButton.icon(
                icon: const Icon(Icons.logout, size: 17),
                label: const Text('Sign out'),
                onPressed: auth.signOut,
              )
            else
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
            const SizedBox(height: 16),
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
                      'Edits are staged locally and only reach $osmLabel when '
                      'you submit them from the Staged changes pane.',
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
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

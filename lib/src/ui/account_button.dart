import 'package:flutter/material.dart';

import '../osm/oauth_popup.dart' show OAuthPopupCancelled;
import '../osm/osm_environment.dart';
import '../state/steward_state.dart';
import 'slab_theme.dart';

/// Sign in to OpenStreetMap, and see who you're signed in as.
///
/// Lives in the persistent map chrome rather than inside the submit flow.
/// Sign-in can't be something you only find once you have edits to submit:
/// a rider wants to know whose account they're about to write under *before*
/// doing the work.
///
/// Always names the map, because "whose account, on which map" is the one
/// question this tool must never leave ambiguous.
class AccountButton extends StatefulWidget {
  const AccountButton({super.key, required this.state});

  final StewardState state;

  @override
  State<AccountButton> createState() => _AccountButtonState();
}

class _AccountButtonState extends State<AccountButton> {
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
        return Card(
          margin: EdgeInsets.zero,
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            // While signing in, tapping abandons the attempt — the popup is
            // COOP-severed and can't be closed from here, so without this a
            // rider who gives up has a spinner and no way out.
            onTap: auth.isSignedIn
                ? null
                : auth.isSigningIn
                ? auth.cancelSignIn
                : _signIn,
            child: Padding(
              padding: EdgeInsets.fromLTRB(12, 8, auth.isSignedIn ? 4 : 16, 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _Avatar(
                    isSignedIn: auth.isSignedIn,
                    isSigningIn: auth.isSigningIn,
                    displayName: auth.identity?.displayName,
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        auth.isSignedIn
                            ? auth.identity?.displayName ?? 'Signed in'
                            : auth.isSigningIn
                            ? 'Signing in…'
                            : 'Sign in to OpenStreetMap',
                        style: theme.textTheme.titleSmall,
                      ),
                      Text(
                        auth.isSigningIn
                            ? 'Finish in the popup, or tap to cancel'
                            : osmShortLabel,
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                  if (auth.isSignedIn)
                    IconButton(
                      icon: const Icon(Icons.logout, size: 18),
                      tooltip: 'Sign out',
                      visualDensity: VisualDensity.compact,
                      onPressed: auth.signOut,
                    ),
                ],
              ),
            ),
          ),
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
class _Avatar extends StatelessWidget {
  const _Avatar({
    required this.isSignedIn,
    required this.isSigningIn,
    required this.displayName,
  });

  final bool isSignedIn;
  final bool isSigningIn;
  final String? displayName;

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
      width: 32,
      height: 32,
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
        (true, _) => const SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        (_, final initials?) => Text(
          initials,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: SlabColors.gold,
          ),
        ),
        _ => Icon(
          isSignedIn ? Icons.person : Icons.login,
          size: 16,
          color: SlabColors.gold,
        ),
      },
    );
  }
}

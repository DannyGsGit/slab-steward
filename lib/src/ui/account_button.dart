import 'package:flutter/material.dart';

import '../osm/oauth_popup.dart' show OAuthPopupCancelled;
import '../osm/osm_environment.dart';
import '../state/steward_state.dart';

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
              padding: EdgeInsets.fromLTRB(14, 8, auth.isSignedIn ? 4 : 16, 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 22,
                    height: 22,
                    child: auth.isSigningIn
                        ? const Padding(
                            padding: EdgeInsets.all(3),
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Icon(
                            auth.isSignedIn
                                ? Icons.account_circle
                                : Icons.login,
                            size: 22,
                          ),
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

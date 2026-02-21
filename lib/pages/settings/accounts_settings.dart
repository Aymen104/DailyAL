import 'package:dailyanimelist/api/anilist/anilist_auth.dart';
import 'package:dailyanimelist/constant.dart';
import 'package:dailyanimelist/main.dart';
import 'package:dailyanimelist/user/user.dart';
import 'package:dailyanimelist/widgets/avatarwidget.dart';
import 'package:flutter/material.dart';

/// Accounts management page – MAL + AniList cards.
class AccountsSettingsPage extends StatefulWidget {
  const AccountsSettingsPage({super.key});

  @override
  State<AccountsSettingsPage> createState() => _AccountsSettingsPageState();
}

class _AccountsSettingsPageState extends State<AccountsSettingsPage> {
  @override
  void initState() {
    super.initState();
    user.addListener(_onUserChanged);
  }

  @override
  void dispose() {
    user.removeListener(_onUserChanged);
    super.dispose();
  }

  void _onUserChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Accounts')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildMalCard(theme),
          const SizedBox(height: 16),
          _buildAniListCard(theme),
        ],
      ),
    );
  }

  // ─── MAL Card ──────────────────────────────────────────────────

  Widget _buildMalCard(ThemeData theme) {
    final isConnected = user.status == AuthStatus.AUTHENTICATED;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundImage:
                      const AssetImage('assets/images/mal-icon.png'),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('MyAnimeList', style: theme.textTheme.titleMedium),
                      if (isConnected)
                        Text('Connected',
                            style: TextStyle(
                                color: theme.colorScheme.primary,
                                fontSize: 12)),
                    ],
                  ),
                ),
                if (isConnected)
                  Chip(
                    avatar: Icon(Icons.check_circle,
                        color: theme.colorScheme.primary, size: 16),
                    label: const Text('Connected'),
                  ),
              ],
            ),
            if (isConnected) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => launchLogOutConfirmation(context: context),
                  icon: const Icon(Icons.logout),
                  label: const Text('Logout'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ─── AniList Card ──────────────────────────────────────────────

  Widget _buildAniListCard(ThemeData theme) {
    final isConnected = user.isAniListConnected;
    final aniUser = user.anilistUser;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (isConnected && aniUser?.avatarMedium != null)
                  AvatarWidget(
                    url: aniUser!.avatarMedium,
                    radius: BorderRadius.circular(20),
                    height: 40,
                    width: 40,
                  )
                else
                  CircleAvatar(
                    radius: 20,
                    backgroundColor: const Color(0xFF2B2D42),
                    child: Text('AL',
                        style: TextStyle(
                            color: Colors.white, fontWeight: FontWeight.bold)),
                  ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('AniList', style: theme.textTheme.titleMedium),
                      if (isConnected && aniUser != null)
                        Text(aniUser.name,
                            style: TextStyle(
                                color: theme.colorScheme.primary,
                                fontSize: 12)),
                    ],
                  ),
                ),
                if (isConnected)
                  Chip(
                    avatar: Icon(Icons.check_circle,
                        color: theme.colorScheme.primary, size: 16),
                    label: const Text('Connected'),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: isConnected
                  ? OutlinedButton.icon(
                      onPressed: () async {
                        final confirmed = await showConfirmationDialog(
                          context: context,
                          alertTitle: 'Disconnect AniList',
                          desc:
                              'Are you sure you want to disconnect your AniList account?',
                        );
                        if (confirmed ?? false) {
                          await AniListAuth.signOut();
                        }
                      },
                      icon: const Icon(Icons.link_off),
                      label: const Text('Disconnect'),
                    )
                  : FilledButton.icon(
                      onPressed: () => AniListAuth.handleSignIn(),
                      icon: const Icon(Icons.link),
                      label: const Text('Connect AniList'),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

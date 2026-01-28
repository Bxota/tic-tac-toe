import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../controllers/game_controller.dart';
import '../controllers/profile_controller.dart';
import '../ui/widgets.dart';
import 'game_screen.dart';
import 'rules_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.controller, required this.profile});

  final GameController controller;
  final ProfileController profile;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _JoinResult {
  const _JoinResult({required this.code, required this.name});

  final String code;
  final String name;
}

class _HomeScreenState extends State<HomeScreen> {
  final TextEditingController _roomController = TextEditingController();
  String _lastName = '';

  @override
  void initState() {
    super.initState();
    widget.profile.init();
  }

  @override
  void dispose() {
    _roomController.dispose();
    super.dispose();
  }

  Future<String?> _showNameDialog({required String title}) async {
    final nameController = TextEditingController(text: _lastName);
    final result = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: AppColors.card,
          title: Text(title),
          content: TextField(
            controller: nameController,
            decoration: const InputDecoration(
              hintText: 'Ton nom',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Annuler'),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop(nameController.text.trim());
              },
              child: const Text('Continuer'),
            ),
          ],
        );
      },
    );
    nameController.dispose();
    if (result != null && result.isNotEmpty) {
      _lastName = result;
    }
    return result;
  }

  Future<_JoinResult?> _showJoinDialog({required bool spectator}) async {
    _roomController.clear();
    final nameController = TextEditingController(text: _lastName);
    final result = await showDialog<_JoinResult>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: AppColors.card,
          title: Text(spectator ? 'Observer un salon' : 'Rejoindre un salon'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _roomController,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(
                  hintText: 'Code du salon (ex: ABCDEF)',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: nameController,
                decoration: const InputDecoration(
                  hintText: 'Ton nom',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Annuler'),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop(
                  _JoinResult(
                    code: _roomController.text.trim(),
                    name: nameController.text.trim(),
                  ),
                );
              },
              child: Text(spectator ? 'Observer' : 'Rejoindre'),
            ),
          ],
        );
      },
    );
    nameController.dispose();
    if (result != null && result.name.isNotEmpty) {
      _lastName = result.name;
    }
    return result;
  }

  Future<String?> _showTokenDialog() async {
    final tokenController = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: AppColors.card,
          title: const Text('Jeton de session'),
          content: TextField(
            controller: tokenController,
            decoration: const InputDecoration(
              hintText: 'Colle le refresh token',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Annuler'),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop(tokenController.text.trim());
              },
              child: const Text('Continuer'),
            ),
          ],
        );
      },
    );
    tokenController.dispose();
    return result;
  }

  @override
  Widget build(BuildContext context) {
    return AppBackground(
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  CircleIconButton(
                    icon: Icons.info_outline,
                    onTap: () {
                      showDialog<void>(
                        context: context,
                        builder: (context) {
                          return AlertDialog(
                            backgroundColor: AppColors.card,
                            title: const Text('Infos'),
                            content: const Text(
                              'Parties privees en temps reel. Utilise un code pour rejoindre.',
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.of(context).pop(),
                                child: const Text('OK'),
                              ),
                            ],
                          );
                        },
                      );
                    },
                  ),
                  CircleIconButton(
                    icon: Icons.rule_folder_outlined,
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const RulesScreen(),
                        ),
                      );
                    },
                  ),
                ],
              ),
              const Spacer(),
              Column(
                children: [
                  const GameLogo(),
                  const SizedBox(height: 16),
                  Text(
                    'Tic-Tac-Toe',
                    style: GoogleFonts.nunito(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.6,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Jouez en temps reel avec un ami',
                    style: TextStyle(
                      fontSize: 14,
                      color: AppColors.textMuted.withValues(alpha: 0.9),
                    ),
                  ),
                ],
              ),
              const Spacer(),
              SoftButton(
                label: 'Creer un salon prive',
                onPressed: () async {
                  final name = await _showNameDialog(title: 'Ton nom');
                  if (name == null) {
                    return;
                  }
                  widget.controller.leaveRoom();
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => GameScreen(controller: widget.controller),
                    ),
                  );
                  await widget.controller.createRoom(name: name);
                },
              ),
              const SizedBox(height: 14),
              SoftButton(
                label: 'Rejoindre un salon',
                filled: false,
                onPressed: () async {
                  final result = await _showJoinDialog(spectator: false);
                  if (result == null || result.code.isEmpty) {
                    return;
                  }
                  if (!mounted) {
                    return;
                  }
                  widget.controller.leaveRoom();
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => GameScreen(controller: widget.controller),
                    ),
                  );
                  await widget.controller.joinRoom(
                    result.code,
                    name: result.name,
                    spectator: false,
                  );
                },
              ),
              const SizedBox(height: 12),
              SoftButton(
                label: 'Observer un salon',
                filled: false,
                onPressed: () async {
                  final result = await _showJoinDialog(spectator: true);
                  if (result == null || result.code.isEmpty) {
                    return;
                  }
                  if (!mounted) {
                    return;
                  }
                  widget.controller.leaveRoom();
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => GameScreen(controller: widget.controller),
                    ),
                  );
                  await widget.controller.joinRoom(
                    result.code,
                    name: result.name,
                    spectator: true,
                  );
                },
              ),
              const SizedBox(height: 12),
              AnimatedBuilder(
                animation: widget.profile,
                builder: (context, _) {
                  final user = widget.profile.user;
                  final stats = widget.profile.stats;
                  final authLoading = widget.profile.authStatus == LoadStatus.loading;
                  final statsLoading = widget.profile.statsStatus == LoadStatus.loading;
                  return Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppColors.cardSoft,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppColors.outline.withValues(alpha: 0.6)),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.25),
                          blurRadius: 10,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                if (user?.avatar != null && user!.avatar!.isNotEmpty)
                                  CircleAvatar(
                                    radius: 18,
                                    backgroundImage: NetworkImage(user.avatar!),
                                  )
                                else
                                  const CircleAvatar(
                                    radius: 18,
                                    backgroundColor: AppColors.outline,
                                    child: Icon(Icons.person, size: 18),
                                  ),
                                const SizedBox(width: 10),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Compte',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: AppColors.textMuted.withValues(alpha: 0.9),
                                      ),
                                    ),
                                    Text(
                                      user?.username ?? 'Invite',
                                      style: const TextStyle(fontSize: 13),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            SizedBox(
                              width: 140,
                              child: SoftButton(
                                label: user == null ? 'Se connecter' : 'Deconnexion',
                                filled: user == null,
                                onPressed: () async {
                                  if (user != null) {
                                    await widget.profile.logout();
                                    return;
                                  }
                                  final token = await _showTokenDialog();
                                  if (token == null || token.isEmpty) {
                                    return;
                                  }
                                  await widget.profile.authenticateWithRefreshToken(token);
                                },
                              ),
                            ),
                          ],
                        ),
                        if (authLoading)
                          const Padding(
                            padding: EdgeInsets.only(top: 8),
                            child: Text(
                              'Connexion...',
                              style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                            ),
                          ),
                        if (widget.profile.authError != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(
                              widget.profile.authError!,
                              style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
                            ),
                          ),
                        if (user != null) ...[
                          const SizedBox(height: 10),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                'Stats',
                                style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                              ),
                              if (statsLoading)
                                const Text(
                                  'Chargement...',
                                  style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                                ),
                            ],
                          ),
                          if (widget.profile.statsError != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: Text(
                                widget.profile.statsError!,
                                style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
                              ),
                            )
                          else if (stats != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  _StatItem(label: 'Total', value: stats.total),
                                  _StatItem(label: 'Victoires', value: stats.wins),
                                  _StatItem(label: 'Defaites', value: stats.losses),
                                  _StatItem(label: 'Nuls', value: stats.draws),
                                ],
                              ),
                            ),
                        ],
                      ],
                    ),
                  );
                },
              ),
              const SizedBox(height: 12),
              Text(
                'Serveur: ${widget.controller.serverUrl}',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.textMuted,
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatItem extends StatelessWidget {
  const _StatItem({required this.label, required this.value});

  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
        ),
        const SizedBox(height: 2),
        Text(
          value.toString(),
          style: const TextStyle(fontSize: 13),
        ),
      ],
    );
  }
}

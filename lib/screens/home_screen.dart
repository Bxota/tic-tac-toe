import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../controllers/game_controller.dart';
import '../ui/widgets.dart';
import 'game_screen.dart';
import 'rules_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.controller});

  final GameController controller;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final TextEditingController _roomController = TextEditingController();

  @override
  void dispose() {
    _roomController.dispose();
    super.dispose();
  }

  Future<void> _showJoinDialog() async {
    _roomController.clear();
    final result = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: AppColors.card,
          title: const Text('Rejoindre un salon'),
          content: TextField(
            controller: _roomController,
            textCapitalization: TextCapitalization.characters,
            decoration: const InputDecoration(
              hintText: 'Code du salon (ex: ABCDEF)',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Annuler'),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop(_roomController.text.trim());
              },
              child: const Text('Rejoindre'),
            ),
          ],
        );
      },
    );

    if (result == null || result.isEmpty) {
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
    await widget.controller.joinRoom(result);
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
                  widget.controller.leaveRoom();
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => GameScreen(controller: widget.controller),
                    ),
                  );
                  await widget.controller.createRoom();
                },
              ),
              const SizedBox(height: 14),
              SoftButton(
                label: 'Rejoindre un salon',
                filled: false,
                onPressed: _showJoinDialog,
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

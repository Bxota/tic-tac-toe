import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../controllers/game_controller.dart';
import '../models/game_models.dart';
import '../ui/widgets.dart';

class GameScreen extends StatelessWidget {
  const GameScreen({super.key, required this.controller});

  final GameController controller;

  String _statusText() {
    if (controller.roomClosed) {
      return 'Salon ferme';
    }
    if (controller.connectionStatus == ConnectionStatus.connecting) {
      return 'Connexion en cours...';
    }
    if (controller.connectionStatus == ConnectionStatus.disconnected && controller.state == null) {
      return 'Connexion perdue';
    }
    final state = controller.state;
    if (state == null) {
      return 'En attente du serveur...';
    }

    switch (state.status) {
      case GameStatus.waiting:
        return controller.isSpectator ? 'En attente de joueurs' : 'En attente d\'un adversaire';
      case GameStatus.paused:
        return controller.isSpectator ? 'Joueur deconnecte' : 'Adversaire deconnecte';
      case GameStatus.win:
        if (controller.isSpectator || state.winner.isEmpty) {
          return 'Partie terminee';
        }
        return state.winner == controller.symbol ? 'Victoire !' : 'Defaite';
      case GameStatus.draw:
        return 'Match nul';
      case GameStatus.inProgress:
        if (controller.isSpectator) {
          return 'Partie en cours';
        }
        return state.turn == controller.symbol ? 'A ton tour' : 'Tour adverse';
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final state = controller.state;
        final roomCode = controller.roomCode ?? '----';
        final symbol = controller.symbol ?? 'X';
        final opponentSymbol = symbol == 'X' ? 'O' : 'X';
        final board = state?.board ?? List.filled(9, '');
        final youConnected = state?.isPlayerConnected(symbol) ?? controller.isConnected;
        final opponentConnected = state?.isPlayerConnected(opponentSymbol) ?? false;
        final playerXName = state?.playerName('X') ?? '';
        final playerOName = state?.playerName('O') ?? '';
        final youName = state?.playerName(symbol) ?? '';
        final opponentName = state?.playerName(opponentSymbol) ?? '';
        final bothPlayersConnected = (state?.isPlayerConnected('X') ?? false) &&
            (state?.isPlayerConnected('O') ?? false);

        return AppBackground(
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              child: Column(
                children: [
                  Row(
                    children: [
                      CircleIconButton(
                        icon: Icons.arrow_back_ios_new_rounded,
                        onTap: () {
                          controller.leaveRoom();
                          Navigator.of(context).pop();
                        },
                      ),
                      const Spacer(),
                      Text(
                        'Salon $roomCode',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const Spacer(),
                      const SizedBox(width: 40),
                    ],
                  ),
                  const SizedBox(height: 12),
                  GestureDetector(
                    onTap: () async {
                      await Clipboard.setData(ClipboardData(text: roomCode));
                      if (!context.mounted) {
                        return;
                      }
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Code copie')),
                      );
                    },
                    child: Text(
                      'Tap pour copier le code',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textMuted.withValues(alpha: 0.9),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: PlayerStatusCard(
                          label: controller.isSpectator
                              ? (playerXName.isNotEmpty ? playerXName : 'Joueur X')
                              : (youName.isNotEmpty ? 'Toi · $youName' : 'Toi'),
                          symbol: symbol,
                          connected: controller.isSpectator
                              ? state?.isPlayerConnected('X') ?? false
                              : youConnected,
                          highlight: AppColors.accentGreen,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: PlayerStatusCard(
                          label: controller.isSpectator
                              ? (playerOName.isNotEmpty ? playerOName : 'Joueur O')
                              : (opponentName.isNotEmpty ? opponentName : 'Adversaire'),
                          symbol: controller.isSpectator ? 'O' : opponentSymbol,
                          connected: controller.isSpectator
                              ? state?.isPlayerConnected('O') ?? false
                              : opponentConnected,
                          highlight: AppColors.accentRed,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 250),
                    child: Text(
                      _statusText(),
                      key: ValueKey(_statusText()),
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                  if (controller.errorMessage != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      controller.errorMessage!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.accentOrange,
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final boardSize = min(constraints.maxWidth, 360.0);
                      return SizedBox(
                        height: boardSize,
                        width: boardSize,
                        child: GridView.builder(
                          itemCount: 9,
                          physics: const NeverScrollableScrollPhysics(),
                          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 3,
                            crossAxisSpacing: 12,
                            mainAxisSpacing: 12,
                          ),
                          itemBuilder: (context, index) {
                            return BoardCell(
                              value: board[index],
                              onTap: () {
                                if (state == null) {
                                  return;
                                }
                                if (controller.isSpectator) {
                                  return;
                                }
                                if (state.status != GameStatus.inProgress) {
                                  return;
                                }
                                if (state.turn != controller.symbol) {
                                  return;
                                }
                                if (board[index].isNotEmpty) {
                                  return;
                                }
                                controller.sendMove(index);
                              },
                            );
                          },
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 18),
                  if (state?.isFinished == true &&
                      bothPlayersConnected &&
                      !controller.roomClosed &&
                      !controller.isSpectator)
                    SoftButton(
                      label: 'Rejouer',
                      onPressed: () {
                        controller.requestRematch();
                      },
                    ),
                  if (state?.isFinished == true &&
                      bothPlayersConnected &&
                      !controller.roomClosed &&
                      !controller.isSpectator)
                    const SizedBox(height: 12),
                  if (controller.connectionStatus != ConnectionStatus.connected &&
                      !controller.roomClosed &&
                      controller.roomCode != null)
                    SoftButton(
                      label: 'Reconnecter',
                      onPressed: () async {
                        await controller.reconnect();
                      },
                    ),
                  if (controller.roomClosed)
                    SoftButton(
                      label: 'Retour accueil',
                      onPressed: () {
                        controller.leaveRoom();
                        Navigator.of(context).pop();
                      },
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

import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../controllers/game_controller.dart';
import '../models/game_models.dart';
import '../ui/confetti.dart';
import '../ui/widgets.dart';

class GameScreen extends StatefulWidget {
  const GameScreen({super.key, required this.controller});

  final GameController controller;

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> with TickerProviderStateMixin {
  late final AnimationController _shakeController;
  late final Animation<double> _shakeAnimation;
  late final AnimationController _confettiController;
  late final List<ConfettiParticle> _confettiParticles;
  GameStatus? _lastStatus;
  String _lastWinner = '';
  bool _showConfetti = false;

  @override
  void initState() {
    super.initState();
    _shakeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    );
    _shakeAnimation = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(begin: 0, end: -6).chain(CurveTween(curve: Curves.easeOut)),
        weight: 1,
      ),
      TweenSequenceItem(
        tween: Tween(begin: -6, end: 5).chain(CurveTween(curve: Curves.easeInOut)),
        weight: 1,
      ),
      TweenSequenceItem(
        tween: Tween(begin: 5, end: -3).chain(CurveTween(curve: Curves.easeInOut)),
        weight: 1,
      ),
      TweenSequenceItem(
        tween: Tween(begin: -3, end: 2).chain(CurveTween(curve: Curves.easeInOut)),
        weight: 1,
      ),
      TweenSequenceItem(
        tween: Tween(begin: 2, end: 0).chain(CurveTween(curve: Curves.easeOut)),
        weight: 1,
      ),
    ]).animate(_shakeController);
    _confettiController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    );
    _confettiParticles = _buildConfettiParticles();
    _lastStatus = widget.controller.state?.status;
    _lastWinner = widget.controller.state?.winner ?? '';
    widget.controller.addListener(_handleGameUpdate);
  }

  @override
  void didUpdateWidget(covariant GameScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_handleGameUpdate);
      widget.controller.addListener(_handleGameUpdate);
      _lastStatus = widget.controller.state?.status;
      _lastWinner = widget.controller.state?.winner ?? '';
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_handleGameUpdate);
    _shakeController.dispose();
    _confettiController.dispose();
    super.dispose();
  }

  String _statusText() {
    if (widget.controller.roomClosed) {
      return 'Salon ferme';
    }
    if (widget.controller.connectionStatus == ConnectionStatus.connecting) {
      return 'Connexion en cours...';
    }
    if (widget.controller.connectionStatus == ConnectionStatus.disconnected &&
        widget.controller.state == null) {
      return 'Connexion perdue';
    }
    final state = widget.controller.state;
    if (state == null) {
      return 'En attente du serveur...';
    }

    switch (state.status) {
      case GameStatus.waiting:
        return widget.controller.isSpectator
            ? 'En attente de joueurs'
            : 'En attente d\'un adversaire';
      case GameStatus.paused:
        return widget.controller.isSpectator
            ? 'Joueur deconnecte'
            : 'Adversaire deconnecte';
      case GameStatus.win:
        if (widget.controller.isSpectator || state.winner.isEmpty) {
          return 'Partie terminee';
        }
        return state.winner == widget.controller.symbol ? 'Victoire !' : 'Defaite';
      case GameStatus.draw:
        return 'Match nul';
      case GameStatus.inProgress:
        if (widget.controller.isSpectator) {
          return 'Partie en cours';
        }
        return state.turn == widget.controller.symbol ? 'A ton tour' : 'Tour adverse';
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([widget.controller, _shakeController]),
      builder: (context, _) {
        final state = widget.controller.state;
        final roomCode = widget.controller.roomCode ?? '----';
        final symbol = widget.controller.symbol ?? 'X';
        final opponentSymbol = symbol == 'X' ? 'O' : 'X';
        final board = state?.board ?? List.filled(9, '');
        final youConnected = state?.isPlayerConnected(symbol) ?? widget.controller.isConnected;
        final opponentConnected = state?.isPlayerConnected(opponentSymbol) ?? false;
        final playerXName = state?.playerName('X') ?? '';
        final playerOName = state?.playerName('O') ?? '';
        final youName = state?.playerName(symbol) ?? '';
        final opponentName = state?.playerName(opponentSymbol) ?? '';
        final bothPlayersConnected = (state?.isPlayerConnected('X') ?? false) &&
            (state?.isPlayerConnected('O') ?? false);
        final shakeOffset = _shakeAnimation.value;

        return Stack(
          children: [
            Transform.translate(
              offset: Offset(shakeOffset, 0),
              child: AppBackground(
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
                                widget.controller.leaveRoom();
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
                                label: widget.controller.isSpectator
                                    ? (playerXName.isNotEmpty ? playerXName : 'Joueur X')
                                    : (youName.isNotEmpty ? 'Toi · $youName' : 'Toi'),
                                symbol: symbol,
                                connected: widget.controller.isSpectator
                                    ? state?.isPlayerConnected('X') ?? false
                                    : youConnected,
                                highlight: AppColors.accentGreen,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: PlayerStatusCard(
                                label: widget.controller.isSpectator
                                    ? (playerOName.isNotEmpty ? playerOName : 'Joueur O')
                                    : (opponentName.isNotEmpty ? opponentName : 'Adversaire'),
                                symbol:
                                    widget.controller.isSpectator ? 'O' : opponentSymbol,
                                connected: widget.controller.isSpectator
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
                        if (widget.controller.errorMessage != null) ...[
                          const SizedBox(height: 8),
                          Text(
                            widget.controller.errorMessage!,
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
                                      if (widget.controller.isSpectator) {
                                        return;
                                      }
                                      if (state.status != GameStatus.inProgress) {
                                        return;
                                      }
                                      if (state.turn != widget.controller.symbol) {
                                        return;
                                      }
                                      if (board[index].isNotEmpty) {
                                        return;
                                      }
                                      widget.controller.sendMove(index);
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
                            !widget.controller.roomClosed &&
                            !widget.controller.isSpectator)
                          SoftButton(
                            label: 'Rejouer',
                            onPressed: () {
                              widget.controller.requestRematch();
                            },
                          ),
                        if (state?.isFinished == true &&
                            bothPlayersConnected &&
                            !widget.controller.roomClosed &&
                            !widget.controller.isSpectator)
                          const SizedBox(height: 12),
                        if (widget.controller.connectionStatus != ConnectionStatus.connected &&
                            !widget.controller.roomClosed &&
                            widget.controller.roomCode != null)
                          SoftButton(
                            label: 'Reconnecter',
                            onPressed: () async {
                              await widget.controller.reconnect();
                            },
                          ),
                        if (widget.controller.roomClosed)
                          SoftButton(
                            label: 'Retour accueil',
                            onPressed: () {
                              widget.controller.leaveRoom();
                              Navigator.of(context).pop();
                            },
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            if (_showConfetti)
              Positioned.fill(
                child: IgnorePointer(
                  child: ConfettiOverlay(
                    animation: _confettiController,
                    particles: _confettiParticles,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  void _handleGameUpdate() {
    final state = widget.controller.state;
    final status = state?.status;
    final winner = state?.winner ?? '';
    final isSpectator = widget.controller.isSpectator;

    if (status == GameStatus.win && !isSpectator && winner.isNotEmpty) {
      final shouldTrigger = status != _lastStatus || winner != _lastWinner;
      if (shouldTrigger) {
        if (winner == widget.controller.symbol) {
          _playWin();
        } else {
          _playLose();
        }
      }
    }

    if (status != GameStatus.win && _showConfetti) {
      _confettiController.stop();
      if (mounted) {
        setState(() {
          _showConfetti = false;
        });
      }
    }

    _lastStatus = status;
    _lastWinner = winner;
  }

  void _playWin() {
    if (!mounted) {
      return;
    }
    setState(() {
      _showConfetti = true;
    });
    _confettiController.forward(from: 0).whenComplete(() {
      if (!mounted) {
        return;
      }
      setState(() {
        _showConfetti = false;
      });
    });
  }

  void _playLose() {
    _shakeController.forward(from: 0);
  }

  List<ConfettiParticle> _buildConfettiParticles() {
    final random = Random();
    final palette = [
      AppColors.accentBlue.withOpacity(0.75),
      AppColors.accentGreen.withOpacity(0.75),
      AppColors.accentRed.withOpacity(0.75),
      AppColors.accentOrange.withOpacity(0.7),
      AppColors.textPrimary.withOpacity(0.5),
    ];
    return List.generate(
      80,
      (_) => ConfettiParticle.random(random, palette),
    );
  }
}

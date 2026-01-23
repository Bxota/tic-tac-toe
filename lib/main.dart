import 'dart:math';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

void main() {
  runApp(const TicTacToeApp());
}

class TicTacToeApp extends StatelessWidget {
  const TicTacToeApp({super.key});

  @override
  Widget build(BuildContext context) {
    final baseTheme = ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: AppColors.backgroundBottom,
      colorScheme: const ColorScheme.dark(
        primary: AppColors.accentBlue,
        secondary: AppColors.accentGreen,
        surface: AppColors.card,
      ),
      textTheme: GoogleFonts.nunitoTextTheme(
        ThemeData.dark().textTheme,
      ).apply(
        bodyColor: AppColors.textPrimary,
        displayColor: AppColors.textPrimary,
      ),
    );

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Tic Tac Toe',
      theme: baseTheme,
      home: const HomeScreen(),
    );
  }
}

class AppColors {
  static const backgroundTop = Color(0xFF242D4D);
  static const backgroundBottom = Color(0xFF1B223E);
  static const card = Color(0xFF2C3658);
  static const cardSoft = Color(0xFF323B5C);
  static const outline = Color(0xFF3D4668);
  static const accentBlue = Color(0xFF9CAEFF);
  static const accentGreen = Color(0xFF9CE37D);
  static const accentRed = Color(0xFFF59B9B);
  static const accentOrange = Color(0xFFF2C089);
  static const textPrimary = Color(0xFFF5F7FF);
  static const textMuted = Color(0xFFA7B2D1);
  static const glow = Color(0xFF43507A);
}

enum GameMode { solo, friend }

enum CellValue { empty, x, o }

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

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
                    icon: Icons.brightness_6_outlined,
                    onTap: () {},
                  ),
                  CircleIconButton(
                    icon: Icons.flag_outlined,
                    onTap: () {},
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
                ],
              ),
              const Spacer(),
              SoftButton(
                label: 'Play Solo',
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const GameScreen(mode: GameMode.solo),
                    ),
                  );
                },
              ),
              const SizedBox(height: 14),
              SoftButton(
                label: 'Play with a friend',
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const GameScreen(mode: GameMode.friend),
                    ),
                  );
                },
              ),
              const SizedBox(height: 18),
              SoftButton(
                label: 'About',
                filled: false,
                onPressed: () {
                  showDialog<void>(
                    context: context,
                    builder: (context) {
                      return AlertDialog(
                        backgroundColor: AppColors.card,
                        title: const Text('About'),
                        content: const Text(
                          'A cozy Tic Tac Toe experience with a calm night-sky look.',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.of(context).pop(),
                            child: const Text('Close'),
                          ),
                        ],
                      );
                    },
                  );
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}

class GameScreen extends StatefulWidget {
  const GameScreen({super.key, required this.mode});

  final GameMode mode;

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  static const _winPatterns = [
    [0, 1, 2],
    [3, 4, 5],
    [6, 7, 8],
    [0, 3, 6],
    [1, 4, 7],
    [2, 5, 8],
    [0, 4, 8],
    [2, 4, 6],
  ];

  final Random _random = Random();
  List<CellValue> _board = List.filled(9, CellValue.empty);
  CellValue _currentPlayer = CellValue.x;
  CellValue? _winner;
  bool _isDraw = false;
  int _xScore = 0;
  int _oScore = 0;
  bool _botThinking = false;
  int _botAction = 0;

  void _handleTap(int index) {
    if (_board[index] != CellValue.empty || _winner != null || _isDraw) {
      return;
    }
    if (widget.mode == GameMode.solo && _currentPlayer == CellValue.o) {
      return;
    }

    setState(() {
      _board[index] = _currentPlayer;
    });

    _evaluateBoard();

    if (_winner != null || _isDraw) {
      return;
    }

    if (widget.mode == GameMode.solo) {
      _botMove();
    } else {
      setState(() {
        _currentPlayer = _currentPlayer == CellValue.x ? CellValue.o : CellValue.x;
      });
    }
  }

  void _botMove() {
    final action = ++_botAction;
    setState(() {
      _currentPlayer = CellValue.o;
      _botThinking = true;
    });

    Future.delayed(const Duration(milliseconds: 450), () {
      if (!mounted || action != _botAction) {
        return;
      }

      final emptyIndices = <int>[];
      for (var i = 0; i < _board.length; i++) {
        if (_board[i] == CellValue.empty) {
          emptyIndices.add(i);
        }
      }

      if (emptyIndices.isEmpty) {
        setState(() {
          _botThinking = false;
        });
        return;
      }

      final choice = emptyIndices[_random.nextInt(emptyIndices.length)];

      setState(() {
        _board[choice] = CellValue.o;
        _botThinking = false;
      });

      _evaluateBoard();

      if (_winner == null && !_isDraw) {
        setState(() {
          _currentPlayer = CellValue.x;
        });
      }
    });
  }

  void _evaluateBoard() {
    final winner = _findWinner();
    final isDraw = !_board.contains(CellValue.empty) && winner == null;

    if (winner != null) {
      setState(() {
        _winner = winner;
        if (winner == CellValue.x) {
          _xScore += 1;
        } else if (winner == CellValue.o) {
          _oScore += 1;
        }
      });
    } else if (isDraw) {
      setState(() {
        _isDraw = true;
      });
    }
  }

  CellValue? _findWinner() {
    for (final pattern in _winPatterns) {
      final first = _board[pattern[0]];
      if (first == CellValue.empty) {
        continue;
      }
      final second = _board[pattern[1]];
      final third = _board[pattern[2]];
      if (first == second && second == third) {
        return first;
      }
    }
    return null;
  }

  void _resetBoard() {
    setState(() {
      _board = List.filled(9, CellValue.empty);
      _winner = null;
      _isDraw = false;
      _currentPlayer = CellValue.x;
      _botThinking = false;
      _botAction += 1;
    });
  }

  String get _statusText {
    if (_winner != null) {
      if (widget.mode == GameMode.solo) {
        return _winner == CellValue.x ? 'You Win!' : 'Bot Wins!';
      }
      return _winner == CellValue.x ? 'Player X Wins!' : 'Player O Wins!';
    }

    if (_isDraw) {
      return 'Draw';
    }

    if (widget.mode == GameMode.solo) {
      if (_botThinking || _currentPlayer == CellValue.o) {
        return 'Bot Thinking';
      }
      return 'Your Turn';
    }

    return _currentPlayer == CellValue.x ? 'Player X Turn' : 'Player O Turn';
  }

  @override
  Widget build(BuildContext context) {
    final modeLabel = widget.mode == GameMode.solo ? 'Easy Mode' : 'Local Mode';
    final playerLabel = widget.mode == GameMode.solo ? 'You' : 'Player X';
    final opponentLabel = widget.mode == GameMode.solo ? 'Bot' : 'Player O';

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
                    onTap: () => Navigator.of(context).pop(),
                  ),
                  const Spacer(),
                  Text(
                    modeLabel,
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
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: ScoreCard(
                      label: playerLabel,
                      score: _xScore,
                      highlight: AppColors.accentGreen,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ScoreCard(
                      label: opponentLabel,
                      score: _oScore,
                      highlight: AppColors.accentRed,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                child: Text(
                  _statusText,
                  key: ValueKey(_statusText),
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
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
                          value: _board[index],
                          onTap: () => _handleTap(index),
                        );
                      },
                    ),
                  );
                },
              ),
              const SizedBox(height: 20),
              SoftButton(
                label: 'Reset Game',
                onPressed: _resetBoard,
              ),
              const SizedBox(height: 12),
              SoftButton(
                label: 'Game Rules',
                filled: false,
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const RulesScreen(),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class RulesScreen extends StatelessWidget {
  const RulesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AppBackground(
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleIconButton(
                icon: Icons.arrow_back_ios_new_rounded,
                onTap: () => Navigator.of(context).pop(),
              ),
              const SizedBox(height: 18),
              Text(
                'Game Rules',
                style: GoogleFonts.nunito(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 20),
              const RuleCard(
                title: 'Win',
                description: 'Get 3 marks in a row. Player wins, game ends.',
                icon: Icons.emoji_events_outlined,
                iconColor: AppColors.accentOrange,
              ),
              const SizedBox(height: 14),
              const RuleCard(
                title: 'Defeat',
                description:
                    'Opponent gets 3 in a row. Player loses, game ends.',
                icon: Icons.thumb_down_alt_outlined,
                iconColor: AppColors.accentRed,
              ),
              const SizedBox(height: 14),
              const RuleCard(
                title: 'Draw',
                description: 'Board full, no 3 in a row. No winner, game ends.',
                icon: Icons.balance_outlined,
                iconColor: AppColors.accentBlue,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class AppBackground extends StatelessWidget {
  const AppBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [AppColors.backgroundTop, AppColors.backgroundBottom],
        ),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: Stack(
          children: [
            const Positioned(
              top: 40,
              left: -60,
              child: SoftCloud(size: 160, opacity: 0.18),
            ),
            const Positioned(
              top: 140,
              right: -40,
              child: SoftCloud(size: 120, opacity: 0.14),
            ),
            const Positioned(
              bottom: 120,
              left: -30,
              child: SoftCloud(size: 110, opacity: 0.12),
            ),
            child,
          ],
        ),
      ),
    );
  }
}

class SoftCloud extends StatelessWidget {
  const SoftCloud({super.key, required this.size, required this.opacity});

  final double size;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: size,
      width: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white.withOpacity(opacity),
        boxShadow: [
          BoxShadow(
            color: AppColors.glow.withOpacity(opacity / 2),
            blurRadius: 40,
            spreadRadius: 6,
          ),
        ],
      ),
    );
  }
}

class CircleIconButton extends StatelessWidget {
  const CircleIconButton({super.key, required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        splashColor: Colors.transparent,
        highlightColor: Colors.transparent,
        child: Ink(
          height: 40,
          width: 40,
          decoration: BoxDecoration(
            color: AppColors.cardSoft,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.outline.withOpacity(0.6)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.25),
                blurRadius: 10,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Icon(
            icon,
            size: 18,
            color: AppColors.textPrimary,
          ),
        ),
      ),
    );
  }
}

class SoftButton extends StatelessWidget {
  const SoftButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.filled = true,
  });

  final String label;
  final VoidCallback onPressed;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final baseColor = filled ? Colors.white : AppColors.cardSoft;
    final textColor = filled ? AppColors.backgroundBottom : AppColors.textPrimary;

    return ElevatedButton(
      onPressed: onPressed,
      clipBehavior: Clip.antiAlias,
      style: ElevatedButton.styleFrom(
        backgroundColor: baseColor,
        foregroundColor: textColor,
        padding: const EdgeInsets.symmetric(vertical: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        elevation: 0,
        shadowColor: Colors.transparent,
      ).copyWith(
        overlayColor: WidgetStateProperty.all(
          Colors.transparent,
        ),
        splashFactory: NoSplash.splashFactory,
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w700,
          color: textColor,
        ),
      ),
    );
  }
}

class GameLogo extends StatelessWidget {
  const GameLogo({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 90,
      width: 90,
      decoration: BoxDecoration(
        color: AppColors.cardSoft,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.35),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: const Stack(
        alignment: Alignment.center,
        children: [
          Positioned(
            left: 16,
            top: 12,
            child: Text(
              'X',
              style: TextStyle(
                fontSize: 36,
                fontWeight: FontWeight.w900,
                color: AppColors.textPrimary,
              ),
            ),
          ),
          Positioned(
            right: 16,
            bottom: 12,
            child: Text(
              'O',
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.w900,
                color: AppColors.accentBlue,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class ScoreCard extends StatelessWidget {
  const ScoreCard({
    super.key,
    required this.label,
    required this.score,
    required this.highlight,
  });

  final String label;
  final int score;
  final Color highlight;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.cardSoft,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.outline.withOpacity(0.6)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.25),
            blurRadius: 14,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Container(
                height: 10,
                width: 10,
                decoration: BoxDecoration(
                  color: highlight,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textMuted,
                ),
              ),
            ],
          ),
          Text(
            '$score',
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

class BoardCell extends StatelessWidget {
  const BoardCell({super.key, required this.value, required this.onTap});

  final CellValue value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final label = switch (value) {
      CellValue.x => 'X',
      CellValue.o => 'O',
      CellValue.empty => '',
    };

    final color = switch (value) {
      CellValue.x => AppColors.accentGreen,
      CellValue.o => AppColors.accentRed,
      CellValue.empty => AppColors.textPrimary,
    };

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppColors.outline.withOpacity(0.5)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.35),
                blurRadius: 14,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 40,
                fontWeight: FontWeight.w900,
                color: color,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class RuleCard extends StatelessWidget {
  const RuleCard({
    super.key,
    required this.title,
    required this.description,
    required this.icon,
    required this.iconColor,
  });

  final String title;
  final String description;
  final IconData icon;
  final Color iconColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardSoft,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.outline.withOpacity(0.6)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.25),
            blurRadius: 14,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 36,
            width: 36,
            decoration: BoxDecoration(
              color: iconColor.withOpacity(0.18),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              icon,
              size: 18,
              color: iconColor,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  description,
                  style: const TextStyle(
                    fontSize: 13,
                    height: 1.4,
                    color: AppColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

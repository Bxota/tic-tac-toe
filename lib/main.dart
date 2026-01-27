import 'package:flutter/material.dart';

import 'controllers/game_controller.dart';
import 'screens/home_screen.dart';
import 'ui/widgets.dart';

const String kServerUrl = String.fromEnvironment(
  'SERVER_URL',
  defaultValue: 'ws://localhost:8080/ws',
);

void main() {
  runApp(const TicTacToeApp());
}

class TicTacToeApp extends StatefulWidget {
  const TicTacToeApp({super.key});

  @override
  State<TicTacToeApp> createState() => _TicTacToeAppState();
}

class _TicTacToeAppState extends State<TicTacToeApp> {
  late final GameController _controller;

  @override
  void initState() {
    super.initState();
    _controller = GameController(serverUrl: kServerUrl);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Tic Tac Toe',
      theme: buildAppTheme(),
      home: HomeScreen(controller: _controller),
    );
  }
}

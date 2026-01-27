import 'package:flutter/foundation.dart';

enum ConnectionStatus { disconnected, connecting, connected, error }

enum GameStatus { waiting, inProgress, paused, win, draw }

class PlayerInfo {
  const PlayerInfo({required this.id, required this.connected});

  final String id;
  final bool connected;

  factory PlayerInfo.fromJson(Map<String, dynamic> json) {
    return PlayerInfo(
      id: json['id'] as String? ?? '',
      connected: json['connected'] as bool? ?? false,
    );
  }
}

class GameState {
  const GameState({
    required this.roomCode,
    required this.board,
    required this.turn,
    required this.status,
    required this.winner,
    required this.players,
  });

  final String roomCode;
  final List<String> board;
  final String turn;
  final GameStatus status;
  final String winner;
  final Map<String, PlayerInfo> players;

  factory GameState.fromJson(Map<String, dynamic> json) {
    final rawBoard = json['board'] as List<dynamic>? ?? const [];
    final board = rawBoard.map((cell) => cell as String? ?? '').toList();
    while (board.length < 9) {
      board.add('');
    }

    final playersJson = json['players'] as Map<String, dynamic>? ?? const {};
    final players = <String, PlayerInfo>{};
    for (final entry in playersJson.entries) {
      players[entry.key] = PlayerInfo.fromJson(entry.value as Map<String, dynamic>);
    }

    return GameState(
      roomCode: json['room_code'] as String? ?? '',
      board: board,
      turn: json['turn'] as String? ?? 'X',
      status: parseGameStatus(json['status'] as String? ?? 'waiting'),
      winner: json['winner'] as String? ?? '',
      players: players,
    );
  }

  bool get isFinished => status == GameStatus.win || status == GameStatus.draw;

  bool isPlayerConnected(String symbol) {
    return players[symbol]?.connected ?? false;
  }
}

GameStatus parseGameStatus(String value) {
  switch (value) {
    case 'in_progress':
      return GameStatus.inProgress;
    case 'paused':
      return GameStatus.paused;
    case 'win':
      return GameStatus.win;
    case 'draw':
      return GameStatus.draw;
    case 'waiting':
    default:
      return GameStatus.waiting;
  }
}

String gameStatusLabel(GameStatus status) {
  switch (status) {
    case GameStatus.inProgress:
      return 'En cours';
    case GameStatus.paused:
      return 'En pause';
    case GameStatus.win:
      return 'Victoire';
    case GameStatus.draw:
      return 'Match nul';
    case GameStatus.waiting:
      return 'En attente';
  }
}

@immutable
class GameIdentity {
  const GameIdentity({
    required this.playerId,
    required this.symbol,
    required this.roomCode,
  });

  final String playerId;
  final String symbol;
  final String roomCode;
}

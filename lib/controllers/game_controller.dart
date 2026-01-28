import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../models/game_models.dart';

class GameController extends ChangeNotifier {
  GameController({required this.serverUrl});

  final String serverUrl;

  ConnectionStatus connectionStatus = ConnectionStatus.disconnected;
  GameState? state;
  String? roomCode;
  String? playerId;
  String? symbol;
  String? role;
  String? errorMessage;
  bool roomClosed = false;
  String? roomClosedReason;

  WebSocketChannel? _channel;
  StreamSubscription? _subscription;
  bool _manualClose = false;
  String? _guestId;
  final Random _random = Random.secure();

  bool get isConnected => connectionStatus == ConnectionStatus.connected;
  bool get isSpectator => role == 'spectator';

  Future<void> createRoom({required String name}) async {
    roomClosed = false;
    roomClosedReason = null;
    errorMessage = null;
    await _ensureConnected();
    final guestId = await _ensureGuestId();
    _send('create_room', {
      'name': name,
      'guest_id': guestId,
    });
  }

  Future<void> joinRoom(String code, {required String name, bool spectator = false}) async {
    roomClosed = false;
    roomClosedReason = null;
    errorMessage = null;
    await _ensureConnected();
    final guestId = await _ensureGuestId();
    _send('join_room', {
      'room_code': code.toUpperCase(),
      'name': name,
      'spectator': spectator,
      'guest_id': guestId,
    });
  }

  Future<void> reconnect() async {
    if (roomCode == null || playerId == null) {
      _setError('Aucune session a reconnecter.');
      notifyListeners();
      return;
    }
    roomClosed = false;
    roomClosedReason = null;
    errorMessage = null;
    await _ensureConnected(force: true);
    final guestId = await _ensureGuestId();
    _send('join_room', {
      'room_code': roomCode,
      'player_id': playerId,
      'spectator': isSpectator,
      'guest_id': guestId,
    });
  }

  void sendMove(int cell) {
    if (roomCode == null || playerId == null) {
      return;
    }
    if (isSpectator) {
      return;
    }
    if (!isConnected) {
      return;
    }
    _send('move', {
      'room_code': roomCode,
      'player_id': playerId,
      'cell': cell,
    });
  }

  void leaveRoom() {
    _manualClose = true;
    _closeChannel();
    roomCode = null;
    playerId = null;
    symbol = null;
    role = null;
    state = null;
    roomClosed = false;
    roomClosedReason = null;
    errorMessage = null;
    connectionStatus = ConnectionStatus.disconnected;
    notifyListeners();
  }

  @override
  void dispose() {
    _manualClose = true;
    _closeChannel();
    super.dispose();
  }

  Future<void> _ensureConnected({bool force = false}) async {
    if (!force && _channel != null) {
      return;
    }
    await _connect();
  }

  Future<String> _ensureGuestId() async {
    if (_guestId != null) {
      return _guestId!;
    }
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString('ttt_guest_id');
    if (stored != null && stored.isNotEmpty) {
      _guestId = stored;
      return stored;
    }
    final bytes = List<int>.generate(16, (_) => _random.nextInt(256));
    final generated = base64UrlEncode(bytes);
    await prefs.setString('ttt_guest_id', generated);
    _guestId = generated;
    return generated;
  }

  Future<void> _connect() async {
    _closeChannel();
    connectionStatus = ConnectionStatus.connecting;
    notifyListeners();

    try {
      _manualClose = false;
      _channel = WebSocketChannel.connect(Uri.parse(serverUrl));
      _subscription = _channel!.stream.listen(
        _handleMessage,
        onError: (Object error) {
          _setError('Connexion interrompue.');
          connectionStatus = ConnectionStatus.error;
          notifyListeners();
        },
        onDone: () {
          if (_manualClose) {
            return;
          }
          connectionStatus = ConnectionStatus.disconnected;
          notifyListeners();
        },
      );
      connectionStatus = ConnectionStatus.connected;
      notifyListeners();
    } catch (error) {
      _setError('Impossible de se connecter au serveur.');
      connectionStatus = ConnectionStatus.error;
      notifyListeners();
    }
  }

  void _closeChannel() {
    _subscription?.cancel();
    _subscription = null;
    _channel?.sink.close();
    _channel = null;
  }

  void _send(String type, Map<String, dynamic> payload) {
    if (_channel == null) {
      return;
    }
    final message = jsonEncode({'type': type, 'payload': payload});
    _channel!.sink.add(message);
  }

  void _handleMessage(dynamic message) {
    if (message is! String) {
      return;
    }

    final decoded = jsonDecode(message) as Map<String, dynamic>;
    final type = decoded['type'] as String? ?? '';
    final payload = decoded['payload'] as Map<String, dynamic>? ?? const {};

    switch (type) {
      case 'room_created':
      case 'room_joined':
        _applyRoomResponse(payload);
        break;
      case 'state':
        _applyState(payload);
        break;
      case 'player_left':
        errorMessage = isSpectator
            ? 'Joueur deconnecte. Il a 1 minute pour revenir.'
            : 'Adversaire deconnecte. Il a 1 minute pour revenir.';
        break;
      case 'room_closed':
        roomClosed = true;
        roomClosedReason = payload['reason'] as String? ?? 'room_closed';
        connectionStatus = ConnectionStatus.disconnected;
        break;
      case 'error':
        _setError(payload['message'] as String? ?? 'Erreur inconnue.');
        break;
      default:
        break;
    }

    notifyListeners();
  }

  void _applyRoomResponse(Map<String, dynamic> payload) {
    roomCode = payload['room_code'] as String? ?? roomCode;
    playerId = payload['player_id'] as String? ?? playerId;
    final incomingSymbol = payload['symbol'] as String?;
    if (incomingSymbol != null && incomingSymbol.isNotEmpty) {
      symbol = incomingSymbol;
    }
    role = payload['role'] as String? ?? role;
    if (role == 'spectator') {
      symbol = null;
    }

    final stateJson = payload['state'] as Map<String, dynamic>?;
    if (stateJson != null) {
      state = GameState.fromJson(stateJson);
    }
  }

  void _applyState(Map<String, dynamic> payload) {
    state = GameState.fromJson(payload);
  }

  void requestRematch() {
    if (roomCode == null || playerId == null) {
      return;
    }
    if (isSpectator) {
      return;
    }
    if (!isConnected) {
      return;
    }
    _send('rematch', {
      'room_code': roomCode,
      'player_id': playerId,
    });
  }

  void _setError(String message) {
    errorMessage = message;
  }
}

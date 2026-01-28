import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class AuthUser {
  AuthUser({
    required this.id,
    required this.username,
    this.avatar,
    required this.isGuest,
  });

  final int id;
  final String username;
  final String? avatar;
  final bool isGuest;

  factory AuthUser.fromJson(Map<String, dynamic> json) {
    return AuthUser(
      id: json['id'] as int? ?? 0,
      username: json['username'] as String? ?? '',
      avatar: json['avatar'] as String?,
      isGuest: json['is_guest'] as bool? ?? false,
    );
  }
}

class ProfileStats {
  ProfileStats({
    required this.total,
    required this.wins,
    required this.losses,
    required this.draws,
  });

  final int total;
  final int wins;
  final int losses;
  final int draws;

  factory ProfileStats.fromJson(Map<String, dynamic> json) {
    return ProfileStats(
      total: json['total'] as int? ?? 0,
      wins: json['wins'] as int? ?? 0,
      losses: json['losses'] as int? ?? 0,
      draws: json['draws'] as int? ?? 0,
    );
  }
}

enum LoadStatus { idle, loading, ready }

class ProfileController extends ChangeNotifier {
  ProfileController({required String serverUrl}) : _apiBase = _buildApiBase(serverUrl);

  static const _accessTokenKey = 'ttt_access_token';
  static const _refreshTokenKey = 'ttt_refresh_token';

  final String _apiBase;

  AuthUser? user;
  ProfileStats? stats;
  String? accessToken;
  String? refreshToken;
  String? authError;
  String? statsError;
  LoadStatus authStatus = LoadStatus.idle;
  LoadStatus statsStatus = LoadStatus.idle;

  String get apiBase => _apiBase;

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    refreshToken = prefs.getString(_refreshTokenKey);
    accessToken = prefs.getString(_accessTokenKey);
    if (refreshToken != null && refreshToken!.isNotEmpty) {
      await refreshSession();
    }
    if (accessToken != null && accessToken!.isNotEmpty) {
      await loadStats();
    }
  }

  Future<void> setRefreshToken(String token) async {
    refreshToken = token.trim();
    final prefs = await SharedPreferences.getInstance();
    if (refreshToken == null || refreshToken!.isEmpty) {
      await prefs.remove(_refreshTokenKey);
    } else {
      await prefs.setString(_refreshTokenKey, refreshToken!);
    }
    notifyListeners();
  }

  Future<void> refreshSession() async {
    final token = refreshToken;
    if (token == null || token.isEmpty) {
      authError = 'Aucun jeton de session.';
      authStatus = LoadStatus.ready;
      notifyListeners();
      return;
    }

    authStatus = LoadStatus.loading;
    authError = null;
    notifyListeners();

    try {
      final response = await http.post(
        Uri.parse(_apiUrl('/auth/refresh')),
        headers: const {'Content-Type': 'application/json'},
        body: jsonEncode({'refresh_token': token}),
      );

      if (response.statusCode < 200 || response.statusCode >= 300) {
        authError = 'Connexion invalide.';
        authStatus = LoadStatus.ready;
        notifyListeners();
        return;
      }

      final payload = jsonDecode(response.body) as Map<String, dynamic>;
      user = AuthUser.fromJson(payload['user'] as Map<String, dynamic>? ?? <String, dynamic>{});
      accessToken = payload['access_token'] as String?;
      final newRefresh = payload['refresh_token'] as String?;
      if (newRefresh != null && newRefresh.isNotEmpty) {
        refreshToken = newRefresh;
      }

      final prefs = await SharedPreferences.getInstance();
      if (accessToken != null && accessToken!.isNotEmpty) {
        await prefs.setString(_accessTokenKey, accessToken!);
      } else {
        await prefs.remove(_accessTokenKey);
      }
      if (refreshToken != null && refreshToken!.isNotEmpty) {
        await prefs.setString(_refreshTokenKey, refreshToken!);
      }
      authStatus = LoadStatus.ready;
      notifyListeners();
    } catch (error) {
      authError = 'Erreur reseau.';
      authStatus = LoadStatus.ready;
      notifyListeners();
    }
  }

  Future<void> loadStats() async {
    final token = accessToken;
    if (token == null || token.isEmpty) {
      statsError = 'Non connecte.';
      statsStatus = LoadStatus.ready;
      notifyListeners();
      return;
    }

    statsStatus = LoadStatus.loading;
    statsError = null;
    notifyListeners();

    try {
      final response = await http.get(
        Uri.parse(_apiUrl('/api/stats')),
        headers: {'Authorization': 'Bearer $token'},
      );

      if (response.statusCode < 200 || response.statusCode >= 300) {
        statsError = 'Impossible de charger les stats.';
        statsStatus = LoadStatus.ready;
        notifyListeners();
        return;
      }

      final payload = jsonDecode(response.body) as Map<String, dynamic>;
      stats = ProfileStats.fromJson(payload);
      statsStatus = LoadStatus.ready;
      notifyListeners();
    } catch (error) {
      statsError = 'Erreur reseau.';
      statsStatus = LoadStatus.ready;
      notifyListeners();
    }
  }

  Future<void> authenticateWithRefreshToken(String token) async {
    await setRefreshToken(token);
    await refreshSession();
    await loadStats();
  }

  Future<void> logout() async {
    final token = accessToken;
    final refresh = refreshToken;
    if (token != null && token.isNotEmpty) {
      try {
        await http.post(
          Uri.parse(_apiUrl('/auth/logout')),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          },
          body: refresh != null && refresh.isNotEmpty
              ? jsonEncode({'refresh_token': refresh})
              : null,
        );
      } catch (error) {
        // Ignore network errors on logout.
      }
    }

    user = null;
    stats = null;
    accessToken = null;
    refreshToken = null;
    authError = null;
    statsError = null;
    authStatus = LoadStatus.idle;
    statsStatus = LoadStatus.idle;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_accessTokenKey);
    await prefs.remove(_refreshTokenKey);
    notifyListeners();
  }

  String _apiUrl(String path) {
    if (_apiBase.endsWith('/')) {
      return '${_apiBase.substring(0, _apiBase.length - 1)}$path';
    }
    return '$_apiBase$path';
  }

  static String _buildApiBase(String serverUrl) {
    final uri = Uri.parse(serverUrl);
    final scheme = uri.scheme == 'wss' ? 'https' : 'http';
    final base = Uri(
      scheme: scheme,
      host: uri.host,
      port: uri.hasPort ? uri.port : null,
    );
    return base.toString();
  }
}

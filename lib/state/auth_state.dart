import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import '../core/api_client.dart';
import '../core/api_error.dart';
import '../models/record.dart';

class AuthState extends ChangeNotifier {
  final ApiClient api;
  RecordData? profile;
  bool loading = true;
  String? error;
  AuthState(this.api) {
    api.onExpired = () {
      profile = null;
      notifyListeners();
    };
  }
  String get role => '${profile?['role'] ?? ''}';
  bool get signedIn => profile != null;
  String get home => switch (role) {
    'admin' => '/admin/reports',
    'operator' => '/shift',
    _ => '/catalog',
  };
  Future<void> init() async {
    await api.restore();
    try {
      if (api.session != null) await loadProfile();
    } on ApiError catch (e) {
      error = e.message;
    }
    loading = false;
    notifyListeners();
  }

  Future<void> loadProfile() async {
    final user = api.session?['user'];
    if (user == null) return;
    final result = await api.request(
      'profiles',
      query: {
        'id': 'eq.${user['id']}',
        'active': 'eq.true',
        'deleted_at': 'is.null',
      },
    );
    if ((result.data as List).isEmpty) {
      await api.clear();
      profile = null;
      throw const ApiError(
        'Учётная запись отключена. Обратитесь к администратору.',
        status: 403,
      );
    }
    profile = RecordData.from((result.data as List).single);
  }

  Future<void> login(String email, String password) async {
    final result = await api.auth('token?grant_type=password', {
      'email': email.trim(),
      'password': password,
    });
    await api.save(result);
    await loadProfile();
    error = null;
    notifyListeners();
  }

  Future<bool> register(String name, String email, String password) async {
    final result = await api.auth('signup', {
      'email': email.trim(),
      'password': password,
      'data': {'full_name': name.trim()},
    });
    if (result['access_token'] == null) return false;
    await api.save(result);
    await loadProfile();
    notifyListeners();
    return true;
  }

  Future<void> logout() async {
    try {
      await api.dio.post(
        '/auth/v1/logout',
        options: Options(
          headers: {
            'apikey': api.key,
            'Authorization': 'Bearer ${api.session?['access_token']}',
          },
        ),
      );
    } catch (_) {
      /* Local sign-out always completes. */
    }
    await api.clear();
    profile = null;
    error = null;
    notifyListeners();
  }
}

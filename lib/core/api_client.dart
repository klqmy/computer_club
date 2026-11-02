import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/record.dart';
import 'api_error.dart';

class ApiClient {
  final Dio dio;
  final String key;
  final SharedPreferences prefs;
  RecordData? session;
  void Function()? onExpired;
  Future<void>? _refreshing;
  ApiClient(String baseUrl, this.key, this.prefs, {Dio? transport})
    : dio =
          transport ??
          Dio(
            BaseOptions(
              baseUrl: baseUrl,
              connectTimeout: const Duration(seconds: 12),
              receiveTimeout: const Duration(seconds: 20),
              sendTimeout: const Duration(seconds: 15),
            ),
          );

  Future<void> restore() async {
    try {
      final saved = prefs.getString('pulse.session');
      if (saved != null) session = RecordData.from(jsonDecode(saved));
    } catch (_) {
      await clear();
    }
  }

  Future<void> save(RecordData value) async {
    session = value;
    await prefs.setString('pulse.session', jsonEncode(value));
  }

  Future<void> clear() async {
    session = null;
    await prefs.remove('pulse.session');
  }

  Future<RecordData> auth(String path, RecordData data) async {
    try {
      final response = await dio.post(
        '/auth/v1/$path',
        data: data,
        options: Options(headers: {'apikey': key}),
      );
      return RecordData.from(response.data);
    } on DioException catch (e) {
      throw ApiError.fromDio(e);
    }
  }

  Future<void> refresh() async {
    if (_refreshing != null) return _refreshing!;
    final task = _doRefresh();
    _refreshing = task;
    try {
      await task;
    } finally {
      _refreshing = null;
    }
  }

  Future<void> _doRefresh() async {
    final token = session?['refresh_token'];
    if (token == null) throw const ApiError('Войдите в систему', status: 401);
    try {
      final result = await auth('token?grant_type=refresh_token', {
        'refresh_token': token,
      });
      await save(result);
    } on ApiError catch (e) {
      // A network outage must not erase a valid saved session.
      if (e.status == 400 || e.status == 401 || e.status == 403) {
        await clear();
        onExpired?.call();
      }
      rethrow;
    }
  }

  Future<Response<dynamic>> request(
    String path, {
    String method = 'GET',
    RecordData? query,
    dynamic data,
    bool retried = false,
    CancelToken? cancelToken,
  }) async {
    try {
      return await dio.request(
        '/rest/v1/$path',
        queryParameters: query,
        data: data,
        cancelToken: cancelToken,
        options: Options(
          method: method,
          headers: {
            'apikey': key,
            if (session?['access_token'] != null)
              'Authorization': 'Bearer ${session!['access_token']}',
            'Prefer': method == 'GET' ? 'count=exact' : 'return=representation',
          },
        ),
      );
    } on DioException catch (e) {
      if (CancelToken.isCancel(e)) rethrow;
      if (e.response?.statusCode == 401 && !retried && session != null) {
        await refresh();
        return request(
          path,
          method: method,
          query: query,
          data: data,
          retried: true,
          cancelToken: cancelToken,
        );
      }
      throw ApiError.fromDio(e);
    }
  }

  Future<dynamic> rpc(String name, RecordData data) async =>
      (await request('rpc/$name', method: 'POST', data: data)).data;
}

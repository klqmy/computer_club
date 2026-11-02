import 'dart:convert';
import 'package:dio/dio.dart';

class ApiError implements Exception {
  final String message;
  final int? status;
  final Map<String, String> fields;
  const ApiError(this.message, {this.status, this.fields = const {}});
  factory ApiError.fromDio(DioException e) {
    final status = e.response?.statusCode;
    if ([
      DioExceptionType.connectionTimeout,
      DioExceptionType.receiveTimeout,
      DioExceptionType.sendTimeout,
    ].contains(e.type)) {
      return const ApiError('Сервер не ответил вовремя. Попробуйте ещё раз.');
    }
    if (e.response == null) {
      return const ApiError(
        'Нет связи с сервером. Проверьте интернет и повторите запрос.',
      );
    }
    final data = e.response?.data;
    final body = data is Map ? data : <String, dynamic>{};
    var fields = <String, String>{};
    if (status == 422) {
      try {
        final details = body['details'] is String
            ? jsonDecode(body['details'])
            : body['details'];
        if (details is Map) {
          fields = details.map((k, v) => MapEntry('$k', '$v'));
        }
      } catch (_) {
        /* A plain server message can accompany a validation error. */
      }
    }
    final text =
        '${body['msg'] ?? body['message'] ?? body['error_description'] ?? ''}';
    return ApiError(
      switch (status) {
        401 => 'Сессия истекла. Войдите снова.',
        403 => 'У вашей роли нет доступа к этой операции.',
        409 =>
          text.isNotEmpty && !text.contains('constraint')
              ? text
              : 'Конфликт: запись уже существует или используется в связанных данных.',
        422 => text.isEmpty ? 'Проверьте поля формы' : text,
        429 => 'Слишком много запросов. Повторите чуть позже.',
        _ =>
          text.isEmpty ? 'Ошибка сервера ($status). Повторите запрос.' : text,
      },
      status: status,
      fields: fields,
    );
  }
  @override
  String toString() => message;
}

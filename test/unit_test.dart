import 'package:computer_club/core/access.dart';
import 'package:computer_club/core/api_client.dart';
import 'package:computer_club/core/api_error.dart';
import 'package:computer_club/models/catalog.dart';
import 'package:computer_club/models/list_query.dart';
import 'package:computer_club/models/record.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:typed_data';

class Adapter implements HttpClientAdapter {
  final Future<ResponseBody> Function(RequestOptions) handle;
  Adapter(this.handle);
  @override
  Future<ResponseBody> fetch(
    RequestOptions o,
    Stream<Uint8List>? body,
    Future<void>? cancel,
  ) => handle(o);
  @override
  void close({bool force = false}) {}
}

ResponseBody jsonBody(String json, int status) => ResponseBody.fromString(
  json,
  status,
  headers: {
    'content-type': ['application/json'],
  },
);
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('У каждой роли есть недоступные остальным разделы', () {
    expect(routeAllowed('admin', '/admin/users'), isTrue);
    expect(routeAllowed('operator', '/admin/users'), isFalse);
    expect(routeAllowed('admin', '/shift'), isFalse);
    expect(routeAllowed('operator', '/shift'), isTrue);
    expect(routeAllowed('client', '/catalog'), isTrue);
    expect(routeAllowed('admin', '/catalog'), isFalse);
    expect(routeAllowed('client', '/manage/payments'), isFalse);
    expect(routeAllowed('admin', '/manage/unknown'), isFalse);
  });
  test('Параметры списка проходят полный цикл URL', () {
    final q = ListQuery.fromUri(
      Uri.parse(
        '/manage/stations?q=Ryzen&zone_id=2&state=ready&ram_gb=64&page=3&size=20&sort=name&dir=desc&trash=deleted',
      ),
      entities['stations']!,
    );
    final copy = ListQuery.fromUri(
      Uri(path: '/manage/stations', queryParameters: q.toUrl()),
      entities['stations']!,
    );
    expect(copy.toUrl(), q.toUrl());
    expect(copy.toApi(entities['stations']!)['offset'], 40);
  });
  test(
    'Неверные страница, размер и SQL-подобная сортировка заменяются безопасными',
    () {
      final q = ListQuery.fromUri(
        Uri.parse('/?page=-2&size=10000&sort=id;drop&role=admin'),
        entities['games']!,
      );
      expect(q.page, 1);
      expect(q.size, 10);
      expect(q.sort, 'id');
      expect(q.filters, isEmpty);
    },
  );
  test('Поиск не позволяет добавить управляющие выражения PostgREST', () {
    final p = const ListQuery(
      search: 'test),role.eq.admin',
    ).toApi(entities['games']!);
    expect(
      p['or'],
      '(title.ilike.*testrole.eq.admin*,genre.ilike.*testrole.eq.admin*)',
    );
  });
  test('Валидация проверяет формат, диапазон и целочисленность', () {
    expect(entities['customers']!.field('email').validate('no-at'), isNotNull);
    expect(entities['stations']!.field('ram_gb').validate('2'), isNotNull);
    expect(entities['stations']!.field('ram_gb').validate('32.5'), isNotNull);
    expect(
      entities['customers']!.field('phone').validate('----------'),
      isNotNull,
    );
    expect(entities['tariffs']!.field('price_per_hour').parse('150,50'), 150.5);
  });
  test('Не существующие даты и значения справочника отклоняются', () {
    expect(
      const FieldSpec(
        'date',
        'Дата',
        kind: FieldKind.date,
      ).validate('2026-02-31'),
      isNotNull,
    );
    expect(entities['bookings']!.field('status').validate('fake'), isNotNull);
    expect(entities['games']!.field('title').validate('  '), isNotNull);
    expect(
      entities['bookings']!.field('starts_at').validate('2026-11-02T18:70'),
      isNotNull,
    );
    expect(
      entities['bookings']!
          .field('starts_at')
          .validate('2026-11-02T00:10+03:00'),
      isNull,
    );
    expect(
      entities['tariffs']!.field('price_per_hour').validate('NaN'),
      isNotNull,
    );
  });
  test('Повреждённые значения фильтров из URL не попадают в запрос', () {
    final q = ListQuery.fromUri(
      Uri.parse('/?state=unknown&zone_id=-1&ram_gb=NaN'),
      entities['stations']!,
    );
    expect(q.filters, isEmpty);
  });
  test('422 сохраняет ошибки конкретных полей', () {
    final e = ApiError.fromDio(
      DioException(
        requestOptions: RequestOptions(),
        response: Response(
          requestOptions: RequestOptions(),
          statusCode: 422,
          data: {
            'message': 'Проверьте поля',
            'details': '{"ram_gb":"Минимум 4"}',
          },
        ),
      ),
    );
    expect(e.status, 422);
    expect(e.fields['ram_gb'], 'Минимум 4');
  });
  test('Таймаут и отсутствие сети имеют понятные сообщения', () {
    expect(
      ApiError.fromDio(
        DioException(
          requestOptions: RequestOptions(),
          type: DioExceptionType.receiveTimeout,
        ),
      ).message,
      contains('вовремя'),
    );
    expect(
      ApiError.fromDio(
        DioException(
          requestOptions: RequestOptions(),
          type: DioExceptionType.connectionError,
        ),
      ).message,
      contains('Нет связи'),
    );
  });
  test('При двух одновременных 401 токен обновляется один раз', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    var refreshes = 0;
    final dio = Dio(BaseOptions(baseUrl: 'https://unit.example'));
    dio.httpClientAdapter = Adapter((o) async {
      if (o.path.contains('/auth/')) {
        refreshes++;
        await Future<void>.delayed(const Duration(milliseconds: 20));
        return jsonBody('{"access_token":"new","refresh_token":"next"}', 200);
      }
      return jsonBody(
        o.headers['Authorization'] == 'Bearer new'
            ? '[]'
            : '{"message":"expired"}',
        o.headers['Authorization'] == 'Bearer new' ? 200 : 401,
      );
    });
    final api = ApiClient(
      'https://unit.example',
      'public',
      prefs,
      transport: dio,
    );
    await api.save({'access_token': 'old', 'refresh_token': 'refresh'});
    await Future.wait([api.request('games'), api.request('zones')]);
    expect(refreshes, 1);
    expect(api.session!['access_token'], 'new');
    final restored = ApiClient('https://unit.example', 'public', prefs);
    await restored.restore();
    expect(restored.session!['refresh_token'], 'next');
  });
  test('Потеря сети при обновлении не удаляет сохранённую сессию', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final dio = Dio(BaseOptions(baseUrl: 'https://unit.example'));
    dio.httpClientAdapter = Adapter((o) async {
      throw DioException(
        requestOptions: o,
        type: DioExceptionType.connectionError,
      );
    });
    final api = ApiClient(
      'https://unit.example',
      'public',
      prefs,
      transport: dio,
    );
    await api.save({'access_token': 'old', 'refresh_token': 'refresh'});
    await expectLater(api.refresh(), throwsA(isA<ApiError>()));
    expect(api.session, isNotNull);
    expect(prefs.getString('pulse.session'), isNotNull);
  });
}

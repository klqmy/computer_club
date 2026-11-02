import 'package:computer_club/core/api_client.dart';
import 'package:computer_club/core/api_error.dart';
import 'package:computer_club/models/catalog.dart';
import 'package:computer_club/models/list_query.dart';
import 'package:computer_club/models/record.dart';
import 'package:computer_club/repositories/club_repository.dart';
import 'package:computer_club/screens/auth_screen.dart';
import 'package:computer_club/screens/entity_screen.dart';
import 'package:computer_club/state/auth_state.dart';
import 'package:computer_club/widgets/async_panel.dart';
import 'package:computer_club/widgets/record_form.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FakeRepository implements ClubRepository {
  bool fieldError = false;
  @override
  Future<PageResult> list(
    EntitySpec s,
    ListQuery q, {
    CancelToken? cancelToken,
  }) async => const PageResult([], 0);
  @override
  Future<RecordData> get(EntitySpec s, int id) async => {};
  @override
  Future<List<RecordData>> references(String key) async => [];
  @override
  Future<RecordData> save(EntitySpec s, RecordData v, {int? id}) async {
    if (fieldError) {
      throw const ApiError(
        'Проверьте поля',
        status: 422,
        fields: {'name': 'Название уже занято сервером'},
      );
    }
    return {'id': 1, ...v};
  }

  @override
  Future<void> remove(EntitySpec s, List<int> ids, String action) async {}
  @override
  Future<dynamic> command(String name, RecordData values) async => {};
}

Future<AuthState> auth() async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  return AuthState(ApiClient('https://unit.example', 'public', prefs))
    ..profile = {'role': 'admin', 'full_name': 'Тест'}
    ..loading = false;
}

Widget app(Widget child, AuthState state, FakeRepository repo) => MultiProvider(
  providers: [
    ChangeNotifierProvider.value(value: state),
    Provider<ClubRepository>.value(value: repo),
  ],
  child: MaterialApp(home: Scaffold(body: child)),
);
void main() {
  testWidgets('Вход показывает ошибки пустого email и пароля', (t) async {
    await t.pumpWidget(app(const AuthScreen(), await auth(), FakeRepository()));
    await t.tap(find.widgetWithText(FilledButton, 'Войти'));
    await t.pump();
    expect(find.text('Заполните поле'), findsOneWidget);
    expect(find.text('Введите пароль'), findsOneWidget);
  });
  testWidgets('Регистрация открывает ФИО и проверяет длину пароля', (t) async {
    await t.pumpWidget(app(const AuthScreen(), await auth(), FakeRepository()));
    await t.tap(find.text('Нет аккаунта? Зарегистрироваться'));
    await t.pump();
    expect(find.text('ФИО'), findsOneWidget);
    await t.enterText(find.byType(TextFormField).at(2), '123');
    await t.tap(find.widgetWithText(FilledButton, 'Создать аккаунт'));
    await t.pump();
    expect(find.text('От 8 до 72 символов'), findsOneWidget);
  });
  testWidgets('Загрузка, пустой результат и ошибка различаются', (t) async {
    Widget panel(bool loading, bool empty, String? error) => MaterialApp(
      home: Scaffold(
        body: AsyncPanel(
          loading: loading,
          empty: empty,
          error: error,
          onRetry: () {},
          child: const Text('Данные'),
        ),
      ),
    );
    await t.pumpWidget(panel(true, false, null));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Ничего не найдено'), findsNothing);
    await t.pumpWidget(panel(false, true, null));
    expect(find.text('Ничего не найдено'), findsOneWidget);
    await t.pumpWidget(panel(false, false, 'Нет связи'));
    expect(find.text('Повторить'), findsOneWidget);
    await t.pumpWidget(panel(false, false, null));
    expect(find.text('Данные'), findsOneWidget);
  });
  testWidgets('Повторная загрузка вызывается кнопкой ошибки', (t) async {
    var calls = 0;
    await t.pumpWidget(
      MaterialApp(
        home: AsyncPanel(
          loading: false,
          empty: false,
          error: 'Нет связи',
          onRetry: () => calls++,
          child: const SizedBox(),
        ),
      ),
    );
    await t.tap(find.text('Повторить'));
    expect(calls, 1);
  });
  testWidgets('Ошибка 422 появляется у конкретного поля формы', (t) async {
    final repo = FakeRepository()..fieldError = true;
    await t.pumpWidget(
      app(RecordForm(spec: entities['zones']!), await auth(), repo),
    );
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextFormField).at(0), 'Арена');
    await t.enterText(find.byType(TextFormField).at(2), '10');
    await t.tap(find.text('Сохранить'));
    await t.pumpAndSettle();
    expect(find.text('Название уже занято сервером'), findsOneWidget);
  });
  testWidgets('Список остаётся работоспособным при ширине 360', (t) async {
    t.view.physicalSize = const Size(360, 800);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    await t.pumpWidget(
      app(
        EntityScreen(spec: entities['zones']!, uri: Uri.parse('/manage/zones')),
        await auth(),
        FakeRepository(),
      ),
    );
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
    expect(find.text('Игровые зоны'), findsOneWidget);
    expect(find.text('Ничего не найдено'), findsOneWidget);
  });
}

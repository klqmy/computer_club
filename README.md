# Компьютерный клуб «Пульс»

Flutter Web + Supabase (PostgreSQL, Auth, REST). Flutter 3.35.4, Dart 3.9.2.

```sh
flutter pub get
flutter run -d chrome --dart-define-from-file=build-config.json
flutter analyze
flutter test
flutter build web --release --pwa-strategy=none --dart-define-from-file=build-config.json
```

В VS Code можно выбрать запуск «Пульс · Web». В `build-config.json` находятся адрес API и публичный publishable key; доступ к данным проверяет RLS в базе.

Для своей базы создайте бесплатный проект Supabase, выполните SQL из `supabase/migrations` по порядку и укажите свои публичные параметры сборки. Регистрация создаёт клиента. Для тестовых данных сначала создайте в Supabase Auth пользователей `admin@pulse-club.example`, `operator@pulse-club.example`, `client@pulse-club.example`, затем выполните `supabase/seed.sql`. Пароли задаются в Auth отдельно. Служебные ключи в клиент добавлять нельзя.

GitHub Actions проверяет код и тесты, собирает Web и прикладывает архив сборки к релизу с SHA коммита. Render публикует прошедшую CI сборку и перенаправляет внутренние адреса на `index.html`. Настройки размещения — `render.yaml`.

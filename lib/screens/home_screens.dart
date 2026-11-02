import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../core/api_client.dart';
import '../models/catalog.dart';
import '../models/list_query.dart';
import '../models/record.dart';
import '../repositories/club_repository.dart';
import '../widgets/async_panel.dart';
import '../widgets/record_form.dart';

class OverviewScreen extends StatefulWidget {
  final bool operatorView;
  const OverviewScreen({super.key, this.operatorView = false});
  @override
  State<OverviewScreen> createState() => _OverviewScreenState();
}

class _OverviewScreenState extends State<OverviewScreen> {
  bool loading = true;
  String? error;
  final data = <String, PageResult>{};
  RecordData summary = {};
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final repo = context.read<ClubRepository>();
      summary = RecordData.from(await repo.command('club_summary', {}));
      final results = await Future.wait(
        ['stations', 'customers', 'bookings', 'sessions', 'payments'].map(
          (k) async => MapEntry(
            k,
            await repo.list(
              entities[k]!,
              const ListQuery(size: 1000, sort: 'created_at', descending: true),
            ),
          ),
        ),
      );
      if (mounted) data.addEntries(results);
    } catch (e) {
      error = '$e';
    }
    if (mounted) setState(() => loading = false);
  }

  Future<void> command(String key, RecordData initial) async {
    if (await editRecord(context, entities[key]!, initial: initial)) load();
  }

  @override
  Widget build(BuildContext context) {
    final bookings = data['bookings']?.rows ?? [];
    final sessions = data['sessions']?.rows ?? [];
    final active = sessions.where((s) => s['finished_at'] == null).toList();
    final upcoming =
        bookings
            .where(
              (b) =>
                  b['status'] == 'reserved' &&
                  DateTime.parse(b['ends_at']).isAfter(DateTime.now()),
            )
            .toList()
          ..sort((a, b) => '${a['starts_at']}'.compareTo('${b['starts_at']}'));
    final revenue = (summary['revenue'] as num?) ?? 0;
    return Padding(
      padding: EdgeInsets.all(MediaQuery.sizeOf(context).width < 600 ? 16 : 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  widget.operatorView ? 'Рабочая смена' : 'Обзор клуба',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
              ),
              IconButton(
                tooltip: 'Обновить',
                onPressed: load,
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            widget.operatorView
                ? 'Бронирования, сеансы и оплаты в одном месте'
                : 'Ресурсы клуба и показатели работы',
            style: const TextStyle(color: Color(0xff99a3b3)),
          ),
          const SizedBox(height: 24),
          Expanded(
            child: AsyncPanel(
              loading: loading,
              empty: false,
              error: error,
              onRetry: load,
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Wrap(
                      spacing: 16,
                      runSpacing: 16,
                      children: [
                        metric(
                          context,
                          'Компьютеры',
                          '${summary['stations'] ?? 0}',
                          Icons.computer,
                        ),
                        metric(
                          context,
                          'Активные сеансы',
                          '${summary['active_sessions'] ?? 0}',
                          Icons.play_circle_outline,
                        ),
                        metric(
                          context,
                          'Клиенты',
                          '${summary['customers'] ?? 0}',
                          Icons.people_outline,
                        ),
                        metric(
                          context,
                          'Оплачено за всё время',
                          '${revenue.toStringAsFixed(0)} ₽',
                          Icons.account_balance_wallet_outlined,
                        ),
                      ],
                    ),
                    const SizedBox(height: 32),
                    if (widget.operatorView) ...[
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          FilledButton.icon(
                            onPressed: () => command('bookings', {}),
                            icon: const Icon(Icons.add),
                            label: const Text('Новая бронь'),
                          ),
                          OutlinedButton.icon(
                            onPressed: () => context.go('/manage/customers'),
                            icon: const Icon(Icons.person_add_alt),
                            label: const Text('Клиенты'),
                          ),
                          OutlinedButton.icon(
                            onPressed: () => context.go('/manage/payments'),
                            icon: const Icon(Icons.receipt_long),
                            label: const Text('Журнал оплат'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 28),
                      Text(
                        'Сейчас играют',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 12),
                      if (active.isEmpty)
                        const Card(
                          child: Padding(
                            padding: EdgeInsets.all(24),
                            child: Text('Активных сеансов нет'),
                          ),
                        ),
                      for (final s in active)
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(20),
                            child: Wrap(
                              alignment: WrapAlignment.spaceBetween,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              spacing: 20,
                              runSpacing: 12,
                              children: [
                                Text(
                                  '${s['station_name']} · ${s['customer_name']}\nНачало: ${formatDate(s['started_at'])}',
                                ),
                                FilledButton(
                                  onPressed: () async {
                                    final row = RecordData.from(s)
                                      ..['finished_at'] = DateTime.now()
                                          .toUtc()
                                          .toIso8601String();
                                    if (await editRecord(
                                      context,
                                      entities['sessions']!,
                                      row: row,
                                    )) {
                                      load();
                                    }
                                  },
                                  child: const Text('Завершить сеанс'),
                                ),
                              ],
                            ),
                          ),
                        ),
                      const SizedBox(height: 28),
                    ],
                    Text(
                      'Ближайшие бронирования',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 12),
                    if (upcoming.isEmpty)
                      const Card(
                        child: Padding(
                          padding: EdgeInsets.all(24),
                          child: Text('Новых бронирований пока нет'),
                        ),
                      ),
                    for (final b in upcoming.take(12))
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Wrap(
                            alignment: WrapAlignment.spaceBetween,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            spacing: 20,
                            runSpacing: 12,
                            children: [
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${b['station_name']} · ${b['customer_name']}',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    '${formatDate(b['starts_at'])} — ${formatDate(b['ends_at'])}',
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    '${b['quoted_total']} ₽ · ${b['tariff_name']}',
                                    style: const TextStyle(
                                      color: Color(0xffc5f36b),
                                    ),
                                  ),
                                ],
                              ),
                              if (widget.operatorView)
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: [
                                    if (DateTime.parse(b['starts_at'])
                                        .subtract(const Duration(minutes: 15))
                                        .isBefore(DateTime.now()))
                                      FilledButton(
                                        onPressed: () => command('sessions', {
                                          'booking_id': b['id'],
                                          'started_at': DateTime.now()
                                              .toIso8601String(),
                                        }),
                                        child: const Text('Начать сеанс'),
                                      ),
                                    OutlinedButton(
                                      onPressed: () => command('payments', {
                                        'booking_id': b['id'],
                                        'amount': b['quoted_total'],
                                        'paid_at': DateTime.now()
                                            .toIso8601String(),
                                      }),
                                      child: const Text('Оплата'),
                                    ),
                                  ],
                                ),
                            ],
                          ),
                        ),
                      ),
                    if (!widget.operatorView) ...[
                      const SizedBox(height: 28),
                      Text(
                        'Состав клуба',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          for (final key in [
                            'zones',
                            'stations',
                            'games',
                            'tariffs',
                            'memberships',
                          ])
                            OutlinedButton(
                              onPressed: () => context.go('/manage/$key'),
                              child: Text(entities[key]!.title),
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

Widget metric(
  BuildContext context,
  String title,
  String value,
  IconData icon,
) => SizedBox(
  width: 230,
  child: Card(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: const Color(0xffc5f36b)),
          const SizedBox(height: 24),
          Text(
            value,
            style: Theme.of(
              context,
            ).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(title, style: const TextStyle(color: Color(0xff99a3b3))),
        ],
      ),
    ),
  ),
);

class UsersScreen extends StatefulWidget {
  const UsersScreen({super.key});
  @override
  State<UsersScreen> createState() => _UsersScreenState();
}

class _UsersScreenState extends State<UsersScreen> {
  bool loading = true;
  String? error;
  List<RecordData> rows = [];
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final result = await context.read<ApiClient>().request(
        'profiles',
        query: {'order': 'created_at.asc'},
      );
      rows = (result.data as List).map((r) => RecordData.from(r)).toList();
    } catch (e) {
      error = '$e';
    }
    if (mounted) setState(() => loading = false);
  }

  Future<void> save(RecordData row, RecordData patch) async {
    try {
      await context.read<ApiClient>().request(
        'profiles',
        method: 'PATCH',
        query: {'id': 'eq.${row['id']}'},
        data: patch,
      );
      load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(24),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Пользователи и роли',
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        const SizedBox(height: 12),
        const Text(
          'Новые пользователи регистрируются клиентами. Только администратор назначает другие роли.',
        ),
        const SizedBox(height: 24),
        Expanded(
          child: AsyncPanel(
            loading: loading,
            empty: rows.isEmpty,
            error: error,
            onRetry: load,
            child: ListView(
              children: [
                for (final row in rows)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 24,
                        runSpacing: 16,
                        children: [
                          SizedBox(
                            width: 230,
                            child: Text('${row['full_name']}'),
                          ),
                          SizedBox(
                            width: 220,
                            child: DropdownButtonFormField<String>(
                              initialValue: row['role'],
                              decoration: const InputDecoration(
                                labelText: 'Роль',
                              ),
                              items: [
                                for (final e in roles.entries)
                                  DropdownMenuItem(
                                    value: e.key,
                                    child: Text(e.value),
                                  ),
                              ],
                              onChanged: (v) => save(row, {'role': v}),
                            ),
                          ),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Text('Активен'),
                              Switch(
                                value: row['active'] == true,
                                onChanged: (v) => save(row, {'active': v}),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}

class MembershipScreen extends StatefulWidget {
  const MembershipScreen({super.key});
  @override
  State<MembershipScreen> createState() => _MembershipScreenState();
}

class _MembershipScreenState extends State<MembershipScreen> {
  bool loading = true;
  String? error;
  List<RecordData> cards = [], customers = [];
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final repo = context.read<ClubRepository>();
      cards = await repo.references('memberships');
      customers = await repo.references('customers');
    } catch (e) {
      error = '$e';
    }
    if (mounted) setState(() => loading = false);
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(24),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Моя клубная карта',
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        const SizedBox(height: 24),
        Expanded(
          child: AsyncPanel(
            loading: loading,
            empty: false,
            error: error,
            onRetry: load,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (cards.isEmpty)
                    const Card(
                      child: Padding(
                        padding: EdgeInsets.all(28),
                        child: Text(
                          'Карта ещё не оформлена. Обратитесь к администратору клуба.',
                        ),
                      ),
                    ),
                  for (final card in cards)
                    Container(
                      width: 480,
                      padding: const EdgeInsets.all(28),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(24),
                        gradient: const LinearGradient(
                          colors: [Color(0xff344932), Color(0xff193342)],
                        ),
                        border: Border.all(
                          color: const Color(0xffc5f36b).withValues(alpha: .4),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'ПУЛЬС  /  CLUB MEMBER',
                            style: TextStyle(
                              letterSpacing: 2,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 36),
                          Text(
                            '${card['discount_percent']}%',
                            style: const TextStyle(
                              fontSize: 64,
                              fontWeight: FontWeight.w900,
                              color: Color(0xffc5f36b),
                            ),
                          ),
                          Text(
                            'скидка на игровое время · ${entities['memberships']!.field('level').choices[card['level']]}',
                          ),
                          const SizedBox(height: 32),
                          Text(
                            '${card['card_number']}',
                            style: const TextStyle(
                              fontSize: 24,
                              letterSpacing: 3,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'Действует до ${formatDate(card['valid_until'])}',
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 28),
                  if (customers.isNotEmpty) ...[
                    Text(
                      '${customers.first['full_name']}',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    Text('${customers.first['email']}'),
                    const SizedBox(height: 16),
                    const Text(
                      'Скидка автоматически учитывается сервером при бронировании. Ночная скидка действует для интервала целиком с 22:00 до 08:00 по Москве.',
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ],
    ),
  );
}

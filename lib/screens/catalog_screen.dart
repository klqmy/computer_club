import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../models/catalog.dart';
import '../models/list_query.dart';
import '../models/record.dart';
import '../repositories/club_repository.dart';
import '../widgets/async_panel.dart';
import '../widgets/filter_panel.dart';
import '../widgets/record_form.dart';

class CatalogScreen extends StatefulWidget {
  final Uri uri;
  const CatalogScreen({super.key, required this.uri});
  @override
  State<CatalogScreen> createState() => _CatalogScreenState();
}

class _CatalogScreenState extends State<CatalogScreen> {
  bool loading = true;
  String? error;
  PageResult? data;
  List<RecordData> zones = [], busyIntervals = [], installed = [], games = [];
  late ListQuery query;
  late DateTime start;
  late int hours;
  final search = TextEditingController();
  int generation = 0;
  @override
  void initState() {
    super.initState();
    read();
    load();
  }

  @override
  void didUpdateWidget(covariant CatalogScreen old) {
    super.didUpdateWidget(old);
    if (old.uri != widget.uri) {
      read();
      load();
    }
  }

  @override
  void dispose() {
    generation++;
    search.dispose();
    super.dispose();
  }

  void read() {
    query = ListQuery.fromUri(widget.uri, entities['stations']!);
    search.text = query.search;
    final now = DateTime.now();
    start =
        DateTime.tryParse(widget.uri.queryParameters['from'] ?? '') ??
        DateTime(now.year, now.month, now.day, now.hour + 1);
    hours = (int.tryParse(widget.uri.queryParameters['hours'] ?? '') ?? 2)
        .clamp(1, 12);
  }

  void update(Map<String, String?> patch) {
    final p = {
      ...query.toUrl(),
      'page': '1',
      'from': start.toIso8601String().substring(0, 16),
      'hours': '$hours',
    };
    patch.forEach((k, v) {
      if (v == null || v.isEmpty) {
        p.remove(k);
      } else {
        p[k] = v;
      }
    });
    context.go(widget.uri.replace(queryParameters: p).toString());
  }

  Future<void> load() async {
    final current = ++generation;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final repo = context.read<ClubRepository>();
      final results = await Future.wait<dynamic>([
        repo.list(entities['stations']!, query),
        repo.references('zones'),
        repo.command('availability', {
          'p_from': start.toUtc().toIso8601String(),
          'p_to': start.add(Duration(hours: hours)).toUtc().toIso8601String(),
        }),
        repo.references('station_games'),
        repo.references('games'),
      ]);
      if (mounted && current == generation) {
        data = results[0];
        zones = results[1];
        busyIntervals = (results[2] as List)
            .map((r) => RecordData.from(r))
            .toList();
        installed = results[3];
        games = results[4];
      }
    } catch (e) {
      if (current == generation) error = '$e';
    }
    if (mounted && current == generation) setState(() => loading = false);
  }

  Future<void> chooseStart() async {
    final day = await showDatePicker(
      context: context,
      initialDate: start,
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (day == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(start),
    );
    if (time == null || !mounted) return;
    update({
      'from': DateTime(
        day.year,
        day.month,
        day.day,
        time.hour,
        time.minute,
      ).toIso8601String().substring(0, 16),
    });
  }

  Future<void> book(RecordData station) async {
    final result = await editRecord(
      context,
      entities['bookings']!,
      initial: {
        'station_id': station['id'],
        'starts_at': start.toIso8601String(),
        'ends_at': start.add(Duration(hours: hours)).toIso8601String(),
        'status': 'reserved',
      },
    );
    if (result && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Бронирование создано. Оно сохранено в личном кабинете.',
          ),
        ),
      );
      load();
    }
  }

  Widget select(String label, String key, Map<String, String> values) =>
      SizedBox(
        width: 190,
        child: DropdownButtonFormField<String>(
          isExpanded: true,
          key: ValueKey('$key-${query.filters[key]}'),
          initialValue: values.containsKey(query.filters[key])
              ? query.filters[key]
              : '',
          decoration: InputDecoration(labelText: label),
          items: [
            const DropdownMenuItem(value: '', child: Text('Все')),
            for (final e in values.entries)
              DropdownMenuItem(
                value: e.key,
                child: Text(e.value, overflow: TextOverflow.ellipsis),
              ),
          ],
          onChanged: (v) => update({key: v}),
        ),
      );
  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.all(MediaQuery.sizeOf(context).width < 600 ? 16 : 32),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Выбери своё место',
          style: Theme.of(
            context,
          ).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        const Text(
          'Свободное время, подходящее железо и твоя любимая игра.',
          style: TextStyle(color: Color(0xff99a3b3)),
        ),
        const SizedBox(height: 24),
        FilterPanel(
          child: Wrap(
            spacing: 12,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              OutlinedButton.icon(
                onPressed: chooseStart,
                icon: const Icon(Icons.calendar_month_outlined),
                label: Text(formatDate(start.toIso8601String())),
              ),
              SizedBox(
                width: 150,
                child: DropdownButtonFormField<int>(
                  initialValue: hours,
                  decoration: const InputDecoration(
                    labelText: 'Продолжительность',
                  ),
                  items: [
                    for (var n = 1; n <= 12; n++)
                      DropdownMenuItem(value: n, child: Text('$n ч.')),
                  ],
                  onChanged: (v) => update({'hours': '$v'}),
                ),
              ),
              SizedBox(
                width: 240,
                child: TextField(
                  controller: search,
                  decoration: const InputDecoration(
                    labelText: 'Найти компьютер',
                    prefixIcon: Icon(Icons.search),
                  ),
                  onSubmitted: (v) => update({'q': v}),
                ),
              ),
              select('Игровая зона', 'zone_id', {
                for (final z in zones) '${z['id']}': '${z['name']}',
              }),
              select('Состояние', 'state', stationStates),
              select('ОЗУ', 'ram_gb', {
                '16': '16 ГБ',
                '32': '32 ГБ',
                '64': '64 ГБ',
              }),
              SizedBox(
                width: 170,
                child: DropdownButtonFormField<String>(
                  initialValue: ['id', 'name', 'ram_gb'].contains(query.sort)
                      ? query.sort
                      : 'id',
                  decoration: const InputDecoration(labelText: 'Сортировка'),
                  isExpanded: true,
                  items: [
                    for (final entry in {
                      'id': 'По номеру',
                      'name': 'По названию',
                      'ram_gb': 'По объёму ОЗУ',
                    }.entries)
                      DropdownMenuItem(
                        value: entry.key,
                        child: Text(entry.value),
                      ),
                  ],
                  onChanged: (v) => update({'sort': v}),
                ),
              ),
              IconButton(
                tooltip: 'Изменить направление',
                onPressed: () =>
                    update({'dir': query.descending ? 'asc' : 'desc'}),
                icon: Icon(query.descending ? Icons.south : Icons.north),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        Expanded(
          child: AsyncPanel(
            loading: loading,
            empty: data?.rows.isEmpty ?? false,
            error: error,
            onRetry: load,
            child: LayoutBuilder(
              builder: (context, c) {
                final count = c.maxWidth >= 1200
                    ? 3
                    : c.maxWidth >= 650
                    ? 2
                    : 1;
                return GridView.builder(
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: count,
                    mainAxisExtent: 385,
                    crossAxisSpacing: 16,
                    mainAxisSpacing: 16,
                  ),
                  itemCount: data?.rows.length ?? 0,
                  itemBuilder: (context, index) {
                    final s = data!.rows[index];
                    final busy = busyIntervals
                        .where((b) => b['station_id'] == s['id'])
                        .toList();
                    final available =
                        busy.isEmpty &&
                        s['state'] == 'ready' &&
                        start.isAfter(DateTime.now());
                    final gameIds = installed
                        .where(
                          (g) =>
                              g['station_id'] == s['id'] &&
                              g['enabled'] == true,
                        )
                        .map((g) => g['game_id'])
                        .toSet();
                    final gameNames = games
                        .where((g) => gameIds.contains(g['id']))
                        .map((g) => '${g['title']}')
                        .toList();
                    return Card(
                      clipBehavior: Clip.antiAlias,
                      child: Padding(
                        padding: const EdgeInsets.all(22),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(
                                  Icons.desktop_windows_outlined,
                                  size: 36,
                                  color: Color(0xff8bdbe3),
                                ),
                                const Spacer(),
                                Chip(
                                  label: Text(
                                    available
                                        ? 'Свободен'
                                        : busy.isNotEmpty
                                        ? 'Занят'
                                        : 'Недоступен',
                                  ),
                                  labelStyle: TextStyle(
                                    fontSize: 11,
                                    color: available
                                        ? const Color(0xffc5f36b)
                                        : const Color(0xffb4bac4),
                                  ),
                                  side: BorderSide.none,
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    '${s['name']}',
                                    style: Theme.of(context)
                                        .textTheme
                                        .headlineSmall
                                        ?.copyWith(fontWeight: FontWeight.w800),
                                  ),
                                ),
                                Text(
                                  '${s['zone_name']}',
                                  style: const TextStyle(
                                    color: Color(0xff99a3b3),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            Text(
                              '${s['cpu']}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 6),
                            Text(
                              '${s['gpu']} · ${s['ram_gb']} ГБ',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              gameNames.isEmpty
                                  ? 'Игры ещё не установлены'
                                  : gameNames.take(4).join(' · '),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Color(0xff99a3b3),
                                fontSize: 12,
                                height: 1.5,
                              ),
                            ),
                            const Spacer(),
                            if (busy.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: Text(
                                  'Занят: ${formatDate(busy.first['starts_at'])} — ${formatDate(busy.first['ends_at'])}',
                                  maxLines: 2,
                                  style: const TextStyle(fontSize: 11),
                                ),
                              ),
                            SizedBox(
                              width: double.infinity,
                              child: FilledButton.icon(
                                onPressed: available ? () => book(s) : null,
                                icon: const Icon(Icons.arrow_forward, size: 18),
                                label: const Text('Забронировать'),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Text('${data?.total ?? 0} компьютеров'),
            const Spacer(),
            Text('Стр. ${query.page}'),
            IconButton(
              tooltip: 'Назад',
              onPressed: query.page > 1
                  ? () => update({'page': '${query.page - 1}'})
                  : null,
              icon: const Icon(Icons.chevron_left),
            ),
            IconButton(
              tooltip: 'Далее',
              onPressed: query.page * query.size < (data?.total ?? 0)
                  ? () => update({'page': '${query.page + 1}'})
                  : null,
              icon: const Icon(Icons.chevron_right),
            ),
          ],
        ),
      ],
    ),
  );
}

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../models/list_query.dart';
import '../models/record.dart';
import '../repositories/club_repository.dart';
import '../state/auth_state.dart';
import '../state/list_state.dart';
import '../widgets/async_panel.dart';
import '../widgets/filter_panel.dart';
import '../widgets/record_form.dart';

class EntityScreen extends StatefulWidget {
  final EntitySpec spec;
  final Uri uri;
  final int? id;
  const EntityScreen({
    super.key,
    required this.spec,
    required this.uri,
    this.id,
  });
  @override
  State<EntityScreen> createState() => _EntityScreenState();
}

class _EntityScreenState extends State<EntityScreen> {
  late ListState state;
  late ListQuery query;
  final search = TextEditingController();
  final selected = <int>{};
  RecordData? detail;
  String? detailError;
  bool detailLoading = false, busy = false;
  @override
  void initState() {
    super.initState();
    state = ListState(context.read<ClubRepository>(), widget.spec);
    readQuery();
    load();
  }

  void readQuery() {
    query = ListQuery.fromUri(widget.uri, widget.spec);
    search.text = query.search;
  }

  @override
  void didUpdateWidget(covariant EntityScreen old) {
    super.didUpdateWidget(old);
    if (old.uri != widget.uri) {
      readQuery();
      selected.clear();
      load();
    }
  }

  @override
  void dispose() {
    state.dispose();
    search.dispose();
    super.dispose();
  }

  Future<void> load() async {
    if (widget.id != null) {
      setState(() {
        detailLoading = true;
        detailError = null;
      });
      try {
        final result = await context.read<ClubRepository>().get(
          widget.spec,
          widget.id!,
        );
        if (mounted) setState(() => detail = result);
      } catch (e) {
        if (mounted) setState(() => detailError = 'Запись недоступна. $e');
      }
      if (mounted) setState(() => detailLoading = false);
    } else {
      await state.load(query);
    }
  }

  void update(Map<String, String?> changes) {
    final p = <String, String>{...query.toUrl(), 'page': '1'};
    changes.forEach((k, v) {
      if (v == null || v.isEmpty) {
        p.remove(k);
      } else {
        p[k] = v;
      }
    });
    context.go(widget.uri.replace(queryParameters: p).toString());
  }

  bool get writable => widget.spec.canWrite(context.read<AuthState>().role);
  bool rowWritable(RecordData row) {
    if (!writable) return false;
    if (context.read<AuthState>().role == 'client' &&
        widget.spec.key == 'bookings') {
      return ['reserved', 'cancelled'].contains(row['status']) &&
          DateTime.parse(row['starts_at']).isAfter(DateTime.now());
    }
    return true;
  }

  String display(FieldSpec f, RecordData row) {
    final value = row[f.key];
    if (value == null) return '—';
    if (f.kind == FieldKind.toggle) return value == true ? 'Да' : 'Нет';
    if (f.kind == FieldKind.choice) return f.choices['$value'] ?? '$value';
    if (f.kind == FieldKind.reference) {
      final label = row[f.key.replaceFirst('_id', '_name')];
      return label == null ? '#$value' : '$label';
    }
    if (f.kind == FieldKind.date || f.kind == FieldKind.dateTime) {
      return formatDate(value);
    }
    return '$value';
  }

  Future<void> edit([RecordData? row]) async {
    if (await editRecord(context, widget.spec, row: row)) {
      selected.clear();
      load();
    }
  }

  Future<void> remove(List<int> ids, String action) async {
    final text = switch (action) {
      'hard' =>
        'Удалить навсегда ${ids.length} записей? Связанные данные могут запретить удаление.',
      'restore' => 'Восстановить ${ids.length} записей?',
      _ => 'Переместить в корзину ${ids.length} записей?',
    };
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Подтверждение'),
        content: Text(text),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Продолжить'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => busy = true);
    try {
      await context.read<ClubRepository>().remove(widget.spec, ids, action);
      selected.clear();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Операция выполнена')));
        if (widget.id != null && action == 'hard') {
          context.go(
            widget.uri.path.substring(0, widget.uri.path.lastIndexOf('/')),
          );
        } else {
          load();
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Widget rowActions(RecordData row) {
    if (!rowWritable(row) && !(writable && widget.spec.key == 'stations')) {
      return const SizedBox.shrink();
    }
    return PopupMenuButton<String>(
      tooltip: 'Действия',
      onSelected: (value) {
        if (value == 'edit') {
          edit(row);
        } else if (value == 'games') {
          selectStationGames(context, row);
        } else {
          remove([row['id']], value);
        }
      },
      itemBuilder: (_) => [
        if (rowWritable(row))
          const PopupMenuItem(value: 'edit', child: Text('Изменить')),
        if (writable && widget.spec.key == 'stations')
          const PopupMenuItem(value: 'games', child: Text('Выбрать игры')),
        if (rowWritable(row)) ...[
          if (row['deleted_at'] == null)
            const PopupMenuItem(value: 'soft', child: Text('В корзину'))
          else
            const PopupMenuItem(value: 'restore', child: Text('Восстановить')),
          const PopupMenuItem(value: 'hard', child: Text('Удалить навсегда')),
        ],
      ],
    );
  }

  void open(RecordData row) => context.go('${widget.uri.path}/${row['id']}');
  Widget filter(FieldSpec f) {
    final value = query.filters[f.key] ?? '';
    final choices = f.kind == FieldKind.toggle
        ? {'true': 'Да', 'false': 'Нет'}
        : f.choices;
    if (choices.isNotEmpty) {
      return SizedBox(
        width: 190,
        child: DropdownButtonFormField<String>(
          key: ValueKey('${f.key}-$value'),
          isExpanded: true,
          initialValue: value,
          decoration: InputDecoration(labelText: f.label),
          items: [
            const DropdownMenuItem(value: '', child: Text('Все')),
            for (final e in choices.entries)
              DropdownMenuItem(
                value: e.key,
                child: Text(e.value, overflow: TextOverflow.ellipsis),
              ),
          ],
          onChanged: (v) => update({f.key: v}),
        ),
      );
    }
    if (f.reference != null) {
      return _ReferenceFilter(
        field: f,
        value: value,
        onChanged: (v) => update({f.key: v}),
      );
    }
    return SizedBox(
      width: 190,
      child: TextFormField(
        key: ValueKey('${f.key}-$value'),
        initialValue: value,
        autovalidateMode: AutovalidateMode.onUserInteraction,
        validator: (v) => (v ?? '').trim().isEmpty ? null : f.validate(v),
        decoration: InputDecoration(
          labelText: f.label,
          hintText: f.kind == FieldKind.dateTime ? 'ГГГГ-ММ-ДД' : null,
          suffixIcon: const Icon(Icons.filter_alt_outlined, size: 18),
        ),
        onFieldSubmitted: (v) {
          if (v.trim().isEmpty || f.validate(v) == null) {
            update({f.key: v.trim()});
          }
        },
      ),
    );
  }

  Widget get detailContent => AsyncPanel(
    loading: detailLoading,
    empty: false,
    error: detailError,
    onRetry: load,
    child: detail == null
        ? const SizedBox.shrink()
        : SingleChildScrollView(
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${widget.spec.singular} #${detail!['id']}',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 24),
                    for (final f in widget.spec.fields)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: Text('${f.label}: ${display(f, detail!)}'),
                      ),
                    for (final key in [
                      'quoted_total',
                      'billable_minutes',
                      'actual_minutes',
                      'charge',
                    ])
                      if (detail!.containsKey(key))
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Text(
                            '${{'quoted_total': 'Стоимость, ₽', 'billable_minutes': 'Оплачиваемые минуты', 'actual_minutes': 'Фактические минуты', 'charge': 'Сумма сеанса, ₽'}[key]}: ${detail![key]}',
                          ),
                        ),
                    Text('Создано: ${formatDate(detail!['created_at'])}'),
                    const SizedBox(height: 12),
                    Text(
                      detail!['deleted_at'] == null
                          ? 'Активная запись'
                          : 'В корзине',
                    ),
                    const SizedBox(height: 24),
                    if (rowWritable(detail!))
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          FilledButton.icon(
                            onPressed: busy ? null : () => edit(detail),
                            icon: const Icon(Icons.edit_outlined),
                            label: const Text('Изменить'),
                          ),
                          OutlinedButton(
                            onPressed: busy
                                ? null
                                : () => remove(
                                    [detail!['id']],
                                    detail!['deleted_at'] == null
                                        ? 'soft'
                                        : 'restore',
                                  ),
                            child: Text(
                              detail!['deleted_at'] == null
                                  ? 'В корзину'
                                  : 'Восстановить',
                            ),
                          ),
                          TextButton(
                            onPressed: busy
                                ? null
                                : () => remove([detail!['id']], 'hard'),
                            child: const Text('Удалить навсегда'),
                          ),
                        ],
                      ),
                    if (writable && widget.spec.key == 'stations')
                      OutlinedButton(
                        onPressed: () => selectStationGames(context, detail!),
                        child: const Text('Выбрать установленные игры'),
                      ),
                  ],
                ),
              ),
            ),
          ),
  );

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: state,
    builder: (context, _) => Padding(
      padding: EdgeInsets.all(MediaQuery.sizeOf(context).width < 600 ? 16 : 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 16,
            runSpacing: 12,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.id == null ? widget.spec.title : 'Карточка записи',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    widget.id == null
                        ? '${state.data?.total ?? 0} записей · ${writable ? 'управление данными' : 'просмотр'}'
                        : 'Прямая ссылка на запись',
                    style: const TextStyle(color: Color(0xff99a3b3)),
                  ),
                ],
              ),
              if (widget.id == null && writable)
                FilledButton.icon(
                  onPressed: () => edit(),
                  icon: const Icon(Icons.add),
                  label: const Text('Добавить'),
                ),
              if (widget.id != null)
                OutlinedButton.icon(
                  onPressed: () => context.go(
                    widget.uri.path.substring(
                      0,
                      widget.uri.path.lastIndexOf('/'),
                    ),
                  ),
                  icon: const Icon(Icons.arrow_back),
                  label: const Text('К списку'),
                ),
            ],
          ),
          const SizedBox(height: 24),
          if (widget.id != null)
            Expanded(child: detailContent)
          else ...[
            FilterPanel(
              child: Wrap(
                spacing: 12,
                runSpacing: 12,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SizedBox(
                    width: 280,
                    child: TextField(
                      controller: search,
                      decoration: InputDecoration(
                        labelText: 'Поиск',
                        prefixIcon: const Icon(Icons.search),
                        suffixIcon: IconButton(
                          tooltip: 'Найти',
                          onPressed: () => update({'q': search.text.trim()}),
                          icon: const Icon(Icons.arrow_forward),
                        ),
                      ),
                      onSubmitted: (v) => update({'q': v.trim()}),
                    ),
                  ),
                  for (final key in widget.spec.filterFields)
                    filter(widget.spec.field(key)),
                  SizedBox(
                    width: 190,
                    child: DropdownButtonFormField<String>(
                      key: ValueKey(query.sort),
                      initialValue: query.sort,
                      decoration: const InputDecoration(
                        labelText: 'Сортировка',
                      ),
                      isExpanded: true,
                      items: [
                        const DropdownMenuItem(
                          value: 'id',
                          child: Text('По номеру'),
                        ),
                        const DropdownMenuItem(
                          value: 'created_at',
                          child: Text('По дате создания'),
                        ),
                        for (final f in widget.spec.fields)
                          DropdownMenuItem(
                            value: f.key,
                            child: Text(
                              f.label,
                              overflow: TextOverflow.ellipsis,
                            ),
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
                  FilterChip(
                    label: const Text('Корзина'),
                    selected: query.trash == 'deleted',
                    onSelected: (v) => update({'trash': v ? 'deleted' : null}),
                  ),
                  TextButton(
                    onPressed: () => context.go(widget.uri.path),
                    child: const Text('Сбросить'),
                  ),
                ],
              ),
            ),
            if (selected.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text('Выбрано: ${selected.length}'),
                    OutlinedButton(
                      onPressed: busy
                          ? null
                          : () => remove(
                              selected.toList(),
                              query.trash == 'deleted' ? 'restore' : 'soft',
                            ),
                      child: Text(
                        query.trash == 'deleted' ? 'Восстановить' : 'В корзину',
                      ),
                    ),
                    TextButton(
                      onPressed: busy
                          ? null
                          : () => remove(selected.toList(), 'hard'),
                      child: const Text('Удалить навсегда'),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 20),
            Expanded(
              child: AsyncPanel(
                loading: state.loading,
                empty: state.data?.rows.isEmpty ?? false,
                error: state.error,
                onRetry: load,
                child: LayoutBuilder(
                  builder: (context, c) {
                    final rows = state.data?.rows ?? [];
                    if (c.maxWidth < 900) {
                      return ListView.separated(
                        itemCount: rows.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (context, i) {
                          final row = rows[i];
                          return Card(
                            child: InkWell(
                              onTap: () => open(row),
                              borderRadius: BorderRadius.circular(16),
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        if (rowWritable(row))
                                          Checkbox(
                                            value: selected.contains(row['id']),
                                            onChanged: busy
                                                ? null
                                                : (v) => setState(() {
                                                    v == true
                                                        ? selected.add(
                                                            row['id'],
                                                          )
                                                        : selected.remove(
                                                            row['id'],
                                                          );
                                                  }),
                                          ),
                                        Expanded(
                                          child: Text(
                                            '#${row['id']} · ${widget.spec.label(row)}',
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                        if (writable) rowActions(row),
                                      ],
                                    ),
                                    for (final f in widget.spec.fields.take(5))
                                      Padding(
                                        padding: const EdgeInsets.only(top: 6),
                                        child: Text(
                                          '${f.label}: ${display(f, row)}',
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    if (row['quoted_total'] != null)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 10),
                                        child: Text(
                                          '${row['quoted_total']} ₽',
                                          style: const TextStyle(
                                            color: Color(0xffc5f36b),
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      );
                    }
                    final fields = widget.spec.fields.take(5).toList();
                    return SingleChildScrollView(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: DataTable(
                          showCheckboxColumn: writable,
                          columns: [
                            const DataColumn(label: Text('№')),
                            for (final f in fields)
                              DataColumn(label: Text(f.label)),
                            if (widget.spec.key == 'bookings')
                              const DataColumn(label: Text('Стоимость')),
                            if (writable) const DataColumn(label: Text('')),
                          ],
                          rows: [
                            for (final row in rows)
                              DataRow(
                                selected: selected.contains(row['id']),
                                onSelectChanged: rowWritable(row)
                                    ? (v) => setState(() {
                                        v == true
                                            ? selected.add(row['id'])
                                            : selected.remove(row['id']);
                                      })
                                    : null,
                                cells: [
                                  DataCell(
                                    Text('#${row['id']}'),
                                    onTap: () => open(row),
                                  ),
                                  for (final f in fields)
                                    DataCell(
                                      ConstrainedBox(
                                        constraints: const BoxConstraints(
                                          maxWidth: 180,
                                        ),
                                        child: Text(
                                          display(f, row),
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      onTap: () => open(row),
                                    ),
                                  if (widget.spec.key == 'bookings')
                                    DataCell(
                                      Text('${row['quoted_total']} ₽'),
                                      onTap: () => open(row),
                                    ),
                                  if (writable) DataCell(rowActions(row)),
                                ],
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Text(
                  'Стр. ${query.page} / ${((state.data?.total ?? 0) / query.size).ceil().clamp(1, 100000)}',
                ),
                const Spacer(),
                DropdownButton<int>(
                  value: query.size,
                  items: [
                    for (final n in [10, 20, 50])
                      DropdownMenuItem(value: n, child: Text('$n')),
                  ],
                  onChanged: (v) => update({'size': '$v'}),
                ),
                IconButton(
                  tooltip: 'Предыдущая страница',
                  onPressed: query.page > 1
                      ? () => update({'page': '${query.page - 1}'})
                      : null,
                  icon: const Icon(Icons.chevron_left),
                ),
                IconButton(
                  tooltip: 'Следующая страница',
                  onPressed: query.page * query.size < (state.data?.total ?? 0)
                      ? () => update({'page': '${query.page + 1}'})
                      : null,
                  icon: const Icon(Icons.chevron_right),
                ),
              ],
            ),
          ],
        ],
      ),
    ),
  );
}

class _ReferenceFilter extends StatefulWidget {
  final FieldSpec field;
  final String value;
  final ValueChanged<String?> onChanged;
  const _ReferenceFilter({
    required this.field,
    required this.value,
    required this.onChanged,
  });
  @override
  State<_ReferenceFilter> createState() => _ReferenceFilterState();
}

class _ReferenceFilterState extends State<_ReferenceFilter> {
  late Future<List<RecordData>> future;
  @override
  void initState() {
    super.initState();
    future = context.read<ClubRepository>().references(widget.field.reference!);
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 190,
    child: FutureBuilder<List<RecordData>>(
      future: future,
      builder: (context, s) {
        final rows = s.data ?? [];
        final values = rows.map((r) => '${r['id']}').toSet();
        return DropdownButtonFormField<String>(
          key: ValueKey(widget.value),
          initialValue: widget.value,
          isExpanded: true,
          decoration: InputDecoration(
            labelText: widget.field.label,
            helperText: s.hasError ? 'Не удалось загрузить' : null,
          ),
          items: [
            const DropdownMenuItem(value: '', child: Text('Все')),
            if (widget.value.isNotEmpty && !values.contains(widget.value))
              DropdownMenuItem(
                value: widget.value,
                child: Text('#${widget.value} · недоступна'),
              ),
            for (final r in rows)
              DropdownMenuItem(
                value: '${r['id']}',
                child: Text(
                  '#${r['id']} · ${r['name'] ?? r['full_name'] ?? r['station_name'] ?? r['title'] ?? ''}',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
          onChanged: widget.onChanged,
        );
      },
    ),
  );
}

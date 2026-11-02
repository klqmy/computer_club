import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/api_error.dart';
import '../models/catalog.dart';
import '../models/record.dart';
import '../repositories/club_repository.dart';
import '../state/auth_state.dart';
import 'async_panel.dart';

Future<bool> editRecord(
  BuildContext context,
  EntitySpec spec, {
  RecordData? row,
  RecordData initial = const {},
}) async =>
    await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => RecordForm(spec: spec, row: row, initial: initial),
    ) ??
    false;

class RecordForm extends StatefulWidget {
  final EntitySpec spec;
  final RecordData? row;
  final RecordData initial;
  const RecordForm({
    super.key,
    required this.spec,
    this.row,
    this.initial = const {},
  });
  @override
  State<RecordForm> createState() => _RecordFormState();
}

class _RecordFormState extends State<RecordForm> {
  final form = GlobalKey<FormState>();
  final values = <String, TextEditingController>{};
  final references = <String, List<RecordData>>{};
  Map<String, String> errors = {};
  bool loading = true, saving = false;
  String? error;
  RecordData? quote;
  @override
  void initState() {
    super.initState();
    for (final f in widget.spec.fields) {
      var value = widget.row?[f.key] ?? widget.initial[f.key];
      value ??= switch (f.kind) {
        FieldKind.toggle => true,
        FieldKind.choice => f.choices.keys.first,
        FieldKind.date => DateTime.now().toIso8601String().split('T').first,
        _ => '',
      };
      if (f.kind == FieldKind.dateTime && '$value'.isNotEmpty) {
        value = DateTime.parse(
          '$value',
        ).toLocal().toIso8601String().substring(0, 16);
      }
      values[f.key] = TextEditingController(text: '$value');
    }
    load();
  }

  @override
  void dispose() {
    for (final c in values.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final repo = context.read<ClubRepository>();
      final refs = widget.spec.fields
          .where((f) => f.reference != null)
          .map((f) => f.reference!)
          .toSet();
      final results = await Future.wait(
        refs.map((key) async => MapEntry(key, await repo.references(key))),
      );
      references.addEntries(results);
      if (widget.spec.key == 'bookings' &&
          values['customer_id']!.text.isEmpty &&
          references['customers']?.length == 1) {
        values['customer_id']!.text = '${references['customers']!.first['id']}';
      }
    } catch (e) {
      error = '$e';
    }
    if (mounted) setState(() => loading = false);
  }

  RecordData payload() => {
    for (final f in widget.spec.fields)
      if (f.editable) f.key: f.parse(values[f.key]!.text),
  };
  String? validate(FieldSpec f, String? v) {
    if (errors.containsKey(f.key)) return errors[f.key];
    final result = f.validate(v);
    if (result != null) return result;
    if (f.key == 'card_number' && !RegExp(r'^PC-[0-9]{6}$').hasMatch(v ?? '')) {
      return 'Формат: PC-000001';
    }
    if (f.key == 'valid_until' && v!.compareTo(values['issued_at']!.text) < 0) {
      return 'Дата раньше выдачи карты';
    }
    if ((f.key == 'ends_at' || f.key == 'finished_at') &&
        (v ?? '').isNotEmpty) {
      final start = DateTime.tryParse(
        values[f.key == 'ends_at' ? 'starts_at' : 'started_at']!.text,
      );
      final end = DateTime.tryParse(v!);
      if (start != null && end != null && !end.isAfter(start)) {
        return 'Окончание должно быть позже начала';
      }
    }
    return null;
  }

  Future<void> save({bool calculate = false}) async {
    errors = {};
    if (!form.currentState!.validate()) return;
    setState(() {
      saving = true;
      error = null;
      quote = null;
    });
    try {
      final data = payload();
      final repo = context.read<ClubRepository>();
      if (calculate) {
        final result = await repo.command('quote_booking', {
          for (final key in [
            'customer_id',
            'station_id',
            'tariff_id',
            'starts_at',
            'ends_at',
          ])
            'p_$key': data[key],
        });
        if (mounted) setState(() => quote = RecordData.from(result));
      } else {
        await repo.save(widget.spec, data, id: widget.row?['id']);
        if (mounted) Navigator.pop(context, true);
      }
    } on ApiError catch (e) {
      if (mounted) {
        setState(() {
          error = e.message;
          errors = e.fields;
        });
        form.currentState!.validate();
      }
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Future<void> pickDate(FieldSpec f) async {
    final old = DateTime.tryParse(values[f.key]!.text) ?? DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: old,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (date == null || !mounted) return;
    var result = date;
    if (f.kind == FieldKind.dateTime) {
      final time = await showTimePicker(
        context: context,
        initialTime: TimeOfDay.fromDateTime(old),
      );
      if (time == null || !mounted) return;
      result = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      );
    }
    setState(() {
      values[f.key]!.text = result.toIso8601String().substring(
        0,
        f.kind == FieldKind.date ? 10 : 16,
      );
      errors.remove(f.key);
      quote = null;
    });
  }

  Widget input(FieldSpec f) {
    final c = values[f.key]!;
    final client = context.read<AuthState>().role == 'client';
    void change() {
      setState(() {
        errors.remove(f.key);
        quote = null;
        if (f.key == 'station_id' && widget.spec.key == 'bookings') {
          values['tariff_id']!.text = '';
        }
      });
    }

    if (f.kind == FieldKind.toggle) {
      return SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(f.label),
        value: c.text == 'true',
        onChanged: saving
            ? null
            : (v) {
                c.text = '$v';
                change();
              },
      );
    }
    if (f.kind == FieldKind.choice || f.kind == FieldKind.reference) {
      final options = <String, String>{...f.choices};
      if (f.reference != null) {
        var rows = references[f.reference!] ?? [];
        if (widget.spec.key == 'bookings' &&
            f.key == 'tariff_id' &&
            values['station_id']!.text.isNotEmpty) {
          final station = (references['stations'] ?? [])
              .where((r) => '${r['id']}' == values['station_id']!.text)
              .firstOrNull;
          if (station != null) {
            rows = rows
                .where(
                  (r) =>
                      r['zone_id'] == station['zone_id'] && r['active'] == true,
                )
                .toList();
          }
        }
        for (final row in rows) {
          final spec = entities[f.reference!]!;
          options['${row['id']}'] = f.reference == 'bookings'
              ? '#${row['id']} · ${row['station_name']} · ${formatDate(row['starts_at'])}'
              : spec.label(row);
        }
      }
      if (client && f.key == 'status') {
        options.removeWhere(
          (key, _) => !['reserved', 'cancelled'].contains(key),
        );
      }
      if (c.text.isNotEmpty && !options.containsKey(c.text)) {
        options[c.text] = 'Текущее значение: ${c.text}';
      }
      return DropdownButtonFormField<String>(
        initialValue: c.text.isEmpty ? null : c.text,
        isExpanded: true,
        decoration: InputDecoration(labelText: f.label),
        menuMaxHeight: 300,
        items: options.entries
            .map(
              (e) => DropdownMenuItem(
                value: e.key,
                child: Text(e.value, overflow: TextOverflow.ellipsis),
              ),
            )
            .toList(),
        onChanged: saving
            ? null
            : (v) {
                c.text = v ?? '';
                change();
              },
        validator: (v) => validate(f, v),
      );
    }
    final date = f.kind == FieldKind.date || f.kind == FieldKind.dateTime;
    return TextFormField(
      controller: c,
      enabled: !saving,
      maxLines: f.key == 'notes' || f.key == 'description' || f.key == 'comment'
          ? 3
          : 1,
      keyboardType: switch (f.kind) {
        FieldKind.integer || FieldKind.decimal => TextInputType.number,
        FieldKind.email => TextInputType.emailAddress,
        FieldKind.phone => TextInputType.phone,
        _ => TextInputType.text,
      },
      decoration: InputDecoration(
        labelText: '${f.label}${f.required ? ' *' : ''}',
        hintText: date
            ? '${f.kind == FieldKind.date ? '2026-11-02' : '2026-11-02T18:30'}${f.kind == FieldKind.dateTime ? ' (местное время)' : ''}'
            : null,
        suffixIcon: date
            ? IconButton(
                tooltip: 'Выбрать дату',
                onPressed: saving ? null : () => pickDate(f),
                icon: const Icon(Icons.calendar_month_outlined),
              )
            : null,
      ),
      validator: (v) => validate(f, v),
      onChanged: (_) => change(),
    );
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      '${widget.row == null ? 'Добавить' : 'Изменить'}: ${widget.spec.singular.toLowerCase()}',
    ),
    content: SizedBox(
      width: 540,
      child: AsyncPanel(
        loading: loading,
        empty: false,
        error: loading
            ? null
            : error != null &&
                  references.isEmpty &&
                  widget.spec.fields.any((f) => f.reference != null)
            ? error
            : null,
        onRetry: load,
        child: SingleChildScrollView(
          child: Form(
            key: form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final f in widget.spec.fields)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 18),
                    child: input(f),
                  ),
                if (widget.spec.key == 'bookings')
                  const Text(
                    'Стоимость рассчитывает сервер: минимум и шаг тарифа, клубная скидка и ночная скидка 22:00–08:00 по Москве.',
                    style: TextStyle(fontSize: 12),
                  ),
                if (quote != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: Text(
                      '${quote!['quoted_total']} ₽ · ${quote!['billable_minutes']} мин.\nКарта: ${quote!['discount_percent']}%, ночь: ${quote!['night_discount_percent']}%',
                      style: const TextStyle(
                        color: Color(0xffc5f36b),
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: Text(
                      error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: saving ? null : () => Navigator.pop(context),
        child: const Text('Отмена'),
      ),
      if (widget.spec.key == 'bookings')
        OutlinedButton(
          onPressed: loading || saving ? null : () => save(calculate: true),
          child: const Text('Рассчитать'),
        ),
      FilledButton(
        onPressed: loading || saving ? null : save,
        child: Text(saving ? 'Подождите…' : 'Сохранить'),
      ),
    ],
  );
}

String formatDate(dynamic value) {
  if (value == null) return '—';
  final d = DateTime.tryParse('$value')?.toLocal();
  if (d == null) return '$value';
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(d.day)}.${two(d.month)}.${d.year}${'$value'.contains('T') ? ' ${two(d.hour)}:${two(d.minute)}' : ''}';
}

Future<void> selectStationGames(
  BuildContext context,
  RecordData station,
) async {
  final repo = context.read<ClubRepository>();
  try {
    final games = await repo.references('games');
    final installed = (await repo.references('station_games'))
        .where((r) => r['station_id'] == station['id'])
        .map((r) => r['game_id'] as int)
        .toSet();
    if (!context.mounted) return;
    bool busy = false;
    String? error;
    await showDialog<void>(
      context: context,
      builder: (dialog) => StatefulBuilder(
        builder: (dialog, setState) => AlertDialog(
          title: Text('Игры · ${station['name']}'),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final game in games)
                    CheckboxListTile(
                      title: Text('${game['title']}'),
                      value: installed.contains(game['id']),
                      onChanged: busy
                          ? null
                          : (v) => setState(() {
                              v == true
                                  ? installed.add(game['id'])
                                  : installed.remove(game['id']);
                            }),
                    ),
                  if (error != null)
                    Text(
                      error!,
                      style: TextStyle(
                        color: Theme.of(dialog).colorScheme.error,
                      ),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: busy ? null : () => Navigator.pop(dialog),
              child: const Text('Отмена'),
            ),
            FilledButton(
              onPressed: busy
                  ? null
                  : () async {
                      setState(() => busy = true);
                      try {
                        await repo.command('set_station_games', {
                          'p_station_id': station['id'],
                          'p_game_ids': installed.toList(),
                        });
                        if (dialog.mounted) Navigator.pop(dialog);
                      } catch (e) {
                        setState(() {
                          error = '$e';
                          busy = false;
                        });
                      }
                    },
              child: const Text('Сохранить'),
            ),
          ],
        ),
      ),
    );
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }
}

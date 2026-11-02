typedef RecordData = Map<String, dynamic>;

enum FieldKind {
  text,
  email,
  phone,
  integer,
  decimal,
  choice,
  reference,
  date,
  dateTime,
  toggle,
}

class FieldSpec {
  final String key, label;
  final FieldKind kind;
  final bool required, editable;
  final int? maxLength;
  final num? min, max;
  final Map<String, String> choices;
  final String? reference;
  const FieldSpec(
    this.key,
    this.label, {
    this.kind = FieldKind.text,
    this.required = true,
    this.editable = true,
    this.maxLength,
    this.min,
    this.max,
    this.choices = const {},
    this.reference,
  });

  String? validate(String? input) {
    final v = input?.trim() ?? '';
    if (v.isEmpty) return required ? 'Заполните поле' : null;
    if (maxLength != null && v.length > maxLength!) {
      return 'Не более $maxLength символов';
    }
    if (kind == FieldKind.email &&
        !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(v)) {
      return 'Введите корректный email';
    }
    if (kind == FieldKind.phone &&
        !RegExp(r'^\+?[0-9 ()-]{10,20}$').hasMatch(v)) {
      return 'Введите телефон: от 10 до 20 символов';
    }
    if (kind == FieldKind.integer ||
        kind == FieldKind.decimal ||
        kind == FieldKind.reference) {
      final n = num.tryParse(v.replaceAll(',', '.'));
      if (n == null ||
          !n.isFinite ||
          (kind != FieldKind.decimal && n != n.roundToDouble())) {
        return 'Введите ${kind == FieldKind.decimal ? 'число' : 'целое число'}';
      }
      if (min != null && n < min!) return 'Минимум: $min';
      if (max != null && n > max!) return 'Максимум: $max';
      if (kind == FieldKind.reference && n <= 0) {
        return 'Выберите связанную запись';
      }
    }
    if (kind == FieldKind.choice && !choices.containsKey(v)) {
      return 'Выберите значение из списка';
    }
    if (kind == FieldKind.toggle && v != 'true' && v != 'false') {
      return 'Выберите Да или Нет';
    }
    if (kind == FieldKind.date || kind == FieldKind.dateTime) {
      final source = v.split('T').first;
      final d = DateTime.tryParse(source);
      if (d == null) return 'Укажите корректную дату';
      if (source !=
          '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}') {
        return 'Такой даты нет';
      }
      if (kind == FieldKind.date && v != source) return 'Укажите только дату';
      if (kind == FieldKind.dateTime) {
        final time = RegExp(
          r'T(\d{2}):(\d{2})(?::(\d{2})(?:\.\d+)?)?(?:Z|[+-]\d{2}:\d{2})?$',
        ).firstMatch(v);
        if (time == null ||
            int.parse(time[1]!) > 23 ||
            int.parse(time[2]!) > 59 ||
            int.parse(time[3] ?? '0') > 59 ||
            DateTime.tryParse(v) == null) {
          return 'Время в формате ГГГГ-ММ-ДДTЧЧ:ММ';
        }
      }
    }
    return null;
  }

  dynamic parse(String value) {
    final v = value.trim();
    if (v.isEmpty && !required) return null;
    return switch (kind) {
      FieldKind.integer ||
      FieldKind.reference => num.parse(v.replaceAll(',', '.')).toInt(),
      FieldKind.decimal => num.parse(v.replaceAll(',', '.')),
      FieldKind.toggle => v == 'true',
      FieldKind.dateTime => DateTime.parse(v).toUtc().toIso8601String(),
      _ => v,
    };
  }
}

class EntitySpec {
  final String key, title, singular, titleField;
  final List<FieldSpec> fields;
  final List<String> filterFields, searchFields;
  final Set<String> writers;
  const EntitySpec(
    this.key,
    this.title,
    this.singular,
    this.titleField,
    this.fields, {
    this.filterFields = const [],
    this.searchFields = const [],
    this.writers = const {'admin'},
  });
  FieldSpec field(String key) => fields.firstWhere((f) => f.key == key);
  bool canWrite(String role) => writers.contains(role);
  String label(RecordData row) => '${row[titleField] ?? '#${row['id']}'}';
}

class PageResult {
  final List<RecordData> rows;
  final int total;
  const PageResult(this.rows, this.total);
}

import 'record.dart';

class ListQuery {
  final int page, size;
  final String search, sort, trash;
  final bool descending;
  final Map<String, String> filters;
  const ListQuery({
    this.page = 1,
    this.size = 10,
    this.search = '',
    this.sort = 'id',
    this.trash = 'active',
    this.descending = false,
    this.filters = const {},
  });

  factory ListQuery.fromUri(Uri uri, EntitySpec spec) {
    final p = uri.queryParameters;
    final allowed = {'id', 'created_at', ...spec.fields.map((f) => f.key)};
    return ListQuery(
      page: (int.tryParse(p['page'] ?? '') ?? 1).clamp(1, 100000),
      size: const [10, 20, 50].contains(int.tryParse(p['size'] ?? ''))
          ? int.parse(p['size']!)
          : 10,
      search: (p['q'] ?? '').trim(),
      sort: allowed.contains(p['sort']) ? p['sort']! : 'id',
      descending: p['dir'] == 'desc',
      trash: p['trash'] == 'deleted' ? 'deleted' : 'active',
      filters: {
        for (final key in spec.filterFields)
          if ((p[key] ?? '').isNotEmpty) key: p[key]!,
      },
    );
  }

  Map<String, String> toUrl() => {
    'page': '$page',
    'size': '$size',
    'sort': sort,
    'dir': descending ? 'desc' : 'asc',
    if (search.isNotEmpty) 'q': search,
    if (trash == 'deleted') 'trash': trash,
    ...filters,
  };

  Map<String, dynamic> toApi(EntitySpec spec) {
    // Wildcards are intentional, PostgREST control punctuation is stripped.
    final term = search.replaceAll(
      RegExp(r'[^\p{L}\p{N}\s@.+\-]', unicode: true),
      '',
    );
    return {
      'select': '*',
      'limit': size,
      'offset': (page - 1) * size,
      'order': '$sort.${descending ? 'desc' : 'asc'},id.asc',
      'deleted_at': trash == 'deleted' ? 'not.is.null' : 'is.null',
      if (term.isNotEmpty && spec.searchFields.isNotEmpty)
        'or': '(${spec.searchFields.map((f) => '$f.ilike.*$term*').join(',')})',
      for (final entry in filters.entries) entry.key: 'eq.${entry.value}',
    };
  }
}

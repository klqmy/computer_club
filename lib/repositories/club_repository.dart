import 'package:dio/dio.dart';
import '../core/api_client.dart';
import '../models/catalog.dart';
import '../models/list_query.dart';
import '../models/record.dart';

abstract class ClubRepository {
  Future<PageResult> list(
    EntitySpec spec,
    ListQuery query, {
    CancelToken? cancelToken,
  });
  Future<RecordData> get(EntitySpec spec, int id);
  Future<RecordData> save(EntitySpec spec, RecordData values, {int? id});
  Future<void> remove(EntitySpec spec, List<int> ids, String action);
  Future<List<RecordData>> references(String entity);
  Future<dynamic> command(String name, RecordData values);
}

class SupabaseClubRepository implements ClubRepository {
  final ApiClient api;
  SupabaseClubRepository(this.api);
  String source(String key) =>
      const {
        'stations',
        'tariffs',
        'station_games',
        'memberships',
        'bookings',
        'sessions',
        'payments',
      }.contains(key)
      ? '${key}_list'
      : key;
  @override
  Future<PageResult> list(
    EntitySpec spec,
    ListQuery query, {
    CancelToken? cancelToken,
  }) async {
    final r = await api.request(
      source(spec.key),
      query: query.toApi(spec),
      cancelToken: cancelToken,
    );
    final count =
        int.tryParse(r.headers.value('content-range')?.split('/').last ?? '') ??
        (r.data as List).length;
    return PageResult(
      (r.data as List).map((x) => RecordData.from(x)).toList(),
      count,
    );
  }

  @override
  Future<RecordData> get(EntitySpec spec, int id) async {
    final result = await api.request(
      source(spec.key),
      query: {'id': 'eq.$id', 'limit': 1},
    );
    return RecordData.from((result.data as List).single);
  }

  @override
  Future<RecordData> save(EntitySpec spec, RecordData values, {int? id}) async {
    if (spec.key == 'bookings') {
      return RecordData.from(
        await command('save_booking', {'p_id': id, 'p_data': values}),
      );
    }
    final r = await api.request(
      spec.key,
      method: id == null ? 'POST' : 'PATCH',
      query: id == null ? null : {'id': 'eq.$id'},
      data: values,
    );
    return RecordData.from((r.data as List).single);
  }

  @override
  Future<void> remove(EntitySpec spec, List<int> ids, String action) async {
    await command('bulk_records', {
      'p_table': spec.key,
      'p_ids': ids,
      'p_action': action,
    });
  }

  @override
  Future<List<RecordData>> references(String entity) async {
    final result = await list(entities[entity]!, const ListQuery(size: 1000));
    return result.rows;
  }

  @override
  Future<dynamic> command(String name, RecordData values) =>
      api.rpc(name, values);
}

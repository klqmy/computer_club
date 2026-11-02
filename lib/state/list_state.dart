import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../models/list_query.dart';
import '../models/record.dart';
import '../repositories/club_repository.dart';

class ListState extends ChangeNotifier {
  final ClubRepository repository;
  final EntitySpec spec;
  PageResult? data;
  bool loading = true;
  String? error;
  CancelToken? _cancel;
  bool _disposed = false;
  ListState(this.repository, this.spec);
  Future<void> load(ListQuery query) async {
    _cancel?.cancel();
    final cancel = CancelToken();
    _cancel = cancel;
    loading = true;
    error = null;
    notifyListeners();
    try {
      final result = await repository.list(spec, query, cancelToken: cancel);
      if (!cancel.isCancelled) data = result;
    } catch (e) {
      if (!cancel.isCancelled) error = '$e';
    }
    if (!cancel.isCancelled && !_disposed) {
      loading = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _cancel?.cancel();
    super.dispose();
  }
}

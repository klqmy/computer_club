import '../models/catalog.dart';

bool routeAllowed(String role, String path) {
  if (path == '/forbidden') return true;
  if (path.startsWith('/admin/')) return role == 'admin';
  if (path == '/shift') return role == 'operator';
  if (path == '/catalog' || path.startsWith('/my/')) return role == 'client';
  if (path.startsWith('/manage/')) {
    final key = path.split('/')[2];
    if (!entities.containsKey(key) || role == 'client') return false;
    return role == 'admin' || role == 'operator';
  }
  return false;
}

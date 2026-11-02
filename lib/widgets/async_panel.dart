import 'package:flutter/material.dart';

class AsyncPanel extends StatelessWidget {
  final bool loading, empty;
  final String? error;
  final VoidCallback onRetry;
  final Widget child;
  const AsyncPanel({
    super.key,
    required this.loading,
    required this.empty,
    this.error,
    required this.onRetry,
    required this.child,
  });
  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(48),
          child: CircularProgressIndicator(),
        ),
      );
    }
    if (error != null || empty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                error == null ? Icons.search_off : Icons.cloud_off,
                size: 48,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 16),
              Text(error ?? 'Ничего не найдено', textAlign: TextAlign.center),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: Text(error == null ? 'Обновить' : 'Повторить'),
              ),
            ],
          ),
        ),
      );
    }
    return child;
  }
}

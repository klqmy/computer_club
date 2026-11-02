import 'package:flutter/material.dart';

class FilterPanel extends StatelessWidget {
  final Widget child;
  const FilterPanel({super.key, required this.child});
  @override
  Widget build(BuildContext context) {
    if (MediaQuery.sizeOf(context).width >= 800) return child;
    return Card(
      child: ExpansionTile(
        title: const Text('Поиск, фильтры и сортировка'),
        leading: const Icon(Icons.tune),
        children: [
          ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * .30,
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: child,
            ),
          ),
        ],
      ),
    );
  }
}

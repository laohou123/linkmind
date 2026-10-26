import 'package:flutter/material.dart';

import '../app_state.dart';
import '../data/repository.dart';
import 'theme.dart';

/// 搜索实体并定位到图谱上。输入即查，不用点按钮。
class EntitySearchDelegate extends SearchDelegate<String?> {
  final AppState state;

  EntitySearchDelegate(this.state)
      : super(
          searchFieldLabel: '搜索设备名称或编号',
          searchFieldStyle: const TextStyle(fontSize: 15, color: AppColors.text),
        );

  @override
  ThemeData appBarTheme(BuildContext context) {
    return Theme.of(context).copyWith(
      scaffoldBackgroundColor: AppColors.bg,
      appBarTheme: const AppBarTheme(backgroundColor: AppColors.bg, elevation: 0),
    );
  }

  @override
  List<Widget> buildActions(BuildContext context) => [
        if (query.isNotEmpty)
          IconButton(
            icon: const Icon(Icons.clear, size: 18, color: AppColors.textSub),
            onPressed: () => query = '',
          ),
      ];

  @override
  Widget buildLeading(BuildContext context) => IconButton(
        icon: const Icon(Icons.arrow_back, size: 20, color: AppColors.textSub),
        onPressed: () => close(context, null),
      );

  @override
  Widget buildResults(BuildContext context) => _buildList(context);

  @override
  Widget buildSuggestions(BuildContext context) => _buildList(context);

  Widget _buildList(BuildContext context) {
    if (query.trim().isEmpty) {
      return const Center(
        child: Text('输入设备名或编号，例如「33#湿矿」',
            style: TextStyle(fontSize: 13, color: AppColors.textFaint)),
      );
    }
    return FutureBuilder<List<Map<String, Object?>>>(
      future: GraphRepository.instance.searchEntities(query.trim()),
      builder: (context, snapshot) {
        final items = snapshot.data ?? const [];
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.accent),
            ),
          );
        }
        if (items.isEmpty) {
          return const Center(
            child: Text('没有匹配的设备',
                style: TextStyle(fontSize: 13, color: AppColors.textFaint)),
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: items.length,
          separatorBuilder: (_, __) => const Divider(height: 1, color: AppColors.border),
          itemBuilder: (context, i) {
            final item = items[i];
            final type = item['type'] as String? ?? '未分类';
            final color = AppColors.typeColor(type);
            return ListTile(
              leading: Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              title: Text(item['name'] as String? ?? '',
                  style: const TextStyle(fontSize: 14, color: AppColors.text)),
              subtitle: Text(type,
                  style: const TextStyle(fontSize: 11, color: AppColors.textFaint)),
              onTap: () => close(context, item['id'] as String?),
            );
          },
        );
      },
    );
  }
}

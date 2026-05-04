import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mise_gui/shared/ui/app_panel.dart';
import 'package:mise_gui/services/mise_process_service.dart';

class AsyncStateView<T> extends StatelessWidget {
  const AsyncStateView({super.key, required this.value, required this.builder});

  final AsyncValue<T> value;
  final Widget Function(T data) builder;

  @override
  Widget build(BuildContext context) {
    return value.when(
      data: builder,
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stackTrace) {
        final isMissingMise = isMiseCommandUnavailable(error);
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: AppPanel(
              child: isMissingMise
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '还没有检测到 mise',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          '当前页面需要可用的 mise CLI 才能继续读取环境信息。先完成安装，再回到应用里刷新即可。',
                        ),
                        const SizedBox(height: 16),
                        SelectableText(
                          recommendedMiseInstallCommand(),
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ],
                    )
                  : Text('页面加载失败: $error'),
            ),
          ),
        );
      },
    );
  }
}

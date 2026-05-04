import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mise_gui/app/theme/app_theme.dart';
import 'package:mise_gui/models/app_models.dart';
import 'package:mise_gui/shared/ui/status_badge.dart';

Future<void> showHistoryEntryDialog(
  BuildContext context, {
  required HistoryEntry entry,
}) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => _HistoryEntryDialog(entry: entry),
  );
}

class _HistoryEntryDialog extends StatelessWidget {
  const _HistoryEntryDialog({required this.entry});

  final HistoryEntry entry;

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colorsOf(context);

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(28),
      child: Container(
        constraints: const BoxConstraints(
          maxWidth: 960,
          maxHeight: 720,
        ),
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: colors.panel,
          borderRadius: BorderRadius.circular(30),
          border: Border.all(color: colors.borderStrong),
          boxShadow: [
            BoxShadow(
              color: colors.backgroundDeep.withValues(alpha: 0.16),
              blurRadius: 40,
              offset: const Offset(0, 20),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      StatusBadge(
                        label: entry.status.label,
                        level: entry.isFailure ? HealthLevel.warning : entry.level,
                      ),
                      const SizedBox(height: 14),
                      Text(
                        '操作详情',
                        style: Theme.of(context).textTheme.headlineMedium,
                      ),
                      const SizedBox(height: 10),
                      Text(
                        entry.detail,
                        style: TextStyle(
                          color: colors.textMuted,
                          height: 1.55,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
            const SizedBox(height: 22),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _FactChip(label: '时间', value: entry.timestamp),
                _FactChip(label: '结果', value: entry.outcomeLabel),
                if (entry.exitCode != null)
                  _FactChip(label: '退出码', value: '${entry.exitCode}'),
                if (entry.durationMs != null)
                  _FactChip(label: '耗时', value: '${entry.durationMs}ms'),
              ],
            ),
            const SizedBox(height: 18),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 6,
                    child: _CodeSection(
                      title: '实际命令',
                      content: entry.command,
                      trailing: TextButton.icon(
                        onPressed: () async {
                          await Clipboard.setData(ClipboardData(text: entry.command));
                          if (!context.mounted) {
                            return;
                          }
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('已复制实际 CLI 命令。')),
                          );
                        },
                        icon: const Icon(Icons.content_copy_rounded, size: 16),
                        label: const Text('复制命令'),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    flex: 7,
                    child: Column(
                      children: [
                        Expanded(
                          child: _CodeSection(
                            title: '标准输出',
                            content: entry.stdout?.trim().isNotEmpty == true
                                ? entry.stdout!
                                : '没有记录到标准输出。',
                          ),
                        ),
                        const SizedBox(height: 16),
                        Expanded(
                          child: _CodeSection(
                            title: '错误输出',
                            content: entry.stderr?.trim().isNotEmpty == true
                                ? entry.stderr!
                                : '没有记录到错误输出。',
                            emphasize: entry.isFailure,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FactChip extends StatelessWidget {
  const _FactChip({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colorsOf(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: colors.panelRaised.withValues(alpha: 0.86),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: colors.border),
      ),
      child: Text(
        '$label: $value',
        style: TextStyle(
          color: colors.textMuted,
          fontSize: 12,
          fontFamily: 'FiraCode',
        ),
      ),
    );
  }
}

class _CodeSection extends StatelessWidget {
  const _CodeSection({
    required this.title,
    required this.content,
    this.trailing,
    this.emphasize = false,
  });

  final String title;
  final String content;
  final Widget? trailing;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colorsOf(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: colors.backgroundSoft,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: emphasize
              ? colors.danger.withValues(alpha: 0.28)
              : colors.border,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontFamily: 'FiraCode',
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (trailing != null) trailing!,
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: SingleChildScrollView(
              child: SelectableText(
                content,
                style: TextStyle(
                  fontFamily: 'FiraCode',
                  fontSize: 13,
                  height: 1.6,
                  color: emphasize ? colors.danger : colors.textPrimary,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

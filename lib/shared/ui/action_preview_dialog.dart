import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mise_gui/app/theme/app_theme.dart';
import 'package:mise_gui/models/app_models.dart';

class ActionPreviewDialogData {
  const ActionPreviewDialogData({
    required this.title,
    required this.summary,
    required this.command,
    required this.level,
    this.diffPreview,
    this.affectedFiles = const [],
    this.impactScope = const [],
    this.riskNotes = const [],
    this.confirmLabel,
  });

  final String title;
  final String summary;
  final String command;
  final HealthLevel level;
  final String? diffPreview;
  final List<String> affectedFiles;
  final List<String> impactScope;
  final List<String> riskNotes;
  final String? confirmLabel;

  bool get requiresConfirmation => confirmLabel != null;
}

Future<bool> showActionPreviewDialog(
  BuildContext context, {
  required ActionPreviewDialogData data,
}) async {
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: !data.requiresConfirmation,
    builder: (dialogContext) => _ActionPreviewDialog(data: data),
  );
  return result ?? false;
}

class _ActionPreviewDialog extends StatelessWidget {
  const _ActionPreviewDialog({required this.data});

  final ActionPreviewDialogData data;

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colorsOf(context);

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(28),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 1040, maxHeight: 760),
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
        child: LayoutBuilder(
          builder: (context, constraints) {
            final stacked = constraints.maxWidth < 900;
            final commandPanel = SizedBox(
              height: 210,
              child: _CodeCard(
                title: '实际命令',
                content: data.command,
                trailing: TextButton.icon(
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: data.command));
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
            );

            final sidePanel = _MetaPanel(data: data);

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            data.title,
                            style: Theme.of(context).textTheme.headlineMedium,
                          ),
                          const SizedBox(height: 10),
                          Text(
                            data.summary,
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
                      onPressed: () => Navigator.of(context).pop(false),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: 22),
                Expanded(
                  child: stacked
                      ? Column(
                          children: [
                            commandPanel,
                            const SizedBox(height: 16),
                            if (data.diffPreview != null &&
                                data.diffPreview!.trim().isNotEmpty) ...[
                              Expanded(
                                child: _CodeCard(
                                  title: '差异预览',
                                  content: data.diffPreview!,
                                ),
                              ),
                              const SizedBox(height: 16),
                            ],
                            sidePanel,
                          ],
                        )
                      : Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              flex: 7,
                              child: Column(
                                children: [
                                  commandPanel,
                                  if (data.diffPreview != null &&
                                      data.diffPreview!.trim().isNotEmpty) ...[
                                    const SizedBox(height: 16),
                                    Expanded(
                                      child: _CodeCard(
                                        title: '差异预览',
                                        content: data.diffPreview!,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            const SizedBox(width: 16),
                            SizedBox(width: 300, child: sidePanel),
                          ],
                        ),
                ),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(false),
                      child: Text(data.requiresConfirmation ? '取消' : '关闭'),
                    ),
                    if (data.requiresConfirmation) ...[
                      const SizedBox(width: 12),
                      FilledButton.icon(
                        onPressed: () => Navigator.of(context).pop(true),
                        icon: const Icon(Icons.check_circle_outline_rounded),
                        label: Text(data.confirmLabel!),
                      ),
                    ],
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _MetaPanel extends StatelessWidget {
  const _MetaPanel({required this.data});

  final ActionPreviewDialogData data;

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colorsOf(context);

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (data.affectedFiles.isNotEmpty)
            _InfoBlock(
              title: '影响文件',
              children: [
                for (final file in data.affectedFiles)
                  _MetaLine(text: file, color: colors.textPrimary, mono: true),
              ],
            ),
          if (data.impactScope.isNotEmpty) ...[
            if (data.affectedFiles.isNotEmpty) const SizedBox(height: 14),
            _InfoBlock(
              title: '影响范围',
              children: [
                for (final item in data.impactScope)
                  _MetaLine(text: item, color: colors.textPrimary),
              ],
            ),
          ],
          if (data.riskNotes.isNotEmpty) ...[
            if (data.affectedFiles.isNotEmpty || data.impactScope.isNotEmpty)
              const SizedBox(height: 14),
            _InfoBlock(
              title: '风险提示',
              children: [
                for (final item in data.riskNotes)
                  _MetaLine(text: item, color: colors.warning),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _InfoBlock extends StatelessWidget {
  const _InfoBlock({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colorsOf(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.panelRaised.withValues(alpha: 0.86),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontFamily: 'FiraCode',
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }
}

class _MetaLine extends StatelessWidget {
  const _MetaLine({required this.text, required this.color, this.mono = false});

  final String text;
  final Color color;
  final bool mono;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 7),
            child: Icon(Icons.adjust_rounded, size: 12, color: color),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: color,
                height: 1.45,
                fontFamily: mono ? 'FiraCode' : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CodeCard extends StatelessWidget {
  const _CodeCard({required this.title, required this.content, this.trailing});

  final String title;
  final String content;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colorsOf(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: colors.backgroundSoft,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: colors.border),
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
                style: const TextStyle(
                  fontFamily: 'FiraCode',
                  fontSize: 13,
                  height: 1.6,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

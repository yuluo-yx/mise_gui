import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mise_gui/app/bootstrap/dependencies.dart';
import 'package:mise_gui/app/theme/app_theme.dart';
import 'package:mise_gui/features/config/application/config_provider.dart';
import 'package:mise_gui/features/projects/application/projects_provider.dart';
import 'package:mise_gui/models/app_models.dart';
import 'package:mise_gui/shared/ui/action_preview_dialog.dart';
import 'package:mise_gui/shared/ui/app_page_scaffold.dart';
import 'package:mise_gui/shared/ui/app_panel.dart';
import 'package:mise_gui/shared/ui/async_state_view.dart';
import 'package:mise_gui/shared/ui/status_badge.dart';

class ConfigPage extends ConsumerStatefulWidget {
  const ConfigPage({super.key});

  @override
  ConsumerState<ConfigPage> createState() => _ConfigPageState();
}

class _ConfigPageState extends ConsumerState<ConfigPage> {
  static const _refreshDebounce = Duration(seconds: 1);

  DateTime? _lastRefreshAt;
  var _refreshing = false;

  Future<void> _handleRefresh() async {
    if (_refreshing) {
      _showFeedback('正在刷新配置，请稍候。');
      return;
    }

    final now = DateTime.now();
    if (_lastRefreshAt != null &&
        now.difference(_lastRefreshAt!) < _refreshDebounce) {
      _showFeedback('点击过于频繁，请 1 秒后再试。');
      return;
    }

    _lastRefreshAt = now;
    setState(() => _refreshing = true);

    try {
      final refreshed = ref.refresh(configProvider.future);
      await refreshed;
      _showFeedback('配置数据已刷新。');
    } catch (_) {
      _showFeedback('刷新失败，请稍后重试。');
    } finally {
      if (mounted) {
        setState(() => _refreshing = false);
      }
    }
  }

  void _showFeedback(String message) {
    if (!mounted) {
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    messenger.removeCurrentSnackBar();
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final configValue = ref.watch(configProvider);
    final projectOptions = ref
        .watch(projectsProvider)
        .maybeWhen(
          data: (items) => items,
          orElse: () => const <ProjectRecord>[],
        );
    final selectedProject = ref.watch(selectedConfigProjectProvider);

    return AsyncStateView(
      value: configValue,
      builder: (workspace) => AppPageScaffold(
        title: '配置管理',
        description: '管理全局和项目配置，保存前先查看差异。',
        child: Column(
          children: [
            _ConfigAutoRefresh(
              paths: workspace.documents
                  .map((document) => document.path)
                  .toList(),
            ),
            _DocumentStrip(
              documents: workspace.documents,
              projectOptions: projectOptions,
              selectedProject: selectedProject,
              onSelectProject: (path) {
                ref.read(selectedConfigProjectPathProvider.notifier).state =
                    path;
              },
              refreshing: _refreshing,
              onRefresh: _handleRefresh,
              onEditDocument: (document) => _openDocumentEditor(
                context: context,
                ref: ref,
                document: document,
              ),
            ),
            if (workspace.runtimeSettings case final runtimeSettings?) ...[
              const SizedBox(height: 18),
              _RuntimeSettingsPanel(
                settings: runtimeSettings,
                onEdit: () => _openRuntimeSettingsEditor(
                  context: context,
                  ref: ref,
                  settings: runtimeSettings,
                ),
              ),
            ],
            const SizedBox(height: 18),
            for (final section in workspace.sections)
              Padding(
                padding: const EdgeInsets.only(bottom: 18),
                child: _ConfigSection(section: section),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _openDocumentEditor({
    required BuildContext context,
    required WidgetRef ref,
    required ConfigDocumentData document,
  }) async {
    final didSave = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) =>
          _ConfigDocumentEditorDialog(document: document),
    );

    if (didSave == true && context.mounted) {
      ref.invalidate(configProvider);
      final messenger = ScaffoldMessenger.of(context);
      messenger.removeCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(content: Text('${document.title} 已写回 ${document.fileName}')),
      );
    }
  }

  Future<void> _openRuntimeSettingsEditor({
    required BuildContext context,
    required WidgetRef ref,
    required ConfigRuntimeSettingsData settings,
  }) async {
    final didSave = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) =>
          _RuntimeSettingsEditorDialog(settings: settings),
    );

    if (didSave == true && context.mounted) {
      ref.invalidate(configProvider);
      final messenger = ScaffoldMessenger.of(context);
      messenger.removeCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(
          content: Text('全局运行时设置已写回 ${settings.document.fileName}'),
        ),
      );
    }
  }
}

class _ConfigAutoRefresh extends ConsumerStatefulWidget {
  const _ConfigAutoRefresh({required this.paths});

  final List<String> paths;

  @override
  ConsumerState<_ConfigAutoRefresh> createState() => _ConfigAutoRefreshState();
}

class _ConfigAutoRefreshState extends ConsumerState<_ConfigAutoRefresh> {
  StreamSubscription<void>? _subscription;

  @override
  void initState() {
    super.initState();
    _bindWatcher();
  }

  @override
  void didUpdateWidget(covariant _ConfigAutoRefresh oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!listEquals(oldWidget.paths, widget.paths)) {
      _bindWatcher();
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  void _bindWatcher() {
    _subscription?.cancel();
    _subscription = ref
        .read(configWatchServiceProvider)
        .watchPaths(widget.paths)
        .listen((_) {
          ref.invalidate(configProvider);
        });
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

class _DocumentStrip extends StatelessWidget {
  const _DocumentStrip({
    required this.documents,
    required this.projectOptions,
    required this.selectedProject,
    required this.onSelectProject,
    required this.refreshing,
    required this.onRefresh,
    required this.onEditDocument,
  });

  final List<ConfigDocumentData> documents;
  final List<ProjectRecord> projectOptions;
  final ProjectRecord? selectedProject;
  final ValueChanged<String?> onSelectProject;
  final bool refreshing;
  final VoidCallback onRefresh;
  final ValueChanged<ConfigDocumentData> onEditDocument;

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colorsOf(context);
    ConfigDocumentData? globalDocument;
    ConfigDocumentData? projectDocument;
    for (final document in documents) {
      if (document.id == 'global') {
        globalDocument = document;
      } else if (document.id == 'workspace') {
        projectDocument = document;
      }
    }

    return AppPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '配置文件',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              TextButton.icon(
                onPressed: refreshing ? null : onRefresh,
                icon: refreshing
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh_rounded, size: 18),
                label: Text(refreshing ? '刷新中...' : '刷新'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '先确认当前有哪些配置文件，再选择要查看的项目配置。',
            style: TextStyle(color: colors.textMuted, height: 1.45),
          ),
          if (globalDocument != null) ...[
            const SizedBox(height: 18),
            _GlobalDocumentBar(
              document: globalDocument,
              onEdit: () => onEditDocument(globalDocument!),
            ),
            if (projectOptions.isNotEmpty || projectDocument != null) ...[
              const SizedBox(height: 18),
              Divider(
                height: 1,
                thickness: 1,
                color: colors.border.withValues(alpha: 0.9),
              ),
            ],
          ],
          if (projectOptions.isNotEmpty) ...[
            const SizedBox(height: 18),
            _ProjectSelector(
              projectOptions: projectOptions,
              selectedProject: selectedProject,
              onSelectProject: onSelectProject,
            ),
          ],
          if (projectDocument != null) ...[
            if (projectOptions.isNotEmpty) ...[
              const SizedBox(height: 18),
              Divider(
                height: 1,
                thickness: 1,
                color: colors.border.withValues(alpha: 0.9),
              ),
            ],
            const SizedBox(height: 18),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: _DocumentCard(
                document: projectDocument,
                onEdit: () => onEditDocument(projectDocument!),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _GlobalDocumentBar extends StatelessWidget {
  const _GlobalDocumentBar({required this.document, required this.onEdit});

  final ConfigDocumentData document;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colorsOf(context);

    return Wrap(
      spacing: 16,
      runSpacing: 16,
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '全局默认配置',
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              Text(
                '这里定义项目默认继承的基线版本和基础设置。',
                style: TextStyle(color: colors.textMuted, height: 1.45),
              ),
              const SizedBox(height: 12),
              _DocumentPathLine(document: document),
            ],
          ),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: onEdit,
            icon: Icon(
              document.exists ? Icons.edit_note_rounded : Icons.add_rounded,
            ),
            label: Text(document.exists ? '编辑全局' : '创建全局'),
          ),
        ),
      ],
    );
  }
}

class _ProjectSelector extends StatelessWidget {
  const _ProjectSelector({
    required this.projectOptions,
    required this.selectedProject,
    required this.onSelectProject,
  });

  final List<ProjectRecord> projectOptions;
  final ProjectRecord? selectedProject;
  final ValueChanged<String?> onSelectProject;

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colorsOf(context);
    final dropdownValue = selectedProject?.path;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '当前配置项目',
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        SizedBox(
          width: 360,
          child: DropdownButtonFormField<String>(
            initialValue: dropdownValue,
            isExpanded: true,
            decoration: const InputDecoration(
              hintText: '选择要查看的项目配置',
              isDense: true,
            ),
            items: [
              for (final project in projectOptions)
                DropdownMenuItem<String>(
                  value: project.path,
                  child: Text(project.name, overflow: TextOverflow.ellipsis),
                ),
            ],
            onChanged: onSelectProject,
          ),
        ),
        if (selectedProject != null) ...[
          const SizedBox(height: 6),
          Text(
            selectedProject!.path,
            style: TextStyle(
              color: colors.textMuted,
              fontSize: 12,
              height: 1.45,
            ),
          ),
        ],
      ],
    );
  }
}

class _DocumentCard extends StatelessWidget {
  const _DocumentCard({required this.document, required this.onEdit});

  final ConfigDocumentData document;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colorsOf(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!document.exists) ...[
          const StatusBadge(label: '待创建', level: HealthLevel.info),
          const SizedBox(height: 12),
        ],
        Text(document.title, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 6),
        Text(
          document.description,
          style: TextStyle(color: colors.textMuted, height: 1.5),
        ),
        const SizedBox(height: 12),
        _DocumentPathLine(document: document),
        const SizedBox(height: 14),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: onEdit,
            icon: Icon(
              document.exists ? Icons.edit_note_rounded : Icons.add_rounded,
            ),
            label: Text(
              document.id == 'global'
                  ? (document.exists ? '编辑全局' : '创建全局')
                  : (document.exists ? '编辑项目配置' : '创建项目配置'),
            ),
          ),
        ),
      ],
    );
  }
}

class _DocumentPathLine extends StatelessWidget {
  const _DocumentPathLine({required this.document});

  final ConfigDocumentData document;

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colorsOf(context);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.description_outlined, size: 16, color: colors.textMuted),
        const SizedBox(width: 8),
        Expanded(
          child: SelectableText(
            document.path,
            style: const TextStyle(
              fontFamily: 'FiraCode',
              fontSize: 12,
              height: 1.5,
            ),
          ),
        ),
      ],
    );
  }
}

class _RuntimeSettingsPanel extends StatelessWidget {
  const _RuntimeSettingsPanel({required this.settings, required this.onEdit});

  final ConfigRuntimeSettingsData settings;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colorsOf(context);
    final configuredCount = settings.records
        .where((record) => record.isConfigured)
        .length;
    final visibleRecords = settings.records.take(4).toList();

    return AppPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 16,
            runSpacing: 14,
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 760),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '全局运行时设置',
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '结构化编辑 ~/.config/mise/config.toml 里的 [settings] 常用项。',
                      style: TextStyle(color: colors.textMuted, height: 1.5),
                    ),
                  ],
                ),
              ),
              FilledButton.icon(
                onPressed: onEdit,
                icon: const Icon(Icons.tune_rounded),
                label: const Text('编辑运行时设置'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              StatusBadge(
                label: '$configuredCount 项已配置',
                level: configuredCount == 0
                    ? HealthLevel.info
                    : HealthLevel.healthy,
              ),
              StatusBadge(
                label: settings.document.exists ? '全局配置已存在' : '待创建全局配置',
                level: settings.document.exists
                    ? HealthLevel.healthy
                    : HealthLevel.info,
              ),
            ],
          ),
          const SizedBox(height: 16),
          for (var index = 0; index < visibleRecords.length; index++) ...[
            _ConfigItemRow(
              item: ConfigItem(
                label: visibleRecords[index].label,
                value: visibleRecords[index].displayValue,
                detail: visibleRecords[index].description,
                level: visibleRecords[index].isConfigured
                    ? HealthLevel.healthy
                    : HealthLevel.info,
                isEditable: true,
              ),
            ),
            if (index != visibleRecords.length - 1)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 14),
                child: Divider(
                  height: 1,
                  thickness: 1,
                  color: colors.border.withValues(alpha: 0.9),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _ConfigSection extends StatelessWidget {
  const _ConfigSection({required this.section});

  final ConfigSectionData section;

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colorsOf(context);

    return AppPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                section.title,
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 10),
              Text(
                section.description,
                style: TextStyle(color: colors.textMuted, height: 1.55),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _ConfigItemGroup(section: section),
          const SizedBox(height: 14),
          _ConfigRawPanel(content: section.rawSnippet),
        ],
      ),
    );
  }
}

class _ConfigItemGroup extends StatelessWidget {
  const _ConfigItemGroup({required this.section});

  final ConfigSectionData section;

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colorsOf(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var index = 0; index < section.items.length; index++) ...[
          _ConfigItemRow(item: section.items[index]),
          if (index != section.items.length - 1)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Divider(
                height: 1,
                thickness: 1,
                color: colors.border.withValues(alpha: 0.9),
              ),
            ),
        ],
      ],
    );
  }
}

class _ConfigItemRow extends StatelessWidget {
  const _ConfigItemRow({required this.item});

  final ConfigItem item;

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colorsOf(context);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.label,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                item.detail,
                style: TextStyle(color: colors.textMuted, height: 1.5),
              ),
            ],
          ),
        ),
        const SizedBox(width: 18),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 220),
          child: Text(
            item.value,
            textAlign: TextAlign.right,
            style: TextStyle(
              color: _statusColor(context, item.level),
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }

  Color _statusColor(BuildContext context, HealthLevel level) {
    final colors = AppTheme.colorsOf(context);
    return switch (level) {
      HealthLevel.healthy => colors.accent,
      HealthLevel.info => colors.info,
      HealthLevel.warning => colors.warning,
      HealthLevel.critical => colors.danger,
    };
  }
}

class _ConfigRawPanel extends StatelessWidget {
  const _ConfigRawPanel({required this.content});

  final String content;

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colorsOf(context);

    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(top: 12),
        title: const Text(
          '原始配置',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Text(
          '展开查看这一组对应的 TOML 内容',
          style: TextStyle(color: colors.textMuted, fontSize: 12),
        ),
        children: [_CodePanel(title: 'TOML', content: content, height: 320)],
      ),
    );
  }
}

enum _RuntimeBooleanChoice {
  unset('跟随默认'),
  enabled('开启'),
  disabled('关闭');

  const _RuntimeBooleanChoice(this.label);

  final String label;
}

class _RuntimeSettingsEditorDialog extends ConsumerStatefulWidget {
  const _RuntimeSettingsEditorDialog({required this.settings});

  final ConfigRuntimeSettingsData settings;

  @override
  ConsumerState<_RuntimeSettingsEditorDialog> createState() =>
      _RuntimeSettingsEditorDialogState();
}

class _RuntimeSettingsEditorDialogState
    extends ConsumerState<_RuntimeSettingsEditorDialog> {
  late final Map<String, TextEditingController> _controllers;
  late final Map<String, _RuntimeBooleanChoice> _booleanValues;
  String? _error;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _controllers = {
      for (final record in widget.settings.records)
        if (record.type != RuntimeSettingValueType.boolean)
          record.key: TextEditingController(
            text: record.isConfigured ? record.displayValue : '',
          ),
    };
    _booleanValues = {
      for (final record in widget.settings.records)
        if (record.type == RuntimeSettingValueType.boolean)
          record.key: _choiceFor(record),
    };
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colorsOf(context);
    final size = MediaQuery.sizeOf(context);

    return Dialog(
      insetPadding: const EdgeInsets.all(28),
      backgroundColor: Colors.transparent,
      child: Container(
        width: size.width * 0.78,
        height: size.height * 0.82,
        constraints: const BoxConstraints(maxWidth: 980),
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          color: colors.panel,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: colors.borderStrong),
          boxShadow: [
            BoxShadow(
              blurRadius: 32,
              color: colors.backgroundDeep.withValues(alpha: 0.24),
              offset: const Offset(0, 18),
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
                      Text(
                        '编辑全局运行时设置',
                        style: Theme.of(context).textTheme.headlineMedium,
                      ),
                      const SizedBox(height: 10),
                      SelectableText(
                        widget.settings.document.path,
                        style: TextStyle(
                          color: colors.textMuted,
                          fontFamily: 'FiraCode',
                          fontSize: 12,
                          height: 1.45,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: _saving
                      ? null
                      : () => Navigator.of(context).pop(false),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
            if (_error != null) ...[
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: colors.danger.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: colors.danger.withValues(alpha: 0.32),
                  ),
                ),
                child: Text(
                  _error!,
                  style: TextStyle(color: colors.danger, height: 1.45),
                ),
              ),
            ],
            const SizedBox(height: 18),
            Expanded(
              child: ListView.separated(
                itemCount: widget.settings.records.length,
                separatorBuilder: (context, index) => Divider(
                  height: 28,
                  thickness: 1,
                  color: colors.border.withValues(alpha: 0.82),
                ),
                itemBuilder: (context, index) {
                  final record = widget.settings.records[index];
                  return _RuntimeSettingEditorRow(
                    record: record,
                    textController: _controllers[record.key],
                    booleanValue: _booleanValues[record.key],
                    onBooleanChanged: (value) {
                      if (value == null) {
                        return;
                      }
                      setState(() {
                        _booleanValues[record.key] = value;
                        _error = null;
                      });
                    },
                  );
                },
              ),
            ),
            const SizedBox(height: 18),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              alignment: WrapAlignment.end,
              children: [
                OutlinedButton(
                  onPressed: _saving
                      ? null
                      : () => Navigator.of(context).pop(false),
                  child: const Text('取消'),
                ),
                FilledButton.icon(
                  onPressed: _saving ? null : _previewAndSave,
                  icon: _saving
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save_outlined),
                  label: Text(_saving ? '保存中...' : '预览并保存'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _previewAndSave() async {
    final values = _collectValues();
    if (values == null || !mounted) {
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final repository = ref.read(configRepositoryProvider);
      final preview = await repository.previewRuntimeSettingsSave(
        document: widget.settings.document,
        values: values,
      );
      if (!mounted) {
        return;
      }
      if (!preview.hasChanges) {
        _showFeedback('运行时设置没有变化。');
        return;
      }

      final confirmed = await showActionPreviewDialog(
        context,
        data: ActionPreviewDialogData(
          title: '确认保存运行时设置',
          summary: '保存后会直接写回全局 mise 配置文件。',
          command: preview.commandPreview,
          level: HealthLevel.warning,
          diffPreview: preview.diffPreview,
          affectedFiles: [widget.settings.document.path],
          impactScope: const ['影响后续 mise 命令读取到的全局 [settings]。'],
          riskNotes: const ['保存前请确认差异预览符合预期。'],
          confirmLabel: '保存设置',
        ),
      );
      if (!confirmed || !mounted) {
        return;
      }

      final stopwatch = Stopwatch()..start();
      await repository.saveDocument(
        document: widget.settings.document,
        nextContent: preview.nextContent,
      );
      stopwatch.stop();
      await ref
          .read(historyServiceProvider)
          .appendEntry(
            HistoryEntry(
              command: preview.commandPreview,
              timestamp: _formatNow(),
              detail: preview.createsFile
                  ? '已通过界面创建并写入全局运行时设置。'
                  : '已通过界面写回全局运行时设置。',
              level: preview.createsFile
                  ? HealthLevel.info
                  : HealthLevel.warning,
              status: HistoryStatus.success,
              exitCode: 0,
              durationMs: stopwatch.elapsedMilliseconds,
              stdout: widget.settings.document.path,
              stdoutSnippet: widget.settings.document.path,
            ),
          );
      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  Map<String, String?>? _collectValues() {
    final values = <String, String?>{};
    for (final record in widget.settings.records) {
      switch (record.type) {
        case RuntimeSettingValueType.boolean:
          final choice = _booleanValues[record.key];
          if (choice == _RuntimeBooleanChoice.enabled) {
            values[record.key] = 'true';
          } else if (choice == _RuntimeBooleanChoice.disabled) {
            values[record.key] = 'false';
          } else {
            values[record.key] = null;
          }
          continue;
        case RuntimeSettingValueType.integer:
          final value = _controllers[record.key]!.text.trim();
          if (value.isEmpty) {
            values[record.key] = null;
            continue;
          }
          final number = int.tryParse(value);
          final min = record.key == 'jobs' ? 1 : 0;
          if (number == null || number < min) {
            _setValidationError('${record.label} 必须是不小于 $min 的整数。');
            return null;
          }
          values[record.key] = number.toString();
          continue;
        case RuntimeSettingValueType.durationString:
          final value = _controllers[record.key]!.text.trim();
          if (value.isEmpty) {
            values[record.key] = null;
            continue;
          }
          if (!_isValidDuration(value)) {
            _setValidationError(
              '${record.label} 需要填写带单位的时长，例如 30s、5m、1h。',
            );
            return null;
          }
          values[record.key] = value;
          continue;
        case RuntimeSettingValueType.plainString:
          final value = _controllers[record.key]!.text.trim();
          if (value.isEmpty) {
            values[record.key] = null;
            continue;
          }
          if (value.contains('\n') || value.contains('\r')) {
            _setValidationError('${record.label} 不能包含换行。');
            return null;
          }
          values[record.key] = value;
          continue;
      }
    }
    return values;
  }

  bool _isValidDuration(String value) {
    return RegExp(
      r'^\d+\s*(ms|s|m|h|d|day|days|week|weeks)$',
      caseSensitive: false,
    ).hasMatch(value);
  }

  void _setValidationError(String message) {
    if (!mounted) {
      return;
    }
    setState(() {
      _error = message;
    });
  }

  void _showFeedback(String message) {
    if (!mounted) {
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    messenger.removeCurrentSnackBar();
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }

  String _formatNow() {
    final now = DateTime.now();
    final hours = now.hour.toString().padLeft(2, '0');
    final minutes = now.minute.toString().padLeft(2, '0');
    return '$hours:$minutes';
  }

  static _RuntimeBooleanChoice _choiceFor(RuntimeSettingRecord record) {
    if (!record.isConfigured) {
      return _RuntimeBooleanChoice.unset;
    }
    return record.displayValue.toLowerCase() == 'true'
        ? _RuntimeBooleanChoice.enabled
        : _RuntimeBooleanChoice.disabled;
  }
}

class _RuntimeSettingEditorRow extends StatelessWidget {
  const _RuntimeSettingEditorRow({
    required this.record,
    required this.textController,
    required this.booleanValue,
    required this.onBooleanChanged,
  });

  final RuntimeSettingRecord record;
  final TextEditingController? textController;
  final _RuntimeBooleanChoice? booleanValue;
  final ValueChanged<_RuntimeBooleanChoice?> onBooleanChanged;

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colorsOf(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        final stacked = constraints.maxWidth < 680;
        final title = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              record.label,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              record.description,
              style: TextStyle(color: colors.textMuted, height: 1.45),
            ),
            const SizedBox(height: 6),
            Text(
              record.key,
              style: TextStyle(
                color: colors.textMuted.withValues(alpha: 0.82),
                fontFamily: 'FiraCode',
                fontSize: 12,
              ),
            ),
          ],
        );
        final field = SizedBox(
          width: stacked ? double.infinity : 240,
          child: _field(),
        );

        if (stacked) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [title, const SizedBox(height: 12), field],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: title),
            const SizedBox(width: 18),
            field,
          ],
        );
      },
    );
  }

  Widget _field() {
    if (record.type == RuntimeSettingValueType.boolean) {
      return DropdownButtonFormField<_RuntimeBooleanChoice>(
        initialValue: booleanValue,
        isExpanded: true,
        decoration: const InputDecoration(isDense: true),
        items: [
          for (final value in _RuntimeBooleanChoice.values)
            DropdownMenuItem(value: value, child: Text(value.label)),
        ],
        onChanged: onBooleanChanged,
      );
    }

    return TextField(
      controller: textController,
      autocorrect: false,
      enableSuggestions: false,
      decoration: InputDecoration(
        isDense: true,
        hintText: _hintFor(record),
      ),
    );
  }

  String _hintFor(RuntimeSettingRecord record) {
    return switch (record.type) {
      RuntimeSettingValueType.durationString => '30s',
      RuntimeSettingValueType.integer => record.key == 'jobs' ? '4' : '0',
      RuntimeSettingValueType.plainString => '.env',
      RuntimeSettingValueType.boolean => '',
    };
  }
}

class _ConfigDocumentEditorDialog extends ConsumerStatefulWidget {
  const _ConfigDocumentEditorDialog({required this.document});

  final ConfigDocumentData document;

  @override
  ConsumerState<_ConfigDocumentEditorDialog> createState() =>
      _ConfigDocumentEditorDialogState();
}

class _ConfigDocumentEditorDialogState
    extends ConsumerState<_ConfigDocumentEditorDialog> {
  late final TextEditingController _controller;
  ConfigSavePreview? _preview;
  bool _loadingPreview = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.document.content);
    _controller.addListener(_handleContentChanged);
  }

  @override
  void dispose() {
    _controller.removeListener(_handleContentChanged);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colorsOf(context);
    final size = MediaQuery.sizeOf(context);
    final hasPendingChanges = _hasPendingChanges;

    return Dialog(
      insetPadding: const EdgeInsets.all(28),
      backgroundColor: Colors.transparent,
      child: Container(
        width: size.width * 0.82,
        height: size.height * 0.82,
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          color: colors.panel,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: colors.borderStrong),
          boxShadow: [
            BoxShadow(
              blurRadius: 32,
              color: colors.backgroundDeep.withValues(alpha: 0.24),
              offset: const Offset(0, 18),
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
                      Text(
                        _preview == null
                            ? '编辑 ${widget.document.title}'
                            : '确认保存 ${widget.document.title}',
                        style: Theme.of(context).textTheme.headlineMedium,
                      ),
                      if (_preview == null) ...[
                        const SizedBox(height: 10),
                        Text(
                          '正在编辑 ${widget.document.path}',
                          style: TextStyle(
                            color: colors.textMuted,
                            height: 1.5,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: colors.backgroundSoft,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: colors.border),
              ),
              child: SelectableText(
                widget.document.path,
                style: const TextStyle(
                  fontFamily: 'FiraCode',
                  fontSize: 12,
                  height: 1.45,
                ),
              ),
            ),
            const SizedBox(height: 18),
            Expanded(
              child: _preview == null
                  ? _buildEditor(colors)
                  : _buildPreview(colors, _preview!),
            ),
            const SizedBox(height: 18),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              alignment: WrapAlignment.end,
              children: [
                if (_preview != null)
                  OutlinedButton.icon(
                    onPressed: _saving
                        ? null
                        : () {
                            setState(() {
                              _preview = null;
                            });
                          },
                    icon: const Icon(Icons.arrow_back_rounded),
                    label: const Text('返回编辑'),
                  ),
                OutlinedButton(
                  onPressed: _loadingPreview || _saving
                      ? null
                      : () => Navigator.of(context).pop(false),
                  child: const Text('取消'),
                ),
                if (_preview == null)
                  if (hasPendingChanges)
                    FilledButton(
                      onPressed: _loadingPreview ? null : _generatePreview,
                      child: Text(_loadingPreview ? '预览中...' : '预览变更'),
                    ),
                if (_preview != null)
                  FilledButton(
                    onPressed: _saving ? null : _saveDocument,
                    child: Text(_saving ? '保存中...' : '保存更改'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEditor(AppPalette colors) {
    return Container(
      decoration: BoxDecoration(
        color: colors.backgroundSoft,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: colors.border),
      ),
      child: TextField(
        controller: _controller,
        maxLines: null,
        expands: true,
        textAlignVertical: TextAlignVertical.top,
        autocorrect: false,
        enableSuggestions: false,
        style: const TextStyle(
          fontFamily: 'FiraCode',
          fontSize: 13,
          height: 1.6,
        ),
        decoration: const InputDecoration(
          border: InputBorder.none,
          contentPadding: EdgeInsets.all(18),
          hintText: '# 在这里编辑 TOML',
        ),
      ),
    );
  }

  Widget _buildPreview(AppPalette colors, ConfigSavePreview preview) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: _CodePanel(
            title: '差异预览',
            content: preview.diffPreview,
            expand: true,
          ),
        ),
      ],
    );
  }

  Future<void> _generatePreview() async {
    setState(() {
      _loadingPreview = true;
    });

    try {
      final preview = await ref
          .read(configRepositoryProvider)
          .previewSave(
            document: widget.document,
            nextContent: _controller.text,
          );
      if (!mounted) {
        return;
      }
      if (!preview.hasChanges) {
        _showFeedback('没有变更，无需预览。');
        return;
      }
      setState(() {
        _preview = preview;
      });
    } finally {
      if (mounted) {
        setState(() {
          _loadingPreview = false;
        });
      }
    }
  }

  Future<void> _saveDocument() async {
    final preview = _preview;
    if (preview == null || !preview.hasChanges) {
      return;
    }
    if (!mounted) {
      return;
    }

    setState(() {
      _saving = true;
    });

    try {
      final stopwatch = Stopwatch()..start();
      await ref
          .read(configRepositoryProvider)
          .saveDocument(
            document: widget.document,
            nextContent: preview.nextContent,
          );
      stopwatch.stop();
      await ref
          .read(historyServiceProvider)
          .appendEntry(
            HistoryEntry(
              command: preview.commandPreview,
              timestamp: _formatNow(),
              detail: preview.createsFile
                  ? '已通过界面创建并写入 ${widget.document.fileName}。'
                  : '已通过界面直接编辑并写回 ${widget.document.fileName}。',
              level: preview.createsFile
                  ? HealthLevel.info
                  : HealthLevel.warning,
              status: HistoryStatus.success,
              exitCode: 0,
              durationMs: stopwatch.elapsedMilliseconds,
              stdout: widget.document.path,
              stdoutSnippet: widget.document.path,
            ),
          );
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop(true);
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
    }
  }

  String _formatNow() {
    final now = DateTime.now();
    final hours = now.hour.toString().padLeft(2, '0');
    final minutes = now.minute.toString().padLeft(2, '0');
    return '$hours:$minutes';
  }

  void _showFeedback(String message) {
    if (!mounted) {
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    messenger.removeCurrentSnackBar();
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }

  bool get _hasPendingChanges =>
      _normalizeEditorContent(_controller.text) !=
      _normalizeEditorContent(widget.document.content);

  String _normalizeEditorContent(String value) {
    final normalized = value.replaceAll('\r\n', '\n');
    if (normalized.trim().isEmpty) {
      return '';
    }
    return normalized.endsWith('\n') ? normalized : '$normalized\n';
  }

  void _handleContentChanged() {
    if (!mounted || _preview != null) {
      return;
    }
    setState(() {});
  }
}

class _CodePanel extends StatelessWidget {
  const _CodePanel({
    required this.title,
    required this.content,
    this.height,
    this.expand = false,
  });

  final String title;
  final String content;
  final double? height;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colorsOf(context);

    final panel = Container(
      height: height,
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: colors.backgroundSoft,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colors.border),
      ),
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
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontFamily: 'FiraCode',
            fontSize: 17,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 12),
        if (expand) Expanded(child: panel) else panel,
      ],
    );
  }
}

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mise_gui/app/bootstrap/dependencies.dart';
import 'package:mise_gui/app/theme/app_theme.dart';
import 'package:mise_gui/features/dashboard/application/dashboard_provider.dart';
import 'package:mise_gui/features/tools/application/tools_provider.dart';
import 'package:mise_gui/models/app_models.dart';
import 'package:mise_gui/services/mise_process_service.dart';
import 'package:mise_gui/shared/ui/action_preview_dialog.dart';
import 'package:mise_gui/shared/ui/app_page_scaffold.dart';
import 'package:mise_gui/shared/ui/app_panel.dart';
import 'package:mise_gui/shared/ui/async_state_view.dart';
import 'package:mise_gui/shared/ui/history_entry_dialog.dart';
import 'package:mise_gui/shared/ui/inline_notice_bar.dart';
import 'package:mise_gui/shared/ui/status_badge.dart';

class ToolsPage extends ConsumerStatefulWidget {
  const ToolsPage({super.key});

  @override
  ConsumerState<ToolsPage> createState() => _ToolsPageState();
}

class _ToolsPageState extends ConsumerState<ToolsPage> {
  String? _selectedToolId;
  final Set<String> _requestedToolIds = <String>{};
  final Set<String> _loadingToolIds = <String>{};
  final Map<String, ToolRecord> _hydratedTools = <String, ToolRecord>{};
  var _refreshing = false;

  void _showFeedback(String message) {
    if (!mounted) {
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    messenger.removeCurrentSnackBar();
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _loadToolDetail(
    String toolId, {
    bool forceRefresh = false,
  }) async {
    if (_loadingToolIds.contains(toolId)) {
      return;
    }

    setState(() {
      _requestedToolIds.add(toolId);
      _loadingToolIds.add(toolId);
    });

    try {
      final detail = forceRefresh
          ? await ref.refresh(toolDetailProvider(toolId).future)
          : await ref.read(toolDetailProvider(toolId).future);
      if (!mounted) {
        return;
      }
      setState(() {
        _hydratedTools[toolId] = detail;
      });
    } catch (error) {
      _showFeedback('读取版本详情失败，请稍后重试。');
      if (!mounted) {
        return;
      }
      setState(() {
        _requestedToolIds.remove(toolId);
      });
    } finally {
      if (mounted) {
        setState(() {
          _loadingToolIds.remove(toolId);
        });
      }
    }
  }

  Future<void> _refreshTools() async {
    if (_refreshing) {
      _showFeedback('工具数据正在刷新，请稍候。');
      return;
    }

    setState(() {
      _refreshing = true;
      _hydratedTools.clear();
      _requestedToolIds.clear();
      _loadingToolIds.clear();
    });

    try {
      await ref.refresh(toolsProvider.future);
      final selectedToolId = _selectedToolId;
      if (selectedToolId != null) {
        await _loadToolDetail(selectedToolId, forceRefresh: true);
      }
      _showFeedback('工具状态已刷新。');
    } catch (_) {
      _showFeedback('刷新工具状态失败，请稍后重试。');
    } finally {
      if (mounted) {
        setState(() {
          _refreshing = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final toolsValue = ref.watch(toolsProvider);

    return AsyncStateView(
      value: toolsValue,
      builder: (tools) {
        final displayTools = tools
            .map((tool) => _hydratedTools[tool.id] ?? tool)
            .toList(growable: false);

        return AppPageScaffold(
          title: '工具版本',
          description: '按工具查看当前版本，并在需要时升级或卸载。',
          actions: [
            OutlinedButton.icon(
              onPressed: _refreshing ? null : _refreshTools,
              icon: _refreshing
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh_rounded),
              label: Text(_refreshing ? '刷新中...' : '刷新状态'),
            ),
            FilledButton.icon(
              onPressed: () => _openInstallToolFlow(context),
              icon: const Icon(Icons.add_circle_outline_rounded),
              label: const Text('安装工具'),
            ),
          ],
          child: _ToolList(
            tools: displayTools,
            selectedToolId: _selectedToolId,
            hydratedTools: _hydratedTools,
            loadingToolIds: _loadingToolIds,
            requestedToolIds: _requestedToolIds,
            onSelected: _selectTool,
            onOpenPreview: _openToolActionPreview,
          ),
        );
      },
    );
  }

  void _selectTool(String id) {
    if (_selectedToolId == id) {
      setState(() {
        _selectedToolId = null;
      });
      return;
    }

    setState(() {
      _selectedToolId = id;
      _requestedToolIds.add(id);
    });

    if (!_loadingToolIds.contains(id) && !_hydratedTools.containsKey(id)) {
      unawaited(_loadToolDetail(id));
    }
  }

  Future<void> _openInstallToolFlow(BuildContext context) async {
    final request = await showDialog<_InstallToolRequest>(
      context: context,
      builder: (dialogContext) => const _InstallToolDialog(),
    );
    if (request == null || !mounted || !context.mounted) {
      return;
    }

    final installCommand = 'mise install ${request.tool}@${request.version}';
    final useCommand = 'mise use --global ${request.tool}@${request.version}';

    await _openToolActionPreview(
      context,
      ActionPreviewDialogData(
        title: '安装 ${request.tool}@${request.version}',
        summary: '会先安装这个版本，再把它写成全局默认版本。',
        command: '$installCommand\n$useCommand',
        level: HealthLevel.info,
        affectedFiles: [_globalConfigPath(), 'mise 安装缓存 / 已安装版本'],
        impactScope: ['会改变全局默认工具版本。', '安装完成后会自动刷新工具页与总览页数据。'],
        riskNotes: const [
          '安装时需要访问网络，过程可能会持续一段时间。',
          '如果版本号无效，安装会失败，失败结果会记录到最近操作。',
        ],
        confirmLabel: '确认安装',
      ),
    );
  }

  Future<void> _openToolActionPreview(
    BuildContext context,
    ActionPreviewDialogData data,
  ) async {
    final rootNavigator = Navigator.of(context, rootNavigator: true);
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showActionPreviewDialog(context, data: data);
    if (!confirmed) {
      if (data.requiresConfirmation) {
        await ref
            .read(historyServiceProvider)
            .appendEntry(
              HistoryEntry(
                command: data.command,
                timestamp: _formatNow(),
                detail: '用户取消了 ${data.title}。',
                level: HealthLevel.info,
                status: HistoryStatus.canceled,
              ),
            );
      }
      return;
    }

    if (!mounted || !context.mounted || !data.requiresConfirmation) {
      return;
    }

    _showRunningDialog(context, title: data.title);
    HistoryEntry? failureEntryToShow;
    String? snackMessage;
    try {
      final result = await ref
          .read(miseActionServiceProvider)
          .runScript(data.command);
      if (!mounted || !context.mounted) {
        return;
      }

      final success = result.isSuccess;
      final diagnosis = success
          ? null
          : diagnoseMiseCommandFailure(
              command: data.command,
              stdout: result.stdout,
              stderr: result.stderr,
            );
      final historyEntry = HistoryEntry(
        command: data.command,
        timestamp: _formatNow(),
        detail: success
            ? '已通过界面执行 ${data.title}。'
            : diagnosis?.detail ?? '${data.title} 执行失败，已保留实际 CLI 和错误输出。',
        level: success ? data.level : HealthLevel.warning,
        status: success ? HistoryStatus.success : HistoryStatus.failure,
        exitCode: result.exitCode,
        durationMs: result.duration.inMilliseconds,
        stdout: result.stdout,
        stderr: result.stderr,
        stdoutSnippet: result.stdoutSnippet,
        stderrSnippet: result.stderrSnippet,
      );
      await ref.read(historyServiceProvider).appendEntry(historyEntry);

      if (success) {
        final affectedToolIds = _extractAffectedToolIds(data.command);
        if (mounted) {
          setState(() {
            if (affectedToolIds.isEmpty) {
              _hydratedTools.clear();
              _requestedToolIds.clear();
              _loadingToolIds.clear();
            } else {
              for (final toolId in affectedToolIds) {
                _hydratedTools.remove(toolId);
                _requestedToolIds.remove(toolId);
                _loadingToolIds.remove(toolId);
              }
            }
          });
        }

        ref.invalidate(toolsProvider);
        await ref.read(toolsProvider.future);
        ref.invalidate(dashboardProvider);

        if (!mounted) {
          return;
        }

        for (final toolId in affectedToolIds) {
          if (toolId == _selectedToolId) {
            unawaited(_loadToolDetail(toolId, forceRefresh: true));
          }
        }
      } else {
        ref.invalidate(dashboardProvider);
      }

      snackMessage = success
          ? '${data.title} 已执行完成。'
          : diagnosis == null
          ? '${data.title} 执行失败，已打开错误详情。'
          : '${data.title} 执行失败：${diagnosis.summary}';
      if (!success) {
        failureEntryToShow = historyEntry;
      }
    } catch (error) {
      final historyEntry = HistoryEntry(
        command: data.command,
        timestamp: _formatNow(),
        detail: '${data.title} 执行异常，界面已拦截并保留错误信息。',
        level: HealthLevel.warning,
        status: HistoryStatus.failure,
        exitCode: -1,
        stderr: error.toString(),
        stderrSnippet: error.toString(),
      );
      await ref.read(historyServiceProvider).appendEntry(historyEntry);
      snackMessage = '${data.title} 执行异常，已打开错误详情。';
      failureEntryToShow = historyEntry;
    } finally {
      if (rootNavigator.mounted && rootNavigator.canPop()) {
        rootNavigator.pop();
      }
    }

    if (!mounted || !context.mounted) {
      return;
    }

    messenger.removeCurrentSnackBar();
    messenger.showSnackBar(SnackBar(content: Text(snackMessage)));

    if (failureEntryToShow != null) {
      await showHistoryEntryDialog(context, entry: failureEntryToShow);
    }
  }

  void _showRunningDialog(BuildContext context, {required String title}) {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => PopScope(
        canPop: false,
        child: Dialog(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2.4),
                ),
                const SizedBox(width: 16),
                Flexible(child: Text('$title 正在执行，请稍候...')),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _formatNow() {
    final now = DateTime.now();
    final hours = now.hour.toString().padLeft(2, '0');
    final minutes = now.minute.toString().padLeft(2, '0');
    return '$hours:$minutes';
  }

  String _globalConfigPath() {
    final home = Platform.environment['HOME'];
    if (home == null || home.isEmpty) {
      return '~/.config/mise/config.toml';
    }
    return '$home/.config/mise/config.toml';
  }

  Set<String> _extractAffectedToolIds(String command) {
    final toolIds = <String>{};
    final matcher = RegExp(
      r'mise\s+install\s+([a-zA-Z0-9._-]+)|mise\s+uninstall\s+(?:--all\s+)?([a-zA-Z0-9._-]+)|mise\s+use\s+(?:--global\s+)?(?:--remove\s+)?([a-zA-Z0-9._-]+)',
      caseSensitive: false,
    );

    for (final match in matcher.allMatches(command)) {
      final toolId = (match.group(1) ?? match.group(2) ?? match.group(3))
          ?.trim();
      if (toolId != null && toolId.isNotEmpty) {
        toolIds.add(toolId);
      }
    }

    return toolIds;
  }
}

class _ToolWorkspaceLoading extends StatelessWidget {
  const _ToolWorkspaceLoading({required this.title, required this.message});

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colorsOf(context);

    return AppPanel(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                width: 30,
                height: 30,
                child: CircularProgressIndicator(strokeWidth: 2.6),
              ),
              const SizedBox(height: 18),
              Text(
                title,
                style: Theme.of(context).textTheme.titleLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 10),
              Text(
                message,
                style: TextStyle(color: colors.textMuted, height: 1.55),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InstallToolRequest {
  const _InstallToolRequest({required this.tool, required this.version});

  final String tool;
  final String version;
}

class _InstallToolDialog extends ConsumerStatefulWidget {
  const _InstallToolDialog();

  @override
  ConsumerState<_InstallToolDialog> createState() => _InstallToolDialogState();
}

class _InstallToolDialogState extends ConsumerState<_InstallToolDialog> {
  final TextEditingController _toolController = TextEditingController();
  final TextEditingController _versionController = TextEditingController();
  final FocusNode _versionFocusNode = FocusNode();
  Timer? _lookupDebounce;
  var _loadingVersions = false;
  List<String> _versionSuggestions = const [];
  String? _lookupMessage;
  int _lookupToken = 0;

  @override
  void initState() {
    super.initState();
    _toolController.addListener(_scheduleVersionLookup);
    _versionFocusNode.addListener(() {
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _lookupDebounce?.cancel();
    _toolController.removeListener(_scheduleVersionLookup);
    _toolController.dispose();
    _versionController.dispose();
    _versionFocusNode.dispose();
    super.dispose();
  }

  void _scheduleVersionLookup() {
    final tool = _toolController.text.trim();
    final scheduledToken = ++_lookupToken;

    _lookupDebounce?.cancel();
    if (mounted) {
      setState(() {
        _versionSuggestions = const [];
        _lookupMessage = tool.isEmpty ? null : '正在读取远端版本...';
        _loadingVersions = tool.isNotEmpty;
      });
    }
    _lookupDebounce = Timer(
      const Duration(milliseconds: 350),
      () => _loadRemoteVersions(scheduledToken),
    );
  }

  Future<void> _loadRemoteVersions(int token) async {
    final tool = _toolController.text.trim();

    if (tool.isEmpty) {
      if (mounted && token == _lookupToken) {
        setState(() {
          _loadingVersions = false;
          _versionSuggestions = const [];
          _lookupMessage = null;
        });
      }
      return;
    }

    setState(() {
      _loadingVersions = true;
      _lookupMessage = null;
    });

    try {
      final versions = await ref
          .read(miseQueryServiceProvider)
          .fetchRemoteVersions(tool);
      if (!mounted || token != _lookupToken) {
        return;
      }

      final stableVersions =
          versions
              .where((version) => !version.rolling)
              .map((version) => version.version)
              .toSet()
              .toList()
            ..sort(_compareVersionsDesc);
      final selected =
          (stableVersions.isNotEmpty
                    ? stableVersions
                    : versions
                          .map((version) => version.version)
                          .toSet()
                          .toList()
                ..sort(_compareVersionsDesc))
              .take(5)
              .toList(growable: false);

      setState(() {
        _loadingVersions = false;
        _versionSuggestions = selected;
        _lookupMessage = selected.isEmpty ? '没有拉到可选版本，仍可手动输入。' : null;
      });
    } catch (error) {
      if (!mounted || token != _lookupToken) {
        return;
      }
      setState(() {
        _loadingVersions = false;
        _versionSuggestions = const [];
        _lookupMessage = '远端版本读取失败，仍可手动输入版本号。';
      });
    }
  }

  int _compareVersionsDesc(String a, String b) {
    return _versionWeight(b).compareTo(_versionWeight(a));
  }

  int _versionWeight(String input) {
    final numbers = RegExp(r'\d+')
        .allMatches(input)
        .map((match) => int.tryParse(match.group(0)!) ?? 0)
        .take(4)
        .toList();

    while (numbers.length < 4) {
      numbers.add(0);
    }

    return numbers[0] * 100000000 +
        numbers[1] * 1000000 +
        numbers[2] * 10000 +
        numbers[3];
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colorsOf(context);

    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        width: 460,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: colors.panel,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: colors.borderStrong),
          boxShadow: [
            BoxShadow(
              color: colors.backgroundDeep.withValues(alpha: 0.14),
              blurRadius: 32,
              offset: const Offset(0, 18),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('安装新工具', style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: 10),
            Text(
              '输入要安装的工具名和版本，随后会进入执行前预览与确认。',
              style: TextStyle(color: colors.textMuted, height: 1.55),
            ),
            const SizedBox(height: 18),
            TextField(
              controller: _toolController,
              decoration: const InputDecoration(
                labelText: 'Tool',
                hintText: '例如: node / python / go / php',
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _versionController,
              focusNode: _versionFocusNode,
              decoration: const InputDecoration(
                labelText: 'Version',
                hintText: '例如: 20.19.0 / 3.12.9 / latest',
              ),
            ),
            if (_versionFocusNode.hasFocus &&
                (_loadingVersions ||
                    _versionSuggestions.isNotEmpty ||
                    _lookupMessage != null)) ...[
              const SizedBox(height: 10),
              _VersionSuggestionList(
                loading: _loadingVersions,
                versions: _versionSuggestions,
                message: _lookupMessage,
                selectedVersion: _versionController.text.trim(),
                onSelected: (version) {
                  _versionController.text = version;
                  _versionController.selection = TextSelection.collapsed(
                    offset: version.length,
                  );
                  _versionFocusNode.unfocus();
                  setState(() {});
                },
              ),
            ],
            const SizedBox(height: 18),
            Text(
              '安装后会直接写成全局默认版本。',
              style: TextStyle(
                color: colors.textMuted,
                fontSize: 13,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 22),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('取消'),
                ),
                const SizedBox(width: 12),
                FilledButton.icon(
                  onPressed: _submit,
                  icon: const Icon(Icons.arrow_forward_rounded),
                  label: const Text('继续预览'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _submit() {
    final tool = _toolController.text.trim();
    final version = _versionController.text.trim();
    if (tool.isEmpty || version.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请先填写工具名和版本号。')));
      return;
    }

    Navigator.of(
      context,
    ).pop(_InstallToolRequest(tool: tool, version: version));
  }
}

class _VersionSuggestionList extends StatelessWidget {
  const _VersionSuggestionList({
    required this.loading,
    required this.versions,
    required this.message,
    required this.selectedVersion,
    required this.onSelected,
  });

  final bool loading;
  final List<String> versions;
  final String? message;
  final String selectedVersion;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colorsOf(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: colors.panelRaised.withValues(alpha: 0.82),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.border),
      ),
      child: loading
          ? const Padding(
              padding: EdgeInsets.all(8),
              child: LinearProgressIndicator(minHeight: 3),
            )
          : versions.isNotEmpty
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(6, 4, 6, 8),
                  child: Text(
                    '远端可选版本',
                    style: TextStyle(
                      color: colors.textMuted,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                for (var index = 0; index < versions.length; index++)
                  _VersionSuggestionRow(
                    version: versions[index],
                    selected: versions[index] == selectedVersion,
                    isFirst: index == 0,
                    onTap: () => onSelected(versions[index]),
                  ),
              ],
            )
          : Padding(
              padding: const EdgeInsets.all(8),
              child: Text(
                message ?? '没有拉到可选版本，仍可手动输入。',
                style: TextStyle(color: colors.textMuted, height: 1.45),
              ),
            ),
    );
  }
}

class _VersionSuggestionRow extends StatelessWidget {
  const _VersionSuggestionRow({
    required this.version,
    required this.selected,
    required this.isFirst,
    required this.onTap,
  });

  final String version;
  final bool selected;
  final bool isFirst;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colorsOf(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: selected
            ? colors.info.withValues(alpha: 0.12)
            : colors.panel.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTapDown: (_) => onTap(),
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          hoverColor: colors.hover,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    version,
                    style: const TextStyle(
                      fontFamily: 'FiraCode',
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (isFirst)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: colors.accent.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      '最新',
                      style: TextStyle(
                        color: colors.accent,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                if (selected) ...[
                  const SizedBox(width: 8),
                  Icon(Icons.check_rounded, size: 18, color: colors.info),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ToolList extends StatelessWidget {
  const _ToolList({
    required this.tools,
    required this.selectedToolId,
    required this.hydratedTools,
    required this.loadingToolIds,
    required this.requestedToolIds,
    required this.onSelected,
    required this.onOpenPreview,
  });

  final List<ToolRecord> tools;
  final String? selectedToolId;
  final Map<String, ToolRecord> hydratedTools;
  final Set<String> loadingToolIds;
  final Set<String> requestedToolIds;
  final ValueChanged<String> onSelected;
  final Future<void> Function(
    BuildContext context,
    ActionPreviewDialogData data,
  )
  onOpenPreview;

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colorsOf(context);

    return AppPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('已安装', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(
            '按工具查看当前版本，并按需加载可升级信息。',
            style: TextStyle(color: colors.textMuted, height: 1.5),
          ),
          const SizedBox(height: 18),
          for (final tool in tools)
            KeyedSubtree(
              key: ValueKey('tool-accordion-${tool.id}'),
              child: Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _ToolAccordionItem(
                  tool: tool,
                  hydratedTool: hydratedTools[tool.id],
                  expanded: tool.id == selectedToolId,
                  detailLoading: loadingToolIds.contains(tool.id),
                  detailRequested: requestedToolIds.contains(tool.id),
                  onTap: () => onSelected(tool.id),
                  onOpenPreview: onOpenPreview,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ToolAccordionItem extends StatelessWidget {
  const _ToolAccordionItem({
    required this.tool,
    required this.hydratedTool,
    required this.expanded,
    required this.detailLoading,
    required this.detailRequested,
    required this.onTap,
    required this.onOpenPreview,
  });

  final ToolRecord tool;
  final ToolRecord? hydratedTool;
  final bool expanded;
  final bool detailLoading;
  final bool detailRequested;
  final VoidCallback onTap;
  final Future<void> Function(
    BuildContext context,
    ActionPreviewDialogData data,
  )
  onOpenPreview;

  @override
  Widget build(BuildContext context) {
    final detail = _resolveDetail();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ToolListItem(
          tool: tool,
          selected: expanded,
          detailLoading: detailLoading,
          detailRequested: detailRequested,
          onTap: onTap,
        ),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 220),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          transitionBuilder: (child, animation) {
            return SizeTransition(
              sizeFactor: animation,
              axisAlignment: -1,
              child: FadeTransition(opacity: animation, child: child),
            );
          },
          child: detail,
        ),
      ],
    );
  }

  Widget _resolveDetail() {
    if (!expanded) {
      return const SizedBox.shrink(key: ValueKey('collapsed-detail'));
    }

    if (detailLoading && hydratedTool == null) {
      return _AccordionDetailShell(
        key: ValueKey('loading-detail-${tool.id}'),
        child: _ToolWorkspaceLoading(
          title: '正在读取 ${tool.name} 的详情',
          message: '远端版本和详细信息返回后，会在这里展开。',
        ),
      );
    }

    final detailTool = hydratedTool;
    if (detailTool == null) {
      return const SizedBox.shrink(key: ValueKey('empty-detail'));
    }

    return _AccordionDetailShell(
      key: ValueKey('ready-detail-${tool.id}-${detailTool.activeVersion}'),
      child: _ToolWorkspace(tool: detailTool, onOpenPreview: onOpenPreview),
    );
  }
}

class _AccordionDetailShell extends StatelessWidget {
  const _AccordionDetailShell({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 20),
      child: child,
    );
  }
}

class _ToolListItem extends StatelessWidget {
  const _ToolListItem({
    required this.tool,
    required this.selected,
    required this.detailLoading,
    required this.detailRequested,
    required this.onTap,
  });

  final ToolRecord tool;
  final bool selected;
  final bool detailLoading;
  final bool detailRequested;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colorsOf(context);
    final hasActiveVersion = tool.installedVersions.any(
      (version) => version.isActive,
    );
    final latestValue = switch ((
      detailLoading,
      detailRequested,
      tool.remoteState,
    )) {
      (true, _, _) => '加载中...',
      (false, false, _) => '点击查看',
      (false, true, ToolRemoteState.unavailable) => '未获取',
      _ => tool.latestStableVersion,
    };

    return Material(
      color: selected
          ? colors.info.withValues(alpha: 0.10)
          : colors.panelRaised.withValues(alpha: 0.84),
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(22),
        hoverColor: colors.hover,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      tool.name,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(tool.category, style: TextStyle(color: colors.textMuted)),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _MiniFact(
                    label: hasActiveVersion ? '当前' : '已装',
                    value: tool.activeVersion,
                  ),
                  _MiniFact(label: '最新', value: latestValue),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ToolWorkspace extends StatelessWidget {
  const _ToolWorkspace({required this.tool, required this.onOpenPreview});

  final ToolRecord tool;
  final Future<void> Function(
    BuildContext context,
    ActionPreviewDialogData data,
  )
  onOpenPreview;

  @override
  Widget build(BuildContext context) {
    return _ToolHeroPanel(tool: tool, onOpenPreview: onOpenPreview);
  }
}

class _ToolHeroPanel extends StatelessWidget {
  const _ToolHeroPanel({required this.tool, required this.onOpenPreview});

  final ToolRecord tool;
  final Future<void> Function(
    BuildContext context,
    ActionPreviewDialogData data,
  )
  onOpenPreview;

  @override
  Widget build(BuildContext context) {
    final recommendedVersion = _recommendedVersion(tool);
    final latestLabel = switch (tool.remoteState) {
      ToolRemoteState.pending => '读取中',
      ToolRemoteState.unavailable => '未获取',
      ToolRemoteState.ready => tool.latestStableVersion,
    };

    return AppPanel(
      showShadow: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final stacked = constraints.maxWidth < 760;
              final currentMetric = _ToolMetricCard(
                label: '当前版本',
                value: tool.activeVersion,
                level: tool.level,
              );
              final latestMetric = _ToolMetricCard(
                label: '最新稳定版',
                value: latestLabel,
                level: switch (tool.remoteState) {
                  ToolRemoteState.unavailable => HealthLevel.warning,
                  _ when tool.hasUpdate => HealthLevel.healthy,
                  _ => HealthLevel.info,
                },
              );

              if (stacked) {
                return Column(
                  children: [
                    currentMetric,
                    const SizedBox(height: 14),
                    latestMetric,
                  ],
                );
              }

              return Row(
                children: [
                  Expanded(child: currentMetric),
                  const SizedBox(width: 16),
                  Expanded(child: latestMetric),
                ],
              );
            },
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              if (tool.hasUpdate && recommendedVersion != null)
                FilledButton.icon(
                  onPressed: () => onOpenPreview(
                    context,
                    ActionPreviewDialogData(
                      title: '升级 ${tool.name} 到 ${recommendedVersion.version}',
                      summary: '会先安装新版本，再切换到这个版本。',
                      command: recommendedVersion.commandPreview,
                      level: HealthLevel.healthy,
                      affectedFiles: _affectedFilesForToolCommand(
                        recommendedVersion.commandPreview,
                      ),
                      impactScope: const ['会新增本地已安装版本。', '默认使用的版本会切换到新版本。'],
                      riskNotes: const ['升级时需要访问网络，过程可能会持续一段时间。'],
                      confirmLabel: '确认升级',
                    ),
                  ),
                  icon: const Icon(Icons.upgrade_rounded),
                  label: Text('升级到 ${recommendedVersion.version}'),
                ),
              OutlinedButton.icon(
                onPressed: () => onOpenPreview(
                  context,
                  ActionPreviewDialogData(
                    title: '卸载 ${tool.name}',
                    summary: '会先从全局配置里移除这个工具，再删除本机上这个工具的所有已安装版本。',
                    command:
                        'mise use --global --remove ${tool.id}\n'
                        'mise uninstall --all ${tool.id}',
                    level: HealthLevel.warning,
                    affectedFiles: _affectedFilesForToolCommand(
                      'mise use --global --remove ${tool.id}\n'
                      'mise uninstall --all ${tool.id}',
                    ),
                    impactScope: const [
                      '全局默认配置里不再声明这个工具。',
                      '这个工具的所有本地已安装版本都会被移除。',
                      '如果其他配置仍然依赖这个工具，相关命令仍可能报缺失。',
                    ],
                    riskNotes: const ['卸载前请确认没有其他配置还在依赖这个工具。'],
                    confirmLabel: '确认卸载',
                  ),
                ),
                icon: const Icon(Icons.delete_outline_rounded),
                label: const Text('卸载'),
              ),
            ],
          ),
          if (tool.notices.isNotEmpty) ...[
            const SizedBox(height: 18),
            Column(
              children: [
                for (final notice in tool.notices) ...[
                  InlineNoticeBar(
                    notice: notice,
                    onShowCommand: notice.commandPreview == null
                        ? null
                        : () => onOpenPreview(
                            context,
                            ActionPreviewDialogData(
                              title: notice.title,
                              summary: notice.message,
                              command: notice.commandPreview!,
                              level: notice.level,
                            ),
                          ),
                  ),
                  if (notice != tool.notices.last) const SizedBox(height: 12),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }

  ToolVersionRecord? _recommendedVersion(ToolRecord tool) {
    for (final version in tool.remoteVersions) {
      if (version.isRecommended) {
        return version;
      }
    }
    return null;
  }
}

class _ToolMetricCard extends StatelessWidget {
  const _ToolMetricCard({
    required this.label,
    required this.value,
    required this.level,
  });

  final String label;
  final String value;
  final HealthLevel level;

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colorsOf(context);
    final accent = switch (level) {
      HealthLevel.healthy => colors.accent,
      HealthLevel.info => colors.info,
      HealthLevel.warning => colors.warning,
      HealthLevel.critical => colors.danger,
    };

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: colors.panelRaised.withValues(alpha: 0.84),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: colors.textMuted,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          SelectableText(
            value,
            style: TextStyle(
              color: accent,
              fontFamily: 'FiraCode',
              fontSize: 28,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _VersionInventoryPanel extends StatelessWidget {
  const _VersionInventoryPanel({
    required this.title,
    required this.subtitle,
    required this.versions,
    this.emptyState,
    required this.onOpenPreview,
  });

  final String title;
  final String subtitle;
  final List<ToolVersionRecord> versions;
  final _PanelEmptyStateData? emptyState;
  final Future<void> Function(
    BuildContext context,
    ActionPreviewDialogData data,
  )
  onOpenPreview;

  @override
  Widget build(BuildContext context) {
    return AppPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _ToolSectionHeader(
            title: title,
            subtitle: subtitle,
            badgeLabel: versions.isEmpty ? '暂无内容' : '${versions.length} 条',
            badgeLevel: versions.isEmpty
                ? HealthLevel.info
                : HealthLevel.healthy,
          ),
          const SizedBox(height: 18),
          if (versions.isEmpty)
            _PanelEmptyStateCard(
              data:
                  emptyState ??
                  const _PanelEmptyStateData(
                    icon: Icons.info_outline_rounded,
                    title: '当前没有可展示的数据',
                    message: '稍后可以重新同步，或先查看命令结果。',
                    level: HealthLevel.info,
                  ),
              onOpenPreview: onOpenPreview,
            )
          else
            for (final version in versions)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _VersionCard(
                  version: version,
                  onOpenPreview: onOpenPreview,
                ),
              ),
        ],
      ),
    );
  }
}

class _VersionCard extends StatelessWidget {
  const _VersionCard({required this.version, required this.onOpenPreview});

  final ToolVersionRecord version;
  final Future<void> Function(
    BuildContext context,
    ActionPreviewDialogData data,
  )
  onOpenPreview;

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colorsOf(context);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.panelRaised.withValues(alpha: 0.82),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 10,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                version.version,
                style: const TextStyle(
                  fontFamily: 'FiraCode',
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              StatusBadge(label: version.channel, level: version.level),
              if (version.isActive)
                const StatusBadge(label: '当前生效', level: HealthLevel.healthy),
              if (version.isRecommended)
                const StatusBadge(label: '推荐版本', level: HealthLevel.info),
              if (version.isAlias)
                const StatusBadge(label: '别名', level: HealthLevel.info),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            version.note,
            style: TextStyle(color: colors.textMuted, height: 1.45),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              if (version.isActive)
                TextButton.icon(
                  onPressed: null,
                  icon: const Icon(Icons.check_circle_rounded),
                  label: const Text('当前版本'),
                )
              else if (version.isInstalled)
                OutlinedButton.icon(
                  onPressed: () => onOpenPreview(
                    context,
                    ActionPreviewDialogData(
                      title: '切换到 ${version.version}',
                      summary: '这个版本已经在本机安装，确认后会开始版本切换。',
                      command: version.commandPreview,
                      level: version.level,
                      affectedFiles: _affectedFilesForToolCommand(
                        version.commandPreview,
                      ),
                      impactScope: const [
                        '当前工具的默认激活版本会变化。',
                        '相关项目的解析结果可能随之更新。',
                      ],
                      riskNotes: const ['切换前请先确认是否有项目级版本覆盖。'],
                      confirmLabel: '确认切换',
                    ),
                  ),
                  icon: const Icon(Icons.swap_horiz_rounded),
                  label: const Text('切换'),
                )
              else
                FilledButton.icon(
                  onPressed: () => onOpenPreview(
                    context,
                    ActionPreviewDialogData(
                      title: '安装 ${version.version}',
                      summary: '这个版本还没安装到本机，确认后会开始安装。',
                      command: version.commandPreview,
                      level: version.level,
                      affectedFiles: _affectedFilesForToolCommand(
                        version.commandPreview,
                      ),
                      impactScope: const [
                        '会新增本地已安装版本记录。',
                        '如果接着激活，当前版本来源也可能改变。',
                      ],
                      riskNotes: const ['安装时会访问网络，并更新本地缓存。'],
                      confirmLabel: version.isRecommended ? '确认升级' : '确认安装',
                    ),
                  ),
                  icon: Icon(
                    version.isRecommended
                        ? Icons.upgrade_rounded
                        : Icons.download_rounded,
                  ),
                  label: Text(version.isRecommended ? '升级' : '安装'),
                ),
              OutlinedButton.icon(
                onPressed: () => onOpenPreview(
                  context,
                  ActionPreviewDialogData(
                    title: '命令预览',
                    summary: '这条命令是当前界面为这个版本动作准备的实际 CLI。',
                    command: version.commandPreview,
                    level: version.level,
                  ),
                ),
                icon: const Icon(Icons.terminal_rounded),
                label: const Text('查看命令'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ProjectImpactPanel extends StatelessWidget {
  const _ProjectImpactPanel({required this.projects});

  final List<ToolProjectImpact> projects;

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colorsOf(context);

    return AppPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _ToolSectionHeader(
            title: '项目影响',
            subtitle: '这里展示当前版本会在哪些配置或项目里生效，方便先判断影响范围。',
            badgeLabel: projects.isEmpty ? '范围集中' : '${projects.length} 条',
            badgeLevel: projects.isEmpty
                ? HealthLevel.healthy
                : HealthLevel.warning,
          ),
          const SizedBox(height: 18),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: colors.backgroundSoft.withValues(alpha: 0.72),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: colors.border),
            ),
            child: Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _CompactFactChip(label: '受影响条目', value: '${projects.length}'),
                _CompactFactChip(
                  label: '当前状态',
                  value: projects.length <= 1 ? '范围明确' : '需重点确认',
                  level: projects.length <= 1
                      ? HealthLevel.healthy
                      : HealthLevel.warning,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          if (projects.isEmpty)
            const _PanelEmptyStateCard(
              data: _PanelEmptyStateData(
                icon: Icons.layers_clear_outlined,
                title: '当前没有额外影响范围',
                message: '这次版本不会扩散到其他项目或配置来源，当前作用范围比较集中。',
                level: HealthLevel.healthy,
              ),
            )
          else
            for (final project in projects)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _ProjectImpactCard(project: project),
              ),
        ],
      ),
    );
  }
}

class _ActionPipelinePanel extends StatelessWidget {
  const _ActionPipelinePanel({
    required this.actions,
    required this.onOpenPreview,
  });

  final List<ToolCommandAction> actions;
  final Future<void> Function(
    BuildContext context,
    ActionPreviewDialogData data,
  )
  onOpenPreview;

  @override
  Widget build(BuildContext context) {
    return AppPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _ToolSectionHeader(
            title: '建议动作',
            subtitle: '根据当前版本来源整理出更稳妥的下一步，执行前仍然会先展示实际命令。',
            badgeLabel: actions.isEmpty ? '无需处理' : '${actions.length} 条',
            badgeLevel: actions.isEmpty
                ? HealthLevel.healthy
                : HealthLevel.info,
          ),
          const SizedBox(height: 18),
          if (actions.isEmpty)
            const _PanelEmptyStateCard(
              data: _PanelEmptyStateData(
                icon: Icons.playlist_add_check_circle_outlined,
                title: '当前不需要额外操作',
                message: '当前版本状态已经比较稳定，如果需要进一步确认，可以直接查看命令预览。',
                level: HealthLevel.healthy,
              ),
            )
          else
            for (final action in actions)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _ActionRecommendationCard(
                  action: action,
                  onOpenPreview: onOpenPreview,
                ),
              ),
        ],
      ),
    );
  }
}

class _ProjectImpactCard extends StatelessWidget {
  const _ProjectImpactCard({required this.project});

  final ToolProjectImpact project;

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colorsOf(context);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.panelRaised.withValues(alpha: 0.82),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 10,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                project.projectName,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              StatusBadge(
                label: '请求 ${project.requestedVersion}',
                level: HealthLevel.info,
              ),
              StatusBadge(
                label: '生效 ${project.resolvedVersion}',
                level: project.level,
              ),
            ],
          ),
          const SizedBox(height: 10),
          SelectableText(
            project.path,
            style: TextStyle(
              color: colors.textMuted,
              fontFamily: 'FiraCode',
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            project.reason,
            style: TextStyle(color: colors.textMuted, height: 1.45),
          ),
        ],
      ),
    );
  }
}

class _ActionRecommendationCard extends StatelessWidget {
  const _ActionRecommendationCard({
    required this.action,
    required this.onOpenPreview,
  });

  final ToolCommandAction action;
  final Future<void> Function(
    BuildContext context,
    ActionPreviewDialogData data,
  )
  onOpenPreview;

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colorsOf(context);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.panelRaised.withValues(alpha: 0.82),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colors.border),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final stacked = constraints.maxWidth < 430;

          final content = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 10,
                runSpacing: 10,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(
                    action.label,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  StatusBadge(label: action.level.label, level: action.level),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                action.summary,
                style: TextStyle(color: colors.textMuted, height: 1.45),
              ),
            ],
          );

          final button = FilledButton.icon(
            onPressed: () => onOpenPreview(
              context,
              ActionPreviewDialogData(
                title: action.label,
                summary: action.summary,
                command: action.command,
                level: action.level,
                affectedFiles: _affectedFilesForToolCommand(action.command),
                impactScope: const [
                  '当前会严格按预览中的 CLI 顺序执行。',
                  '执行后会自动刷新工具页与总览页数据。',
                ],
                riskNotes: _toolCommandIsMutating(action.command)
                    ? const ['如果命令会写配置或切换版本，请先确认当前工作目录是否正确。']
                    : const [],
                confirmLabel: _toolCommandIsMutating(action.command)
                    ? '确认执行'
                    : '运行查询',
              ),
            ),
            icon: Icon(
              _toolCommandIsMutating(action.command)
                  ? Icons.play_arrow_rounded
                  : Icons.terminal_rounded,
            ),
            label: Text(
              _toolCommandIsMutating(action.command) ? '执行动作' : '查看命令',
            ),
          );

          if (stacked) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [content, const SizedBox(height: 14), button],
            );
          }

          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: content),
              const SizedBox(width: 16),
              button,
            ],
          );
        },
      ),
    );
  }
}

class _ToolSectionHeader extends StatelessWidget {
  const _ToolSectionHeader({
    required this.title,
    required this.subtitle,
    required this.badgeLabel,
    required this.badgeLevel,
  });

  final String title;
  final String subtitle;
  final String badgeLabel;
  final HealthLevel badgeLevel;

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colorsOf(context);

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
                  Text(title, style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 8),
                  Text(
                    subtitle,
                    style: TextStyle(color: colors.textMuted, height: 1.5),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            StatusBadge(label: badgeLabel, level: badgeLevel),
          ],
        ),
        const SizedBox(height: 14),
        Container(
          height: 1,
          width: double.infinity,
          color: colors.border.withValues(alpha: 0.8),
        ),
      ],
    );
  }
}

class _PanelEmptyStateData {
  const _PanelEmptyStateData({
    required this.icon,
    required this.title,
    required this.message,
    required this.level,
    this.actionLabel,
    this.previewData,
  });

  final IconData icon;
  final String title;
  final String message;
  final HealthLevel level;
  final String? actionLabel;
  final ActionPreviewDialogData? previewData;
}

class _PanelEmptyStateCard extends StatelessWidget {
  const _PanelEmptyStateCard({required this.data, this.onOpenPreview});

  final _PanelEmptyStateData data;
  final Future<void> Function(
    BuildContext context,
    ActionPreviewDialogData data,
  )?
  onOpenPreview;

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colorsOf(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: colors.panelRaised.withValues(alpha: 0.78),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: switch (data.level) {
                    HealthLevel.healthy => colors.accent.withValues(
                      alpha: 0.14,
                    ),
                    HealthLevel.info => colors.info.withValues(alpha: 0.14),
                    HealthLevel.warning => colors.warning.withValues(
                      alpha: 0.14,
                    ),
                    HealthLevel.critical => colors.danger.withValues(
                      alpha: 0.14,
                    ),
                  },
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  data.icon,
                  color: switch (data.level) {
                    HealthLevel.healthy => colors.accent,
                    HealthLevel.info => colors.info,
                    HealthLevel.warning => colors.warning,
                    HealthLevel.critical => colors.danger,
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      data.title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      data.message,
                      style: TextStyle(color: colors.textMuted, height: 1.45),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (data.actionLabel != null &&
              data.previewData != null &&
              onOpenPreview != null) ...[
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: () => onOpenPreview!(context, data.previewData!),
              icon: const Icon(Icons.terminal_rounded),
              label: Text(data.actionLabel!),
            ),
          ],
        ],
      ),
    );
  }
}

class _CompactFactChip extends StatelessWidget {
  const _CompactFactChip({
    required this.label,
    required this.value,
    this.level = HealthLevel.info,
  });

  final String label;
  final String value;
  final HealthLevel level;

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colorsOf(context);
    final color = switch (level) {
      HealthLevel.healthy => colors.accent,
      HealthLevel.info => colors.info,
      HealthLevel.warning => colors.warning,
      HealthLevel.critical => colors.danger,
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.24)),
      ),
      child: Text(
        '$label: $value',
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _ToolOverviewStrip extends StatelessWidget {
  const _ToolOverviewStrip({required this.tool});

  final ToolRecord tool;

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colorsOf(context);
    final items = <({String label, String value})>[
      (label: '当前版本', value: tool.activeVersion),
      (label: '请求版本', value: tool.requestedVersion),
      (
        label: '推荐稳定版',
        value: tool.remoteState == ToolRemoteState.pending
            ? '正在同步'
            : tool.latestStableVersion,
      ),
      (label: '关联项目', value: '${tool.projectImpactCount}'),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 860;

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: colors.backgroundSoft.withValues(alpha: 0.76),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: colors.border),
          ),
          child: compact
              ? Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    for (final item in items)
                      SizedBox(
                        width: constraints.maxWidth > 540
                            ? (constraints.maxWidth - 22) / 2
                            : double.infinity,
                        child: _OverviewMetricItem(
                          label: item.label,
                          value: item.value,
                        ),
                      ),
                  ],
                )
              : Row(
                  children: [
                    for (var index = 0; index < items.length; index++) ...[
                      Expanded(
                        child: _OverviewMetricItem(
                          label: items[index].label,
                          value: items[index].value,
                          dense: true,
                        ),
                      ),
                      if (index != items.length - 1)
                        Container(
                          width: 1,
                          height: 46,
                          margin: const EdgeInsets.symmetric(horizontal: 8),
                          color: colors.border,
                        ),
                    ],
                  ],
                ),
        );
      },
    );
  }
}

class _OverviewMetricItem extends StatelessWidget {
  const _OverviewMetricItem({
    required this.label,
    required this.value,
    this.dense = false,
  });

  final String label;
  final String value;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colorsOf(context);

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: dense ? 10 : 14,
        vertical: dense ? 10 : 14,
      ),
      decoration: BoxDecoration(
        color: dense
            ? Colors.transparent
            : colors.panelRaised.withValues(alpha: 0.68),
        borderRadius: BorderRadius.circular(18),
        border: dense ? null : Border.all(color: colors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: colors.textMuted,
              fontSize: dense ? 12 : 13,
            ),
          ),
          SizedBox(height: dense ? 6 : 8),
          SelectableText(
            value,
            style: TextStyle(
              fontFamily: 'FiraCode',
              fontSize: dense ? 13 : 15,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniFact extends StatelessWidget {
  const _MiniFact({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colors = AppTheme.colorsOf(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: colors.backgroundSoft,
        borderRadius: BorderRadius.circular(999),
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

bool _toolCommandIsMutating(String command) {
  final normalized = command.toLowerCase();
  return normalized.contains('mise install ') ||
      normalized.contains('mise use ') ||
      normalized.contains('mise uninstall ') ||
      normalized.contains('mise unuse ') ||
      normalized.contains('mise settings set ');
}

List<String> _affectedFilesForToolCommand(String command) {
  final normalized = command.toLowerCase();
  final files = <String>[];
  final home = Platform.environment['HOME'];

  if (normalized.contains('mise use --global ')) {
    if (home != null && home.isNotEmpty) {
      files.add('$home/.config/mise/config.toml');
    } else {
      files.add('~/.config/mise/config.toml');
    }
  } else if (normalized.contains('mise use ')) {
    files.add('${Directory.current.path}/mise.toml');
  }

  if (normalized.contains('mise install ')) {
    files.add('mise 安装缓存 / 已安装版本');
  }

  if (normalized.contains('mise uninstall ')) {
    files.add('mise 安装缓存 / 已安装版本');
  }

  return files;
}

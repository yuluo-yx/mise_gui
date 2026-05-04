import 'dart:ffi';
import 'dart:io';

import 'package:mise_gui/models/app_models.dart';
import 'package:mise_gui/repositories/projects_repository.dart';
import 'package:mise_gui/services/history_service.dart';
import 'package:mise_gui/services/mise_cli_service.dart';
import 'package:mise_gui/services/mise_process_service.dart';

class DashboardRepository {
  const DashboardRepository({
    required this.miseCliService,
    required this.projectsRepository,
    required this.processService,
    required this.historyService,
  });

  final MiseCliService miseCliService;
  final ProjectsRepository projectsRepository;
  final MiseProcessService processService;
  final HistoryService historyService;

  Future<DashboardSnapshot> loadDashboard() async {
    final results = await Future.wait<dynamic>([
      miseCliService.fetchDashboardToolSummary(),
      projectsRepository.loadProjects(),
      _loadOperatingSystemInfo(),
      _loadMiseVersionInfo(),
      historyService.fetchHistory(),
    ]);

    final toolSummary = results[0] as DashboardToolSummary;
    final projects = results[1] as List<ProjectRecord>;
    final operatingSystemInfo = results[2] as _OperatingSystemInfo;
    final miseVersionInfo = results[3] as _MiseVersionInfo;
    final recentHistory = results[4] as List<HistoryEntry>;

    final declaredToolCount = projects.fold<int>(
      0,
      (sum, project) => sum + project.declaredToolCount,
    );
    final overrideProjectCount = projects
        .where((project) => project.hasOverrideRisk)
        .length;
    final overrideCount = projects.fold<int>(
      0,
      (sum, project) => sum + project.overrideCount,
    );

    return DashboardSnapshot(
      title: '环境总览',
      subtitle: '',
      metrics: [
        SummaryMetric(
          label: '当前系统',
          value: operatingSystemInfo.label,
          caption: operatingSystemInfo.caption,
          level: HealthLevel.info,
        ),
        SummaryMetric(
          label: '已装工具',
          value: '${toolSummary.installedToolCount} 个',
          caption: '当前已纳入 mise 管理的本地工具。',
          level: toolSummary.installedToolCount > 0
              ? HealthLevel.healthy
              : HealthLevel.info,
        ),
        SummaryMetric(
          label: '项目覆盖',
          value: projects.isEmpty
              ? '未配置'
              : overrideCount > 0
              ? '$overrideProjectCount 个项目'
              : '无覆盖',
          caption: projects.isEmpty
              ? '还没有配置要扫描的项目目录。'
              : overrideCount > 0
              ? '已扫描 ${projects.length} 个项目，发现 $overrideCount 处覆盖，分布在 $overrideProjectCount 个项目里。'
              : declaredToolCount > 0
              ? '已扫描 ${projects.length} 个项目，没有发现覆盖全局版本的项目。'
              : '已扫描 ${projects.length} 个项目，暂未检测到项目级版本声明。',
          level: overrideCount > 0
              ? HealthLevel.warning
              : projects.isEmpty
              ? HealthLevel.info
              : HealthLevel.healthy,
        ),
        SummaryMetric(
          label: 'Mise 版本',
          value: miseVersionInfo.version,
          caption: miseVersionInfo.detail,
          level: miseVersionInfo.level,
        ),
      ],
      signals: const [],
      toolSummary: toolSummary,
      recentHistory: recentHistory.take(3).toList(growable: false),
      riskHighlights: const [],
    );
  }

  String _operatingSystemLabel() {
    if (Platform.isMacOS) {
      return 'macOS';
    }
    if (Platform.isWindows) {
      return 'Windows';
    }
    if (Platform.isLinux) {
      return 'Linux';
    }
    return Platform.operatingSystem;
  }

  Future<String?> _operatingSystemVersion() async {
    try {
      if (Platform.isMacOS) {
        final result = await Process.run('sw_vers', const [
          '-productVersion',
        ], runInShell: false);
        final value = (result.stdout ?? '').toString().trim();
        if (result.exitCode == 0 && value.isNotEmpty) {
          return value;
        }
      }

      if (Platform.isLinux) {
        final result = await Process.run('uname', const [
          '-r',
        ], runInShell: false);
        final value = (result.stdout ?? '').toString().trim();
        if (result.exitCode == 0 && value.isNotEmpty) {
          return value;
        }
      }

      if (Platform.isWindows) {
        final version = Platform.operatingSystemVersion.trim();
        if (version.isNotEmpty) {
          return version;
        }
      }
    } catch (_) {
      return null;
    }

    return null;
  }

  Future<String?> _operatingSystemBuild() async {
    try {
      if (Platform.isMacOS) {
        final result = await Process.run('sw_vers', const [
          '-buildVersion',
        ], runInShell: false);
        final value = (result.stdout ?? '').toString().trim();
        if (result.exitCode == 0 && value.isNotEmpty) {
          return value;
        }
      }
    } catch (_) {
      return null;
    }

    return null;
  }

  String _operatingSystemCaption() {
    final arch = switch (Abi.current()) {
      Abi.macosArm64 || Abi.linuxArm64 || Abi.windowsArm64 => 'arm64',
      Abi.macosX64 || Abi.linuxX64 || Abi.windowsX64 => 'x64',
      _ => Abi.current().toString().split('.').last,
    };
    return '$arch 架构';
  }

  Future<_OperatingSystemInfo> _loadOperatingSystemInfo() async {
    final systemName = _operatingSystemLabel();
    final version = await _operatingSystemVersion();
    final build = await _operatingSystemBuild();
    final label = version == null || version.isEmpty
        ? systemName
        : '$systemName $version';
    final captionParts = <String>[];

    if (build != null && build.isNotEmpty) {
      captionParts.add('Build $build');
    }
    captionParts.add(_operatingSystemCaption());

    final cpuModel = await _loadCpuModel();
    if (cpuModel != null && cpuModel.isNotEmpty) {
      captionParts.add(cpuModel);
    }

    return _OperatingSystemInfo(label: label, caption: captionParts.join('\n'));
  }

  Future<String?> _loadCpuModel() async {
    try {
      if (Platform.isMacOS) {
        final result = await Process.run('sysctl', const [
          '-n',
          'machdep.cpu.brand_string',
        ], runInShell: false);
        final value = (result.stdout ?? '').toString().trim();
        if (result.exitCode == 0 && value.isNotEmpty) {
          return value;
        }

        final armResult = await Process.run(
          'sysctl',
          const ['-n', 'machdep.cpu.brand_string'],
          environment: const {'PATH': '/usr/sbin:/usr/bin:/bin:/sbin'},
          runInShell: false,
        );
        final armValue = (armResult.stdout ?? '').toString().trim();
        if (armResult.exitCode == 0 && armValue.isNotEmpty) {
          return armValue;
        }
      }

      if (Platform.isLinux) {
        final cpuInfo = await File('/proc/cpuinfo').readAsString();
        for (final line in cpuInfo.split('\n')) {
          if (!line.toLowerCase().startsWith('model name')) {
            continue;
          }
          final separatorIndex = line.indexOf(':');
          if (separatorIndex == -1) {
            continue;
          }
          final value = line.substring(separatorIndex + 1).trim();
          if (value.isNotEmpty) {
            return value;
          }
        }
      }
    } catch (_) {
      return null;
    }

    return null;
  }

  Future<_MiseVersionInfo> _loadMiseVersionInfo() async {
    try {
      final result = await processService.run(
        const MiseCommandRequest(
          arguments: ['--version'],
          timeout: Duration(seconds: 5),
        ),
      );
      final firstLine = result.stdout
          .split('\n')
          .map((line) => line.trim())
          .firstWhere((line) => line.isNotEmpty, orElse: () => '');
      final match = RegExp(r'(\d+(?:\.\d+){1,3})').firstMatch(firstLine);
      final version = match?.group(1) ?? firstLine;
      final detail = firstLine.replaceFirst(version, '').trim();

      return _MiseVersionInfo(
        version: version.isEmpty ? '未知' : version,
        detail: detail.isEmpty ? 'mise CLI 已可用。' : detail,
        level: HealthLevel.info,
      );
    } catch (error) {
      if (isMiseCommandUnavailable(error)) {
        return const _MiseVersionInfo(
          version: '未检测到',
          detail: '当前设备还没有可执行的 mise CLI。',
          level: HealthLevel.critical,
        );
      }
      return _MiseVersionInfo(
        version: '读取失败',
        detail: '无法读取 mise 版本: $error',
        level: HealthLevel.warning,
      );
    }
  }
}

class _MiseVersionInfo {
  const _MiseVersionInfo({
    required this.version,
    required this.detail,
    required this.level,
  });

  final String version;
  final String detail;
  final HealthLevel level;
}

class _OperatingSystemInfo {
  const _OperatingSystemInfo({required this.label, required this.caption});

  final String label;
  final String caption;
}

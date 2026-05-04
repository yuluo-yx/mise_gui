import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:mise_gui/models/app_models.dart';
import 'package:mise_gui/services/mise_process_service.dart';
import 'package:mise_gui/services/mise_query_service.dart';

abstract class ProjectScanService {
  Future<List<ProjectRecord>> fetchProjects(
    List<ScanDirectoryRecord> directories,
  );
}

class LiveProjectScanService implements ProjectScanService {
  const LiveProjectScanService({
    required MiseQueryService queryService,
    this.maxDepth = 3,
    this.maxDirectoriesPerRoot = 240,
    this.maxProjectsPerRoot = 80,
  }) : _queryService = queryService;

  final MiseQueryService _queryService;
  final int maxDepth;
  final int maxDirectoriesPerRoot;
  final int maxProjectsPerRoot;

  static const List<String> _workspaceConfigNames = <String>[
    'mise.toml',
    '.mise.local.toml',
    'mise.local.toml',
  ];

  static const Set<String> _ignoredDirectories = <String>{
    '.git',
    '.dart_tool',
    '.idea',
    '.vscode',
    'build',
    'dist',
    'node_modules',
  };

  @override
  Future<List<ProjectRecord>> fetchProjects(
    List<ScanDirectoryRecord> directories,
  ) async {
    try {
      final activeDirectories = directories
          .where((directory) => directory.enabled)
          .toList(growable: false);
      final collapsedDirectories = _collapseOverlappingRoots(activeDirectories);
      if (collapsedDirectories.isEmpty) {
        return const <ProjectRecord>[];
      }

      final globalConfigPath = _globalConfigPath();
      final globalConfig = await _readFileIfExists(globalConfigPath) ?? '';
      final projectsByPath = <String, ProjectRecord>{};

      for (final directory in collapsedDirectories) {
        final configPaths = await _discoverWorkspaceConfigPaths(directory.path);
        for (final configPath in configPaths) {
          ProjectRecord? project;
          try {
            project = await _buildProjectRecord(
              configPath: configPath,
              scanRootPath: directory.path,
              globalConfig: globalConfig,
            );
          } catch (_) {
            project = null;
          }
          if (project == null) {
            continue;
          }
          projectsByPath.putIfAbsent(project.path, () => project!);
        }
      }

      final projects = projectsByPath.values.toList()
        ..sort((a, b) {
          final overrideCompare = b.overrideCount.compareTo(a.overrideCount);
          if (overrideCompare != 0) {
            return overrideCompare;
          }
          return a.path.toLowerCase().compareTo(b.path.toLowerCase());
        });
      return projects;
    } catch (_) {
      return const <ProjectRecord>[];
    }
  }

  Future<List<String>> _discoverWorkspaceConfigPaths(String rootPath) async {
    final rootDirectory = Directory(rootPath);
    if (!await rootDirectory.exists()) {
      return const <String>[];
    }

    final queue = Queue<({Directory directory, int depth})>()
      ..add((directory: rootDirectory, depth: 0));
    final visited = <String>{};
    final discovered = <String>{};

    while (queue.isNotEmpty && visited.length < maxDirectoriesPerRoot) {
      final item = queue.removeFirst();
      final path = item.directory.path;
      if (!visited.add(path)) {
        continue;
      }

      final configPath = await _discoverPrimaryConfigPath(path);
      if (configPath != null) {
        discovered.add(configPath);
        if (discovered.length >= maxProjectsPerRoot) {
          break;
        }
      }

      if (item.depth >= maxDepth) {
        continue;
      }

      final children = <Directory>[];
      await for (final entity
          in item.directory.list(followLinks: false).handleError((_) {})) {
        if (entity is! Directory) {
          continue;
        }
        final basename = _basename(entity.path);
        if (basename.startsWith('.') ||
            _ignoredDirectories.contains(basename)) {
          continue;
        }
        children.add(entity);
      }

      children.sort(
        (a, b) => a.path.toLowerCase().compareTo(b.path.toLowerCase()),
      );
      for (final child in children) {
        queue.add((directory: child, depth: item.depth + 1));
      }
    }

    final ordered = discovered.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return ordered;
  }

  List<ScanDirectoryRecord> _collapseOverlappingRoots(
    List<ScanDirectoryRecord> directories,
  ) {
    final sorted = directories.toList()
      ..sort((a, b) {
        final depthCompare = _pathDepth(a.path).compareTo(_pathDepth(b.path));
        if (depthCompare != 0) {
          return depthCompare;
        }
        return a.path.toLowerCase().compareTo(b.path.toLowerCase());
      });

    final kept = <ScanDirectoryRecord>[];
    for (final directory in sorted) {
      final covered = kept.any(
        (existing) => _containsPath(existing.path, directory.path),
      );
      if (!covered) {
        kept.add(directory);
      }
    }
    return kept;
  }

  Future<String?> _discoverPrimaryConfigPath(String directoryPath) async {
    for (final fileName in _workspaceConfigNames) {
      final candidate = File(
        '$directoryPath${Platform.pathSeparator}$fileName',
      );
      if (await candidate.exists()) {
        return candidate.path;
      }
    }
    return null;
  }

  Future<ProjectRecord?> _buildProjectRecord({
    required String configPath,
    required String scanRootPath,
    required String globalConfig,
  }) async {
    final workspacePath = File(configPath).parent.path;
    final workspaceConfig = await _readFileIfExists(configPath);
    if (workspaceConfig == null) {
      return null;
    }

    final projectAssignments = _parseAssignments(
      _extractSection(workspaceConfig, 'tools'),
    );
    final globalAssignments = _parseAssignments(
      _extractSection(globalConfig, 'tools'),
    );

    var installedTools = <String, List<MiseInstalledToolVersionRef>>{};
    String? scanIssue;
    try {
      installedTools = await _queryService.fetchInstalledTools(
        workingDirectory: workspacePath,
      );
    } on MiseProcessException catch (error) {
      scanIssue = _describeScanIssue(error);
    } catch (_) {
      scanIssue = '暂时无法解析 mise 的生效版本，已按项目文件里的声明继续展示。';
    }

    final activeVersions = <String, MiseInstalledToolVersionRef>{};
    for (final entry in installedTools.entries) {
      for (final version in entry.value) {
        if (version.active) {
          activeVersions[entry.key] = version;
          break;
        }
      }
    }

    final bindings = <ProjectToolBinding>[];
    final toolNames = <String>{
      ...projectAssignments.keys,
      ...activeVersions.keys,
    }.toList()..sort();

    for (final toolName in toolNames) {
      final active = activeVersions[toolName];
      final declaredInProject = projectAssignments.containsKey(toolName);
      final declaredInGlobal = globalAssignments.containsKey(toolName);
      final projectVersion =
          projectAssignments[toolName] ??
          active?.requestedVersion ??
          active?.version ??
          '未设置';
      final globalVersion = globalAssignments[toolName] ?? '未设置';
      final source = declaredInProject
          ? '项目'
          : _formatSource(active?.source?.path, configPath);

      bindings.add(
        ProjectToolBinding(
          name: toolName,
          projectVersion: projectVersion,
          globalVersion: globalVersion,
          source: source,
          declaredInProject: declaredInProject,
          declaredInGlobal: declaredInGlobal,
        ),
      );
    }

    bindings.sort((a, b) => a.name.compareTo(b.name));

    final environment = _resolveEnvironment(projectAssignments.keys);
    final declaredTools = bindings
        .where((binding) => binding.declaredInProject)
        .length;
    final overrides = bindings
        .where((binding) => binding.overridesGlobal)
        .length;
    final projectOnlyTools = bindings
        .where(
          (binding) => binding.declaredInProject && !binding.declaredInGlobal,
        )
        .length;

    return ProjectRecord(
      name: _basename(workspacePath),
      path: workspacePath,
      scanRootPath: scanRootPath,
      configPath: configPath,
      environment: environment,
      lastScan: await _formatLastScan(configPath),
      commandPreview: [
        'mise current',
        'mise ls --json',
        'cat $configPath',
      ].join('\n'),
      bindings: bindings,
      level: scanIssue != null || overrides > 0
          ? HealthLevel.warning
          : HealthLevel.healthy,
      notes: _buildNotes(
        declaredTools: declaredTools,
        overrides: overrides,
        projectOnlyTools: projectOnlyTools,
        scanIssue: scanIssue,
      ),
    );
  }

  String _buildNotes({
    required int declaredTools,
    required int overrides,
    required int projectOnlyTools,
    String? scanIssue,
  }) {
    final base = switch ((overrides, projectOnlyTools, declaredTools)) {
      (> 0, _, _) => '当前项目有 $overrides 个工具版本不同于全局配置。',
      (0, > 0, _) => '当前项目有 $projectOnlyTools 个工具只在项目中声明。',
      (0, 0, 0) => '当前项目没有项目级工具声明。',
      _ => '当前项目有 $declaredTools 个工具声明，与全局默认值保持一致。',
    };

    if (scanIssue == null || scanIssue.isEmpty) {
      return base;
    }
    return '$base $scanIssue';
  }

  String _describeScanIssue(MiseProcessException error) {
    final stderr = error.result.stderr.toLowerCase();
    if (stderr.contains('not trusted')) {
      return '这个项目的配置文件还没有被 mise trust，当前按文件声明展示版本。';
    }
    return '暂时无法解析 mise 的生效版本，已按项目文件里的声明继续展示。';
  }

  String _globalConfigPath() {
    final home = Platform.environment['HOME'];
    if (home == null || home.isEmpty) {
      return '.config/mise/config.toml';
    }
    return '$home/.config/mise/config.toml';
  }

  Future<String?> _readFileIfExists(String path) async {
    final file = File(path);
    if (!await file.exists()) {
      return null;
    }
    return file.readAsString();
  }

  Future<String> _formatLastScan(String path) async {
    try {
      final modifiedAt = await File(path).lastModified();
      final elapsed = DateTime.now().difference(modifiedAt);
      if (elapsed.inMinutes < 1) {
        return '刚刚';
      }
      if (elapsed.inHours < 1) {
        return '${elapsed.inMinutes} 分钟前';
      }
      return '${elapsed.inHours} 小时前';
    } catch (_) {
      return '最近';
    }
  }

  String? _extractSection(String? content, String sectionName) {
    if (content == null || content.trim().isEmpty) {
      return null;
    }

    final lines = content.split('\n');
    final buffer = <String>[];
    final header = '[$sectionName]';
    var collecting = false;

    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.startsWith('[') && trimmed.endsWith(']')) {
        if (collecting) {
          break;
        }
        if (trimmed == header) {
          collecting = true;
          buffer.add(line);
          continue;
        }
      }

      if (collecting) {
        buffer.add(line);
      }
    }

    if (buffer.isEmpty) {
      return null;
    }
    return buffer.join('\n').trimRight();
  }

  Map<String, String> _parseAssignments(String? section) {
    if (section == null || section.trim().isEmpty) {
      return const <String, String>{};
    }

    final result = <String, String>{};
    for (final line in section.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isEmpty ||
          trimmed.startsWith('#') ||
          trimmed.startsWith('[') ||
          !trimmed.contains('=')) {
        continue;
      }

      final index = trimmed.indexOf('=');
      final key = trimmed.substring(0, index).trim().replaceAll('"', '');
      final value = trimmed.substring(index + 1).trim().replaceAll('"', '');
      result[key] = value;
    }
    return result;
  }

  String _formatSource(String? sourcePath, String workspaceConfigPath) {
    if (sourcePath == null || sourcePath.isEmpty) {
      return '继承';
    }
    if (sourcePath == workspaceConfigPath) {
      return '项目';
    }
    if (sourcePath.contains('/.config/mise/')) {
      return '全局';
    }
    return '解析结果';
  }

  String _resolveEnvironment(Iterable<String> tools) {
    final toolSet = tools.toSet();
    if (toolSet.contains('flutter')) {
      return 'Flutter 桌面环境';
    }
    if (toolSet.contains('node')) {
      return 'Node 工作区';
    }
    if (toolSet.contains('python') && toolSet.contains('go')) {
      return 'Python 与 Go';
    }
    if (toolSet.contains('python')) {
      return 'Python';
    }
    if (toolSet.contains('java')) {
      return 'Java';
    }
    return 'mise 工作区';
  }

  String _basename(String path) {
    var normalized = path.replaceAll('\\', '/');
    while (normalized.endsWith('/')) {
      normalized = normalized.substring(0, normalized.length - 1);
    }
    final parts = normalized.split('/');
    return parts.isEmpty ? path : parts.last;
  }

  bool _containsPath(String parent, String child) {
    final normalizedParent = _normalizeComparablePath(parent);
    final normalizedChild = _normalizeComparablePath(child);
    return normalizedChild == normalizedParent ||
        normalizedChild.startsWith('$normalizedParent/');
  }

  String _normalizeComparablePath(String path) {
    var normalized = path.replaceAll('\\', '/');
    while (normalized.endsWith('/')) {
      normalized = normalized.substring(0, normalized.length - 1);
    }
    return normalized;
  }

  int _pathDepth(String path) {
    return _normalizeComparablePath(
      path,
    ).split('/').where((segment) => segment.isNotEmpty).length;
  }
}

class MockProjectScanService implements ProjectScanService {
  const MockProjectScanService();

  @override
  Future<List<ProjectRecord>> fetchProjects(
    List<ScanDirectoryRecord> directories,
  ) async {
    await Future<void>.delayed(const Duration(milliseconds: 150));

    return const [
      ProjectRecord(
        name: 'frontend-app',
        path: '~/Workspaces/frontend-app',
        scanRootPath: '~/Workspaces',
        configPath: '~/Workspaces/frontend-app/mise.toml',
        environment: 'Node 工作区',
        lastScan: '2 分钟前',
        commandPreview: 'mise current\nmise ls --json',
        level: HealthLevel.warning,
        notes: '当前项目有 1 个工具版本不同于全局配置。',
        bindings: [
          ProjectToolBinding(
            name: 'node',
            projectVersion: '20.16.0',
            globalVersion: '22.4.1',
            source: '项目',
            declaredInProject: true,
            declaredInGlobal: true,
          ),
        ],
      ),
      ProjectRecord(
        name: 'mise_gui',
        path: '~/Documents/FlutterProject/mise_gui',
        scanRootPath: '~/Documents/FlutterProject',
        configPath: '~/Documents/FlutterProject/mise_gui/mise.toml',
        environment: 'Flutter 桌面环境',
        lastScan: '4 小时前',
        commandPreview: 'mise current\nmise ls --json',
        level: HealthLevel.healthy,
        notes: '当前项目有 1 个工具声明，与全局默认值保持一致。',
        bindings: [
          ProjectToolBinding(
            name: 'flutter',
            projectVersion: '3.41.4',
            globalVersion: '3.41.4',
            source: '项目',
            declaredInProject: true,
            declaredInGlobal: true,
          ),
        ],
      ),
      ProjectRecord(
        name: 'api-gateway',
        path: '~/Workspaces/api-gateway',
        scanRootPath: '~/Workspaces',
        configPath: '~/Workspaces/api-gateway/mise.toml',
        environment: 'Python',
        lastScan: '1 小时前',
        commandPreview: 'mise current\nmise ls --json',
        level: HealthLevel.warning,
        notes: '当前项目有 1 个工具版本不同于全局配置。',
        bindings: [
          ProjectToolBinding(
            name: 'python',
            projectVersion: '3.11',
            globalVersion: '3',
            source: '项目',
            declaredInProject: true,
            declaredInGlobal: true,
          ),
        ],
      ),
    ];
  }
}

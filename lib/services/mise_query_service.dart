import 'dart:io';
import 'dart:convert';

import 'package:mise_gui/services/mise_process_service.dart';

class MiseSourceRef {
  const MiseSourceRef({required this.type, this.path});

  final String type;
  final String? path;
}

class MiseInstalledToolVersionRef {
  const MiseInstalledToolVersionRef({
    required this.tool,
    required this.version,
    required this.installed,
    required this.active,
    this.requestedVersion,
    this.installPath,
    this.source,
  });

  final String tool;
  final String version;
  final bool installed;
  final bool active;
  final String? requestedVersion;
  final String? installPath;
  final MiseSourceRef? source;
}

class MiseRemoteToolVersionRef {
  const MiseRemoteToolVersionRef({
    required this.tool,
    required this.version,
    required this.rolling,
    this.createdAt,
  });

  final String tool;
  final String version;
  final bool rolling;
  final String? createdAt;
}

class MiseCurrentToolRef {
  const MiseCurrentToolRef({
    required this.tool,
    required this.version,
    required this.rawLine,
  });

  final String tool;
  final String version;
  final String rawLine;
}

class MiseResolvedExecutableRef {
  const MiseResolvedExecutableRef({
    required this.subject,
    required this.command,
    required this.exitCode,
    required this.stdout,
    required this.stderr,
  });

  final String subject;
  final String command;
  final int exitCode;
  final String stdout;
  final String stderr;

  bool get isResolved => exitCode == 0 && resolvedPath != null;

  String? get resolvedPath {
    final value = stdout.trim();
    return value.isEmpty ? null : value;
  }
}

abstract class MiseQueryService {
  Future<Map<String, List<MiseInstalledToolVersionRef>>> fetchInstalledTools({
    String? workingDirectory,
  });

  Future<List<MiseCurrentToolRef>> fetchCurrentTools({
    String? workingDirectory,
  });

  Future<List<MiseRemoteToolVersionRef>> fetchRemoteVersions(
    String tool, {
    String? workingDirectory,
  });

  Future<Map<String, dynamic>> fetchOutdated({String? workingDirectory});

  Future<Map<String, dynamic>> fetchSettings({String? workingDirectory});

  Future<Map<String, dynamic>> fetchEnvironment({String? workingDirectory});

  Future<MiseResolvedExecutableRef> fetchExecutable(
    String subject, {
    String? workingDirectory,
  });

  Future<MiseResolvedExecutableRef> fetchShellExecutable(
    String subject, {
    String? workingDirectory,
  });
}

class CliMiseQueryService implements MiseQueryService {
  const CliMiseQueryService(this._processService);

  final MiseProcessService _processService;

  @override
  Future<Map<String, List<MiseInstalledToolVersionRef>>> fetchInstalledTools({
    String? workingDirectory,
  }) async {
    final result = await _processService.run(
      MiseCommandRequest(
        arguments: const ['ls', '--json'],
        workingDirectory: workingDirectory,
      ),
    );

    final json = jsonDecode(result.stdout) as Map<String, dynamic>;
    final parsed = <String, List<MiseInstalledToolVersionRef>>{};

    for (final entry in json.entries) {
      final tool = entry.key;
      final records = (entry.value as List<dynamic>)
          .cast<Map<String, dynamic>>()
          .map(
            (item) => MiseInstalledToolVersionRef(
              tool: tool,
              version: item['version'] as String,
              requestedVersion: item['requested_version'] as String?,
              installPath: item['install_path'] as String?,
              installed: item['installed'] as bool? ?? false,
              active: item['active'] as bool? ?? false,
              source: _parseSource(item['source'] as Map<String, dynamic>?),
            ),
          )
          .toList();

      parsed[tool] = records;
    }

    return parsed;
  }

  @override
  Future<List<MiseCurrentToolRef>> fetchCurrentTools({
    String? workingDirectory,
  }) async {
    final result = await _processService.run(
      MiseCommandRequest(
        arguments: const ['current'],
        workingDirectory: workingDirectory,
      ),
    );

    final lines = const LineSplitter().convert(result.stdout);
    final tools = <MiseCurrentToolRef>[];

    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) {
        continue;
      }

      final match = RegExp(r'^(\S+)\s+(\S+)').firstMatch(trimmed);
      if (match == null) {
        continue;
      }

      tools.add(
        MiseCurrentToolRef(
          tool: match.group(1)!,
          version: match.group(2)!,
          rawLine: trimmed,
        ),
      );
    }

    return tools;
  }

  @override
  Future<List<MiseRemoteToolVersionRef>> fetchRemoteVersions(
    String tool, {
    String? workingDirectory,
  }) async {
    final result = await _processService.run(
      MiseCommandRequest(
        arguments: ['ls-remote', '--json', tool],
        workingDirectory: workingDirectory,
        timeout: const Duration(seconds: 90),
      ),
    );

    final json = jsonDecode(result.stdout) as List<dynamic>;

    return json
        .cast<Map<String, dynamic>>()
        .map(
          (item) => MiseRemoteToolVersionRef(
            tool: tool,
            version: item['version'] as String,
            rolling: item['rolling'] as bool? ?? false,
            createdAt: item['created_at'] as String?,
          ),
        )
        .toList();
  }

  @override
  Future<Map<String, dynamic>> fetchOutdated({String? workingDirectory}) async {
    final result = await _processService.run(
      MiseCommandRequest(
        arguments: const ['outdated', '--json'],
        workingDirectory: workingDirectory,
      ),
    );

    return jsonDecode(result.stdout) as Map<String, dynamic>;
  }

  @override
  Future<Map<String, dynamic>> fetchSettings({String? workingDirectory}) async {
    final result = await _processService.run(
      MiseCommandRequest(
        arguments: const ['settings', 'ls', '--json-extended'],
        workingDirectory: workingDirectory,
      ),
    );

    return jsonDecode(result.stdout) as Map<String, dynamic>;
  }

  @override
  Future<Map<String, dynamic>> fetchEnvironment({
    String? workingDirectory,
  }) async {
    final result = await _processService.run(
      MiseCommandRequest(
        arguments: const ['env', '-J'],
        workingDirectory: workingDirectory,
      ),
    );

    return jsonDecode(result.stdout) as Map<String, dynamic>;
  }

  @override
  Future<MiseResolvedExecutableRef> fetchExecutable(
    String subject, {
    String? workingDirectory,
  }) async {
    final result = await _processService.run(
      MiseCommandRequest(
        arguments: ['which', subject],
        workingDirectory: workingDirectory,
        allowNonZeroExit: true,
      ),
    );

    return MiseResolvedExecutableRef(
      subject: subject,
      command: 'mise which $subject',
      exitCode: result.exitCode,
      stdout: result.stdout,
      stderr: result.stderr,
    );
  }

  @override
  Future<MiseResolvedExecutableRef> fetchShellExecutable(
    String subject, {
    String? workingDirectory,
  }) async {
    final shellPath = _shellPath();
    final command = 'command -v ${_shellQuote(subject)}';

    final result = await Process.run(
      shellPath,
      ['-ilc', command],
      workingDirectory: workingDirectory,
      includeParentEnvironment: true,
      runInShell: false,
    );

    return MiseResolvedExecutableRef(
      subject: subject,
      command: command,
      exitCode: result.exitCode,
      stdout: (result.stdout ?? '').toString(),
      stderr: (result.stderr ?? '').toString(),
    );
  }

  MiseSourceRef? _parseSource(Map<String, dynamic>? source) {
    if (source == null) {
      return null;
    }

    return MiseSourceRef(
      type: source['type'] as String? ?? 'unknown',
      path: source['path'] as String?,
    );
  }

  String _shellPath() {
    final configured = Platform.environment['SHELL'];
    if (configured != null && configured.isNotEmpty) {
      return configured;
    }
    return Platform.isMacOS ? '/bin/zsh' : '/bin/bash';
  }

  String _shellQuote(String value) {
    return "'${value.replaceAll("'", r"'\''")}'";
  }
}

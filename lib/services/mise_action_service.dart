import 'dart:convert';

import 'package:mise_gui/services/mise_process_service.dart';

class ExecutedMiseCommand {
  const ExecutedMiseCommand({
    required this.command,
    required this.stdout,
    required this.stderr,
    required this.exitCode,
    required this.duration,
  });

  final String command;
  final String stdout;
  final String stderr;
  final int exitCode;
  final Duration duration;
}

class MiseActionResult {
  const MiseActionResult({required this.script, required this.commands});

  final String script;
  final List<ExecutedMiseCommand> commands;

  bool get isSuccess =>
      commands.isNotEmpty && commands.every((item) => item.exitCode == 0);

  int get exitCode => commands.isEmpty ? -1 : commands.last.exitCode;

  Duration get duration =>
      commands.fold(Duration.zero, (total, item) => total + item.duration);

  String get stdout => commands
      .where((item) => item.stdout.trim().isNotEmpty)
      .map((item) => '\$ ${item.command}\n${item.stdout.trim()}')
      .join('\n\n');

  String get stderr => commands
      .where((item) => item.stderr.trim().isNotEmpty)
      .map((item) => '\$ ${item.command}\n${item.stderr.trim()}')
      .join('\n\n');

  String? get stdoutSnippet {
    for (final command in commands.reversed) {
      final trimmed = command.stdout.trim();
      if (trimmed.isNotEmpty) {
        return trimmed.split('\n').take(3).join('\n');
      }
    }
    return null;
  }

  String? get stderrSnippet {
    for (final command in commands.reversed) {
      final trimmed = command.stderr.trim();
      if (trimmed.isNotEmpty) {
        return trimmed.split('\n').take(3).join('\n');
      }
    }
    return null;
  }
}

abstract class MiseActionService {
  Future<MiseActionResult> runScript(String script, {String? workingDirectory});
}

class LocalMiseActionService implements MiseActionService {
  const LocalMiseActionService(this._processService);

  final MiseProcessService _processService;

  @override
  Future<MiseActionResult> runScript(
    String script, {
    String? workingDirectory,
  }) async {
    final commands = <ExecutedMiseCommand>[];

    for (final rawLine in const LineSplitter().convert(script)) {
      final line = rawLine.trim();
      if (line.isEmpty || line.startsWith('#')) {
        continue;
      }
      if (!line.startsWith('mise ')) {
        throw UnsupportedError(
          'Only mise CLI commands can be executed from GUI actions.',
        );
      }

      final arguments = _parseArguments(line.substring(5));
      final result = await _processService.run(
        MiseCommandRequest(
          arguments: arguments,
          workingDirectory: workingDirectory,
          allowNonZeroExit: true,
          preferShellExecution: true,
          timeout: const Duration(minutes: 6),
        ),
      );

      commands.add(
        ExecutedMiseCommand(
          command: line,
          stdout: result.stdout,
          stderr: result.stderr,
          exitCode: result.exitCode,
          duration: result.duration,
        ),
      );

      if (result.exitCode != 0) {
        break;
      }
    }

    return MiseActionResult(script: script, commands: commands);
  }

  List<String> _parseArguments(String input) {
    final matches = RegExp(
      r'''[^\s"']+|"([^"]*)"|'([^']*)' ''',
    ).allMatches('$input ').toList();
    if (matches.isEmpty) {
      return const <String>[];
    }

    return matches.map((match) {
      final full = match.group(0)!.trimRight();
      if (full.startsWith('"') && full.endsWith('"')) {
        return full.substring(1, full.length - 1);
      }
      if (full.startsWith("'") && full.endsWith("'")) {
        return full.substring(1, full.length - 1);
      }
      return full;
    }).toList();
  }
}

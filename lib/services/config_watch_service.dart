import 'dart:async';
import 'dart:io';

abstract class ConfigWatchService {
  Stream<void> watchPaths(List<String> paths);
}

class LocalConfigWatchService implements ConfigWatchService {
  const LocalConfigWatchService({
    this.debounceDuration = const Duration(milliseconds: 320),
  });

  final Duration debounceDuration;

  @override
  Stream<void> watchPaths(List<String> paths) {
    final uniquePaths = paths.toSet().where((path) => path.trim().isNotEmpty);

    if (uniquePaths.isEmpty) {
      return const Stream<void>.empty();
    }

    late final StreamController<void> controller;
    final subscriptions = <StreamSubscription<FileSystemEvent>>[];
    Timer? debounce;

    void emit() {
      debounce?.cancel();
      debounce = Timer(debounceDuration, () {
        if (!controller.isClosed) {
          controller.add(null);
        }
      });
    }

    Future<void> attachWatchers() async {
      for (final path in uniquePaths) {
        final targetFile = File(path);
        final parent = await _resolveWatchDirectory(targetFile.parent);
        if (!await parent.exists()) {
          continue;
        }

        final fileName = targetFile.uri.pathSegments.isEmpty
            ? targetFile.path
            : targetFile.uri.pathSegments.last;

        final subscription = parent
            .watch(
              events:
                  FileSystemEvent.create |
                  FileSystemEvent.modify |
                  FileSystemEvent.delete |
                  FileSystemEvent.move,
            )
            .handleError((_) {})
            .listen((event) {
              final eventFileName = event.path
                  .split(Platform.pathSeparator)
                  .last;
              if (eventFileName == fileName) {
                emit();
              }
            }, onError: (_) {});

        subscriptions.add(subscription);
      }
    }

    controller = StreamController<void>(
      onListen: attachWatchers,
      onCancel: () async {
        debounce?.cancel();
        for (final subscription in subscriptions) {
          await subscription.cancel();
        }
      },
    );

    return controller.stream;
  }

  Future<Directory> _resolveWatchDirectory(Directory initial) async {
    var current = initial;

    while (!await current.exists()) {
      final parent = current.parent;
      if (parent.path == current.path) {
        return initial;
      }
      current = parent;
    }

    return current;
  }
}

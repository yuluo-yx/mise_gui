import 'package:flutter_test/flutter_test.dart';
import 'package:mise_gui/services/mise_process_service.dart';

void main() {
  test('diagnoses missing make for source builds', () {
    final diagnosis = diagnoseMiseCommandFailure(
      command: 'mise install redis@8.6.2',
      stderr:
          'mise [redis] Compiling Redis from source...\n'
          'sh: make: command not found\n'
          'Failed to compile Redis. Make sure you have a C compiler (gcc/clang) and make installed.',
    );

    expect(diagnosis, isNotNull);
    expect(diagnosis!.summary, contains('缺少 make'));
    expect(diagnosis.detail, contains('xcode-select --install'));
  });

  test('diagnoses missing compiler toolchain', () {
    final diagnosis = diagnoseMiseCommandFailure(
      command: 'mise install erlang@27',
      stderr: 'configure: error: no acceptable C compiler found in \$PATH',
    );

    expect(diagnosis, isNotNull);
    expect(diagnosis!.summary, contains('C 编译工具链'));
    expect(diagnosis.detail, contains('clang --version'));
  });
}

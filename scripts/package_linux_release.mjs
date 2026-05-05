#!/usr/bin/env node
import fs from 'node:fs';
import path from 'node:path';

import {
  APP_DISPLAY_NAME,
  BINARY_NAME,
  ROOT_DIR,
  copyDirectory,
  dateStamp,
  ensureDir,
  findExistingDir,
  inferArchFromBuildPath,
  makeTempStage,
  printArtifact,
  readPubspecVersion,
  recreateDir,
  runFlutterBuild,
  tarGzDirectory,
  zipDirectory,
} from './desktop_package_common.mjs';

function main() {
  const format = process.argv.includes('--zip') ? 'zip' : 'tar.gz';

  if (process.platform !== 'linux') {
    throw new Error('Linux release packages must be built on Linux with the Flutter Linux toolchain.');
  }

  runFlutterBuild('linux');

  const bundleDir = findExistingDir(
    [
      path.join(ROOT_DIR, 'build', 'linux', 'x64', 'release', 'bundle'),
      path.join(ROOT_DIR, 'build', 'linux', 'release', 'bundle'),
    ],
    'Flutter Linux release bundle',
  );
  const executablePath = path.join(bundleDir, BINARY_NAME);

  if (!fs.existsSync(executablePath)) {
    throw new Error(`Could not find built executable: ${executablePath}`);
  }

  const arch = inferArchFromBuildPath(bundleDir, 'linux');
  const version = readPubspecVersion();
  const distDir = path.join(ROOT_DIR, 'dist', 'linux');
  const extension = format === 'zip' ? 'zip' : 'tar.gz';
  const artifactPath = path.join(
    distDir,
    `${APP_DISPLAY_NAME}-Linux-${arch}-release-${version}-${dateStamp()}.${extension}`,
  );
  const tempRoot = makeTempStage('mise-gui-linux-release-');
  const stageDir = path.join(tempRoot, `${APP_DISPLAY_NAME}-Linux-${arch}`);

  try {
    ensureDir(distDir);
    recreateDir(stageDir);
    copyDirectory(bundleDir, stageDir);

    if (format === 'zip') {
      zipDirectory(stageDir, artifactPath);
    } else {
      tarGzDirectory(stageDir, artifactPath);
    }

    printArtifact(artifactPath);
  } finally {
    fs.rmSync(tempRoot, { recursive: true, force: true });
  }
}

try {
  main();
} catch (error) {
  console.error(error instanceof Error ? error.message : String(error));
  process.exit(1);
}

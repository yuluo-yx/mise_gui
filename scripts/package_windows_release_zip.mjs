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
  zipDirectory,
} from './desktop_package_common.mjs';

const requiredRuntimeDlls = [
  'msvcp140.dll',
  'vcruntime140.dll',
  'vcruntime140_1.dll',
];

function findFileRecursive(baseDir, fileName, maxDepth = 6) {
  if (!baseDir || !fs.existsSync(baseDir) || maxDepth < 0) {
    return null;
  }

  let entries;
  try {
    entries = fs.readdirSync(baseDir, { withFileTypes: true });
  } catch {
    return null;
  }

  for (const entry of entries) {
    const fullPath = path.join(baseDir, entry.name);
    if (entry.isFile() && entry.name.toLowerCase() === fileName.toLowerCase()) {
      return fullPath;
    }
  }

  for (const entry of entries) {
    if (!entry.isDirectory()) {
      continue;
    }
    const found = findFileRecursive(path.join(baseDir, entry.name), fileName, maxDepth - 1);
    if (found) {
      return found;
    }
  }

  return null;
}

function redistSearchRoots() {
  const roots = [
    process.env.VCToolsRedistDir ? { dir: process.env.VCToolsRedistDir, maxDepth: 6 } : null,
    process.env.SystemRoot ? { dir: path.join(process.env.SystemRoot, 'System32'), maxDepth: 0 } : null,
    process.env.WINDIR ? { dir: path.join(process.env.WINDIR, 'System32'), maxDepth: 0 } : null,
  ];

  for (const programFiles of [process.env.ProgramFiles, process.env['ProgramFiles(x86)']]) {
    if (!programFiles) {
      continue;
    }
    for (const edition of ['Community', 'Professional', 'Enterprise', 'BuildTools']) {
      roots.push(
        {
          dir: path.join(
            programFiles,
            'Microsoft Visual Studio',
            '2022',
            edition,
            'VC',
            'Redist',
            'MSVC',
          ),
          maxDepth: 6,
        },
      );
    }
  }

  return roots.filter(Boolean);
}

function copyVisualCppRuntimeDlls(stageDir, releaseDir) {
  const searchRoots = redistSearchRoots();
  const missing = [];

  for (const dll of requiredRuntimeDlls) {
    const bundled = path.join(releaseDir, dll);
    const source = fs.existsSync(bundled)
      ? bundled
      : searchRoots
          .map(({ dir, maxDepth }) => findFileRecursive(dir, dll, maxDepth))
          .find(Boolean);

    if (source) {
      fs.copyFileSync(source, path.join(stageDir, dll));
    } else {
      missing.push(dll);
    }
  }

  if (missing.length > 0) {
    console.warn(
      [
        `Warning: could not find Visual C++ runtime DLL(s): ${missing.join(', ')}`,
        'Install the Microsoft Visual C++ Redistributable on target machines,',
        'or run this script from a Visual Studio Developer PowerShell so the DLLs can be bundled.',
      ].join(' '),
    );
  }
}

function main() {
  if (process.platform !== 'win32') {
    throw new Error('Windows release packages must be built on Windows with the Flutter Windows toolchain.');
  }

  runFlutterBuild('windows');

  const releaseDir = findExistingDir(
    [
      path.join(ROOT_DIR, 'build', 'windows', 'x64', 'runner', 'Release'),
      path.join(ROOT_DIR, 'build', 'windows', 'runner', 'Release'),
    ],
    'Flutter Windows release output',
  );
  const exePath = path.join(releaseDir, `${BINARY_NAME}.exe`);
  const dataDir = path.join(releaseDir, 'data');

  if (!fs.existsSync(exePath)) {
    throw new Error(`Could not find built executable: ${exePath}`);
  }
  if (!fs.existsSync(dataDir)) {
    throw new Error(`Could not find Flutter data directory: ${dataDir}`);
  }

  const arch = inferArchFromBuildPath(releaseDir, 'windows');
  const version = readPubspecVersion();
  const distDir = path.join(ROOT_DIR, 'dist', 'windows');
  const artifactPath = path.join(
    distDir,
    `${APP_DISPLAY_NAME}-Windows-${arch}-release-${version}-${dateStamp()}.zip`,
  );
  const tempRoot = makeTempStage('mise-gui-windows-release-');
  const stageDir = path.join(tempRoot, `${APP_DISPLAY_NAME}-Windows-${arch}`);

  try {
    ensureDir(distDir);
    recreateDir(stageDir);
    copyDirectory(releaseDir, stageDir);
    copyVisualCppRuntimeDlls(stageDir, releaseDir);
    zipDirectory(stageDir, artifactPath);
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

import { readdir, readFile } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const repoRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const ignoredDirs = new Set([
  '.git',
  '.dart_tool',
  '.idea',
  '.vscode',
  'build',
  'dist',
  'node_modules',
  'target',
]);

const blockedPackageVersions = new Map([
  ['axios', new Set(['1.14.1', '0.30.4'])],
  ['plain-crypto-js', new Set(['4.2.1'])],
]);

const blockedIocs = [
  'sfrclak.com',
  '142.11.206.73',
  'f7d335205b8d7b20208fb3ef93ee6dc817905dc3ae0c10a0b164f4e7d07121cd',
  '617b67a8e1210e4fc87c92d1d1da45a2f311c08d26e89b12307cf583c900d101',
  '92ff08773995ebc8d55ec4b8e1a225d0d1e51efa4ef88b8849d0071230c9645a',
];

const lifecycleScriptNames = [
  'preinstall',
  'install',
  'postinstall',
  'prepublish',
  'preprepare',
  'prepare',
];

async function walk(dir) {
  const results = [];
  const entries = await readdir(dir, { withFileTypes: true });

  for (const entry of entries) {
    const fullPath = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      if (!ignoredDirs.has(entry.name)) {
        results.push(...await walk(fullPath));
      }
      continue;
    }

    results.push(fullPath);
  }

  return results;
}

function toPosixRelative(filePath) {
  return path.relative(repoRoot, filePath).split(path.sep).join('/');
}

function hasDependencies(pkg) {
  return [
    'dependencies',
    'devDependencies',
    'optionalDependencies',
    'peerDependencies',
  ].some((field) => Object.keys(pkg[field] ?? {}).length > 0);
}

function checkManifestPackageSet(relativePath, packageSet, findings, fieldName) {
  for (const [packageName, versionSpec] of Object.entries(packageSet ?? {})) {
    const blockedVersions = blockedPackageVersions.get(packageName);
    if (!blockedVersions) {
      continue;
    }

    for (const blockedVersion of blockedVersions) {
      if (String(versionSpec).includes(blockedVersion)) {
        findings.push(
          `${relativePath}: ${fieldName} references blocked package version ${packageName}@${blockedVersion}`,
        );
      }
    }
  }
}

function scanTextForIocs(relativePath, content, findings) {
  for (const indicator of blockedIocs) {
    if (content.includes(indicator)) {
      findings.push(`${relativePath}: contains blocked IOC ${indicator}`);
    }
  }
}

function checkPackageLock(relativePath, lock, findings) {
  const packages = lock.packages ?? {};

  for (const [packagePath, metadata] of Object.entries(packages)) {
    const packageName = metadata.name
      ?? (packagePath.startsWith('node_modules/')
        ? packagePath.slice('node_modules/'.length)
        : packagePath);
    const version = metadata.version;
    const blockedVersions = blockedPackageVersions.get(packageName);

    if (blockedVersions?.has(version)) {
      findings.push(
        `${relativePath}: lockfile contains blocked package version ${packageName}@${version}`,
      );
    }

    if (metadata.hasInstallScript === true) {
      findings.push(
        `${relativePath}: lockfile package ${packageName || '<root>'} declares install-time scripts`,
      );
    }
  }
}

async function main() {
  const files = await walk(repoRoot);
  const findings = [];
  const packageJsonFiles = files.filter((file) => path.basename(file) === 'package.json');
  const textFiles = files.filter((file) => {
    const base = path.basename(file);
    return base === 'package.json'
      || base === 'package-lock.json'
      || base === 'npm-shrinkwrap.json'
      || base === 'README.md'
      || base.endsWith('.yml')
      || base.endsWith('.yaml')
      || base.endsWith('.toml')
      || base.endsWith('.mjs')
      || base.endsWith('.js');
  });

  for (const file of textFiles) {
    if (path.resolve(file) === fileURLToPath(import.meta.url)) {
      continue;
    }
    const content = await readFile(file, 'utf8');
    scanTextForIocs(toPosixRelative(file), content, findings);
  }

  for (const packageJsonFile of packageJsonFiles) {
    const relativePath = toPosixRelative(packageJsonFile);
    const packageDir = path.dirname(packageJsonFile);
    const manifest = JSON.parse(await readFile(packageJsonFile, 'utf8'));

    checkManifestPackageSet(relativePath, manifest.dependencies, findings, 'dependencies');
    checkManifestPackageSet(relativePath, manifest.devDependencies, findings, 'devDependencies');
    checkManifestPackageSet(relativePath, manifest.optionalDependencies, findings, 'optionalDependencies');
    checkManifestPackageSet(relativePath, manifest.peerDependencies, findings, 'peerDependencies');

    for (const scriptName of lifecycleScriptNames) {
      if (manifest.scripts?.[scriptName]) {
        findings.push(
          `${relativePath}: manifest defines lifecycle script "${scriptName}" which should require explicit review`,
        );
      }
    }

    if (hasDependencies(manifest)) {
      const hasLockfile = ['package-lock.json', 'npm-shrinkwrap.json', 'pnpm-lock.yaml', 'yarn.lock']
        .some((fileName) => files.includes(path.join(packageDir, fileName)));
      if (!hasLockfile) {
        findings.push(`${relativePath}: dependencies are declared without a lockfile in the same directory`);
      }
    }
  }

  for (const lockfile of files.filter((file) => path.basename(file) === 'package-lock.json')) {
    const relativePath = toPosixRelative(lockfile);
    const parsed = JSON.parse(await readFile(lockfile, 'utf8'));
    checkPackageLock(relativePath, parsed, findings);
  }

  if (findings.length > 0) {
    console.error('Node supply-chain check failed:\n');
    for (const finding of findings) {
      console.error(`- ${finding}`);
    }
    process.exitCode = 1;
    return;
  }

  console.log('Node supply-chain check passed: no blocked packages, IOCs, or unsafe lockfile patterns found.');
}

await main();

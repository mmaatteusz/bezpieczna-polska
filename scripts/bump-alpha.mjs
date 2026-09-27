import { readFileSync, writeFileSync } from 'node:fs';

const backendPackageUrl = new URL('../backend/package.json', import.meta.url);
const backendLockUrl = new URL('../backend/package-lock.json', import.meta.url);
const pubspecUrl = new URL('../mobile/pubspec.yaml', import.meta.url);
const runbookUrl = new URL('../docs/PRODUCTION_RUNBOOK.md', import.meta.url);

const backendPackageRaw = readFileSync(backendPackageUrl, 'utf8');
const backendPackage = JSON.parse(backendPackageRaw);
const currentVersion = String(backendPackage.version ?? '');
const alphaMatch = currentVersion.match(/^(\d+\.\d+\.\d+)-alpha\.(\d+)$/);
if (!alphaMatch) {
  throw new Error(
    `Expected backend version like 0.1.0-alpha.23, got ${currentVersion}`,
  );
}

const pubspec = readFileSync(pubspecUrl, 'utf8');
const pubspecMatch = pubspec.match(/^version:\s*([^+\s]+)\+(\d+)\s*$/m);
if (!pubspecMatch) {
  throw new Error('Expected versionName+buildNumber in mobile/pubspec.yaml');
}
if (pubspecMatch[1] !== currentVersion) {
  throw new Error(
    `Version mismatch: backend=${currentVersion}, mobile=${pubspecMatch[1]}`,
  );
}

const nextVersion = `${alphaMatch[1]}-alpha.${Number(alphaMatch[2]) + 1}`;
const nextBuild = Number(pubspecMatch[2]) + 1;
if (!Number.isSafeInteger(nextBuild) || nextBuild < 1) {
  throw new Error('Cannot allocate the next production build number');
}

const backendLock = readFileSync(backendLockUrl, 'utf8');
if (!backendLock.includes(currentVersion)) {
  throw new Error('backend/package-lock.json does not contain the current version');
}

writeFileSync(
  backendPackageUrl,
  backendPackageRaw.replace(currentVersion, nextVersion),
);
writeFileSync(
  backendLockUrl,
  backendLock.replaceAll(currentVersion, nextVersion),
);
writeFileSync(
  pubspecUrl,
  pubspec.replace(
    /^version:\s*[^+\s]+\+\d+\s*$/m,
    `version: ${nextVersion}+${nextBuild}`,
  ),
);

const runbook = readFileSync(runbookUrl, 'utf8');
writeFileSync(
  runbookUrl,
  runbook.replace(
    /^Aktualny kod: \*\*[^*]+\*\*\.$/m,
    `Aktualny kod: **${nextVersion}**.`,
  ),
);

await import('./sync-mobile-version.mjs');
console.log(`Bumped ${currentVersion} -> ${nextVersion}, production build ${nextBuild}`);

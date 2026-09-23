import { readFileSync, writeFileSync } from 'node:fs';

const backendPackage = JSON.parse(
  readFileSync(new URL('../backend/package.json', import.meta.url), 'utf8'),
);
const version = String(backendPackage.version ?? '');
if (!/^\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?$/.test(version)) {
  throw new Error('Expected a valid semantic version in backend/package.json');
}

const pubspec = readFileSync(new URL('../mobile/pubspec.yaml', import.meta.url), 'utf8');
const match = pubspec.match(/^version:\s*([^+\s]+)\+(\d+)\s*$/m);
if (!match) throw new Error('Expected a versionName+buildNumber in mobile/pubspec.yaml');
if (match[1] !== version) {
  throw new Error(`Version mismatch: backend/package.json=${version}, mobile/pubspec.yaml=${match[1]}`);
}

const mobileTarget = new URL('../mobile/lib/app_version.dart', import.meta.url);
const generatedMobile =
  `// Generated from backend/package.json + mobile/pubspec.yaml by scripts/sync-mobile-version.mjs.\n` +
  `// Run node scripts/sync-mobile-version.mjs after changing both release versions.\n` +
  `const appVersion = '${version}';\n`;

const backendTarget = new URL('../backend/src/config.ts', import.meta.url);
const backendConfig = readFileSync(backendTarget, 'utf8');
const versionLine = /^export const APP_VERSION='[^']+';/m;
if (!versionLine.test(backendConfig)) {
  throw new Error('Expected APP_VERSION in backend/src/config.ts');
}
const generatedBackend = backendConfig.replace(
  versionLine,
  `export const APP_VERSION='${version}';`,
);

const check = process.argv.includes('--check');
if (check) {
  if (readFileSync(mobileTarget, 'utf8') !== generatedMobile) {
    throw new Error('mobile/lib/app_version.dart differs from canonical release version');
  }
  if (backendConfig !== generatedBackend) {
    throw new Error('backend/src/config.ts APP_VERSION differs from canonical release version');
  }
} else {
  writeFileSync(mobileTarget, generatedMobile);
  writeFileSync(backendTarget, generatedBackend);
}
console.log(
  `Release version ${version} (build ${match[2]}): ${check ? 'verified' : 'synced'}`,
);

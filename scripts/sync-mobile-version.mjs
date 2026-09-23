import { readFileSync, writeFileSync } from 'node:fs';

const pubspec = readFileSync(new URL('../mobile/pubspec.yaml', import.meta.url), 'utf8');
const match = pubspec.match(/^version:\s*([^+\s]+)\+\d+\s*$/m);
if (!match) throw new Error('Expected a versionName+buildNumber in mobile/pubspec.yaml');
const target = new URL('../mobile/lib/app_version.dart', import.meta.url);
const generated = `// Generated from mobile/pubspec.yaml by scripts/sync-mobile-version.mjs.\n` +
  `// Run node scripts/sync-mobile-version.mjs after changing the pubspec version.\n` +
  `const appVersion = '${match[1]}';\n`;
if (process.argv.includes('--check')) {
  if (readFileSync(target, 'utf8') !== generated) {
    throw new Error('mobile/lib/app_version.dart differs from mobile/pubspec.yaml');
  }
} else {
  writeFileSync(target, generated);
}
console.log(`Mobile version ${match[1]}: ${process.argv.includes('--check') ? 'verified' : 'synced'}`);

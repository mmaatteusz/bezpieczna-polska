import { execFileSync } from 'node:child_process';
import { readFileSync } from 'node:fs';

function parseBuildNumber(yaml, source) {
  const match = yaml.match(/^version:\s*[^+\s]+\+(\d+)\s*$/m);
  if (!match) throw new Error(`Missing versionName+buildNumber in ${source}`);
  const value = Number(match[1]);
  if (!Number.isSafeInteger(value) || value < 1) {
    throw new Error(`Invalid Android build number in ${source}: ${match[1]}`);
  }
  return value;
}

const currentYaml = readFileSync(new URL('../mobile/pubspec.yaml', import.meta.url), 'utf8');
const current = parseBuildNumber(currentYaml, 'mobile/pubspec.yaml');

const head = execFileSync('git', ['rev-parse', 'HEAD'], { encoding: 'utf8' }).trim();
const tags = execFileSync('git', ['tag', '--list', 'v*', '--sort=-creatordate'], {
  encoding: 'utf8',
})
  .split(/\r?\n/)
  .map((tag) => tag.trim())
  .filter(Boolean);

let maxPrevious = 0;
let maxTag = null;

for (const tag of tags) {
  const tagCommit = execFileSync('git', ['rev-list', '-n', '1', tag], { encoding: 'utf8' }).trim();
  if (tagCommit === head) continue;

  let yaml;
  try {
    yaml = execFileSync('git', ['show', `${tag}:mobile/pubspec.yaml`], { encoding: 'utf8' });
  } catch {
    continue;
  }

  const build = parseBuildNumber(yaml, `${tag}:mobile/pubspec.yaml`);
  if (build > maxPrevious) {
    maxPrevious = build;
    maxTag = tag;
  }
}

if (maxPrevious > 0 && current <= maxPrevious) {
  throw new Error(
    `Production Android build number must increase: current=${current}, previous maximum=${maxPrevious} (${maxTag})`,
  );
}

console.log(
  maxPrevious > 0
    ? `Production Android build number is monotonic: ${current} > ${maxPrevious} (${maxTag})`
    : `No previous production tags with Android build numbers found; current=${current}`,
);

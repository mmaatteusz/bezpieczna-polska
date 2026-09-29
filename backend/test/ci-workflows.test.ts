import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';

const production=readFileSync('../.github/workflows/production-release.yml','utf8');
const regression=readFileSync('../.github/workflows/regression-preview.yml','utf8');
const preview=readFileSync('../.github/workflows/preview-apk.yml','utf8');
const installable=readFileSync('../.github/workflows/test-apk.yml','utf8');
const updateCompat=readFileSync('../.github/workflows/android-update-compat.yml','utf8');
const ios=readFileSync('../.github/workflows/ios-ci.yml','utf8');
const runtimeAudit=readFileSync('../.github/workflows/audit-production-runtime.yml','utf8');
const probeDockerfile=readFileSync('../backend/Dockerfile.probe','utf8');
const manualAndroid=readFileSync('../.github/workflows/build.yml','utf8');

function stepBlock(yaml:string,name:string){
  const marker=`      - name: ${name}`;
  const start=yaml.indexOf(marker);
  assert.notEqual(start,-1,`missing workflow step: ${name}`);
  const next=yaml.indexOf('\n      - ',start+marker.length);
  return yaml.slice(start,next<0?yaml.length:next);
}

test('main release has a non-advisory hard live NEPTUN contract gate',()=>{
  const step=stepBlock(production,'Required live NEPTUN contract check');
  assert.match(step,/node scripts\/live-neptun\.mjs/);
  assert.doesNotMatch(step,/continue-on-error\s*:\s*true/);
});

test('external live source checks run before preview signing can block the job',()=>{
  const signing=regression.indexOf('      - name: Configure stable preview signing');
  assert.ok(signing>0);
  for(const name of ["Live RSO contract check","Live WCZK contract check","Live IMGW warnings contract check","Live PAA communication contract check","Live CERT and CSIRT GOV contract check","Live Straż Graniczna contract check"]){
    const source=regression.indexOf(`      - name: ${name}`);
    assert.ok(source>=0,`missing ${name}`);
    assert.ok(source<signing,`${name} must run before signing`);
  }
});

test('manual Android preview uses preview environment in Gradle and Dart',()=>{
  assert.match(manualAndroid,/BP_ENV:\s*preview/);
  assert.match(manualAndroid,/--dart-define=APP_ENV=preview/);
  assert.match(manualAndroid,/--dart-define="API_BASE_URL=\$API_BASE_URL"/);
});

test('production Android artifact gate checks versionCode and arm64 ABI',()=>{
  assert.match(production,/versionCode='\$\{EXPECTED_CODE\}'/);
  assert.match(production,/native-code: 'arm64-v8a'/);
  assert.match(production,/Unexpected non-arm64 native libraries/);
});


test('runtime and app build workflows are provider-neutral',()=>{
  for(const [name,yaml] of [
    ['runtime audit',runtimeAudit],
    ['preview',preview],
    ['regression',regression],
    ['installable APK',installable],
    ['update compatibility',updateCompat],
    ['iOS',ios],
    ['manual Android',manualAndroid],
  ] as const){
    assert.doesNotMatch(yaml,/railway\.app/i,`${name} hardcodes Railway hostname`);
    assert.doesNotMatch(yaml,/railway-runtime-smoke/i,`${name} still uses Railway-specific smoke client`);
  }
  assert.doesNotMatch(probeDockerfile,/railway-runtime-smoke/i);
  assert.match(runtimeAudit,/vars\.PRODUCTION_API_BASE_URL/);
  assert.match(runtimeAudit,/scripts\/production-runtime-smoke\.mjs/);
  for(const yaml of [preview,regression,installable,updateCompat,ios,manualAndroid]){
    assert.match(yaml,/vars\.PREVIEW_API_BASE_URL\s*\|\|\s*vars\.PRODUCTION_API_BASE_URL/);
  }
});

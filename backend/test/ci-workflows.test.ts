import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';

const production=readFileSync('../.github/workflows/production-release.yml','utf8');
const regression=readFileSync('../.github/workflows/regression-preview.yml','utf8');
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

import {readFileSync} from 'node:fs';
import {publicHttpsUrl} from '../backend/dist/config.js';
const backend=JSON.parse(readFileSync(new URL('../backend/package.json',import.meta.url)));
const yaml=readFileSync(new URL('../mobile/pubspec.yaml',import.meta.url),'utf8');
const version=yaml.match(/^version:\s*([^+\s]+)\+(\d+)$/m);
if(!version||version[1]!==backend.version||version[2]!=='17')throw new Error('Mobile/backend version mismatch');
const dartVersion=readFileSync(new URL('../mobile/lib/app_version.dart',import.meta.url),'utf8');
if(!dartVersion.includes(`const appVersion = '${version[1]}';`))throw new Error('Displayed mobile version mismatch');
if(process.env.GITHUB_REF?.startsWith('refs/tags/')&&!new RegExp('^refs/tags/v'+version[1].replaceAll('.','\\.')+'-rc\\.[0-9]+$').test(process.env.GITHUB_REF))
 throw new Error('Release candidate tag does not match app version');
if(process.argv.includes('--production')){
 if(process.env.APP_ENV!=='production'||process.env.ENABLE_DEVELOPER_SETTINGS!=='false')throw new Error('Production build environment mismatch');
 const url=publicHttpsUrl(process.env.API_BASE_URL??'');
 const response=await fetch(new URL('/health',url),{redirect:'error',signal:AbortSignal.timeout(10000)});
 if(!response.ok)throw new Error('Production backend is unavailable');
 const health=await response.json();
 if(health.version!==version[1]||health.environment!=='production'||health.buildSha!==process.env.BACKEND_SHA)throw new Error('Production backend version/build SHA mismatch');
 const readyResponse=await fetch(new URL('/ready',url),{redirect:'error',signal:AbortSignal.timeout(10000)});
 if(!readyResponse.ok)throw new Error('Production backend database is not ready');
 const ready=await readyResponse.json();
 if(!ready.ready||ready.database!=='postgres'||!ready.postgis)throw new Error('Production PostGIS readiness mismatch');
}
console.log('Version/config validation PASS: '+version[1]);

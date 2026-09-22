import {writeFile,mkdir} from 'node:fs/promises';
import {ukraineAdapter,UA_API} from '../dist/ukraine-adapter.js';
import {fetchPublic} from '../dist/adapters.js';
import {UA_BOUNDARY_QUERY,parseUaBoundaries} from '../dist/ukraine-geography.js';
const path=process.argv[2]??'../output/ukraine-live.json';
const report={checkedAt:new Date().toISOString(),source:UA_API,contract:'UkraineAlarm API v3',liveAuthenticated:'NOT_CONFIGURED_UA_API_KEY_MISSING'};
let failed=false;
try{
 if(process.env.UKRAINE_ALARM_API_KEY){const b=await ukraineAdapter.sync({now:new Date(),fetchText:fetchPublic});report.liveAuthenticated='PASS';report.eventCount=b.events.length;report.coverage=b.coverage;report.regions=b.uaMetadata.regions.length;}
 else {
  // Confirm the official service is reachable; never copy a web client's key.
  const r=await fetch(UA_API+'/alerts',{redirect:'error',signal:AbortSignal.timeout(20000)});report.unauthenticatedStatus=r.status;
  if(![401,403].includes(r.status))throw new Error('UA_UNAUTHENTICATED_CONTRACT_UNEXPECTED');
 }
}catch(e){report.liveAuthenticated=process.env.UKRAINE_ALARM_API_KEY?'FAIL':'NOT_CONFIGURED_UA_API_KEY_MISSING';report.error=String(e.message).slice(0,200);failed=true;}
try{const data=parseUaBoundaries(JSON.parse(await fetchPublic(UA_BOUNDARY_QUERY)));report.administrativeBoundaries={status:'PASS',count:data.length,source:UA_BOUNDARY_QUERY,names:data.map(f=>f.properties)};}
catch(e){report.administrativeBoundaries={status:'UNAVAILABLE',error:String(e.message).slice(0,200)};}
await mkdir(new URL('.',new URL('file://'+process.cwd()+'/'+path)),{recursive:true});await writeFile(path,JSON.stringify(report,null,2));console.log(JSON.stringify(report,null,2));if(failed)process.exitCode=1;

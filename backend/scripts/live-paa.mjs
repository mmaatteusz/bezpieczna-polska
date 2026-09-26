import {writeFile,mkdir} from 'node:fs/promises';
import {dirname} from 'node:path';
import {paaAdapter,PAA_INDEX,PAA_MONITORING} from '../dist/paa-adapter.js';
import {paaMeasurementsAdapter,PAA_MEASUREMENTS_BASE} from '../dist/paa-measurements-adapter.js';
import {fetchPublic} from '../dist/adapters.js';

const out=process.argv[2]??'paa-live.json',now=new Date();
const communication=await paaAdapter.sync({now,fetchText:fetchPublic});
let measurements={state:'UNAVAILABLE',source:PAA_MEASUREMENTS_BASE,adapterVersion:paaMeasurementsAdapter.version,count:0,errorCode:null};
try{
 const batch=await paaMeasurementsAdapter.sync({now,fetchText:fetchPublic});
 measurements={state:'AVAILABLE',source:PAA_MEASUREMENTS_BASE,adapterVersion:paaMeasurementsAdapter.version,count:batch.radiationMeasurements?.length??0,errorCode:null};
}catch(error){
 const message=error instanceof Error?error.message:'SOURCE_SYNC_FAILED';
 measurements={...measurements,errorCode:/^[A-Z][A-Z0-9_]{2,100}$/.test(message)?message:'SOURCE_SYNC_FAILED'};
}
const report={
 retrievedAt:now.toISOString(),
 officialCommunicationSource:PAA_INDEX,
 officialMeasurementPortal:PAA_MONITORING,
 communication:{adapterVersion:paaAdapter.version,pagesFetched:communication.pagesFetched,complete:communication.complete,eventCount:communication.events.length,events:communication.events},
 measurements,
};
await mkdir(dirname(out),{recursive:true});
await writeFile(out,JSON.stringify(report,null,2));
console.log(JSON.stringify({eventCount:communication.events.length,pagesFetched:communication.pagesFetched,measurementState:measurements.state,measurementCount:measurements.count,measurementError:measurements.errorCode}));

import {writeFile,mkdir} from 'node:fs/promises';
import {dirname} from 'node:path';
import {paaAdapter,PAA_INDEX,PAA_MONITORING} from '../dist/paa-adapter.js';
import {fetchPublic} from '../dist/adapters.js';
const out=process.argv[2]??'paa-live.json',now=new Date();
const batch=await paaAdapter.sync({now,fetchText:fetchPublic});
const report={retrievedAt:now.toISOString(),officialCommunicationSource:PAA_INDEX,officialMeasurementPortal:PAA_MONITORING,measurementIntegration:'NOT_IMPLEMENTED_WAF_FORMAT_UNVERIFIED',adapterVersion:paaAdapter.version,pagesFetched:batch.pagesFetched,complete:batch.complete,eventCount:batch.events.length,events:batch.events};
await mkdir(dirname(out),{recursive:true});await writeFile(out,JSON.stringify(report,null,2));console.log(JSON.stringify({eventCount:report.eventCount,pagesFetched:report.pagesFetched,complete:false}));

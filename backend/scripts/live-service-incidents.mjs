import {writeFile,mkdir} from 'node:fs/promises';
import {dirname} from 'node:path';
import {policeAdapter,pspIncidentsAdapter,POLICE_RSS,PSP_INCIDENTS_INDEX} from '../dist/service-incidents-adapter.js';
import {fetchPublic} from '../dist/adapters.js';

const out=process.argv[2]??'service-incidents-live.json';
const now=new Date();
const [police,psp]=await Promise.all([
  policeAdapter.sync({now,fetchText:fetchPublic,previousEvents:[]}),
  pspIncidentsAdapter.sync({now,fetchText:fetchPublic,previousEvents:[]}),
]);
const report={
  checkedAt:now.toISOString(),
  police:{source:POLICE_RSS,adapterVersion:policeAdapter.version,pagesFetched:police.pagesFetched,complete:police.complete,coverage:police.coverage,eventCount:police.events.length,events:police.events},
  psp:{source:PSP_INCIDENTS_INDEX,adapterVersion:pspIncidentsAdapter.version,pagesFetched:psp.pagesFetched,complete:psp.complete,coverage:psp.coverage,eventCount:psp.events.length,events:psp.events},
};
await mkdir(dirname(out),{recursive:true});
await writeFile(out,JSON.stringify(report,null,2));
console.log(JSON.stringify({policeEvents:police.events.length,policePages:police.pagesFetched,pspEvents:psp.events.length,pspPages:psp.pagesFetched}));

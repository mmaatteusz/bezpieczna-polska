import {writeFile,mkdir} from 'node:fs/promises';
import {dirname} from 'node:path';
import {fetchPublic,rsoAdapter} from '../dist/adapters.js';

const out=process.argv[2]??'rso-live.json';
const now=new Date();
const batch=await rsoAdapter.sync({now,fetchText:fetchPublic});
const report={
  checkedAt:now.toISOString(),
  source:'https://komunikaty.tvp.pl/komunikatyxml/wszystkie/wszystkie/0?_format=xml',
  adapterVersion:rsoAdapter.version,
  complete:batch.complete,
  coverage:batch.coverage,
  eventCount:batch.events.length,
  events:batch.events,
};
await mkdir(dirname(out),{recursive:true});
await writeFile(out,JSON.stringify(report,null,2));
console.log(JSON.stringify({events:batch.events.length,complete:batch.complete,coverage:batch.coverage}));

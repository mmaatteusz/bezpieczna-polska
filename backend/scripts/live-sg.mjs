import {writeFile,mkdir} from 'node:fs/promises';
import {dirname} from 'node:path';
import {sgAdapter,SG_INDEX,SG_RSS_PAGE} from '../dist/sg-adapter.js';
import {fetchPublic} from '../dist/adapters.js';

const out=process.argv[2]??'sg-live.json';
const now=new Date();
const batch=await sgAdapter.sync({now,fetchText:fetchPublic,previousEvents:[]});
const report={
 checkedAt:now.toISOString(),
 officialNewsSource:SG_INDEX,
 officialRssPage:SG_RSS_PAGE,
 rssIntegration:'RSS_CHANNEL_LIST_EMPTY',
 adapterVersion:sgAdapter.version,
 pagesFetched:batch.pagesFetched,
 complete:batch.complete,
 coverage:batch.coverage,
 operationalEventCount:batch.events.length,
 events:batch.events
};
await mkdir(dirname(out),{recursive:true});
await writeFile(out,JSON.stringify(report,null,2));
console.log(JSON.stringify({pagesFetched:batch.pagesFetched,operationalEventCount:batch.events.length,rss:'RSS_CHANNEL_LIST_EMPTY'}));

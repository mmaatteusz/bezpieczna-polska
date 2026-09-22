import {writeFile,mkdir} from 'node:fs/promises';
import {dirname} from 'node:path';
import {certAdapter,CERT_FEED,CSIRT_GOV_RSS_PAGE,parseCsirtGovRssLanding} from '../dist/cyber-adapter.js';
import {fetchPublic} from '../dist/adapters.js';

const out=process.argv[2]??'cyber-live.json';
const now=new Date();
const cert=await certAdapter.sync({now,fetchText:fetchPublic});
if(!cert.events.length)throw new Error('EMPTY_CERT_BATCH');
const csirtLanding=await fetchPublic(CSIRT_GOV_RSS_PAGE);
const csirtChannels=parseCsirtGovRssLanding(csirtLanding);
if(csirtChannels.length)throw new Error('CSIRT_GOV_PUBLIC_CHANNELS_CHANGED');

const report={
 checkedAt:now.toISOString(),
 cert:{source:CERT_FEED,adapterVersion:certAdapter.version,eventCount:cert.events.length,complete:cert.complete,coverage:cert.coverage,events:cert.events},
 csirtGov:{source:CSIRT_GOV_RSS_PAGE,publicChannelCount:0,integration:'NOT_CONFIGURED_RSS_LIST_EMPTY'}
};
await mkdir(dirname(out),{recursive:true});
await writeFile(out,JSON.stringify(report,null,2));
console.log(JSON.stringify({certEvents:cert.events.length,csirtGovPublicChannels:0,csirtGov:'NOT_CONFIGURED_RSS_LIST_EMPTY'}));

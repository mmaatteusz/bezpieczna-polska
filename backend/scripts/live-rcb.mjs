import {mkdir,writeFile} from 'node:fs/promises';
import {Store,openDb} from '../dist/store.js';
import {ingest} from '../dist/adapters.js';
import {rcbAdapter} from '../dist/rcb-adapter.js';
import {buildApp} from '../dist/app.js';
const directory=process.argv[2];
if(!directory)throw new Error('Supply an output directory for the live observation');
const db=openDb(process.env.TEST_DATABASE_URL,':memory:'),store=new Store(db);
try{
 await store.init();await ingest(store,[rcbAdapter]);
 const source=(await store.health()).find(s=>s.id==='RCB');
 if(source?.state!=='HEALTHY')throw new Error(`RCB_LIVE_FAILED: ${source?.errorCode}`);
 const app=await buildApp(store);
 try{
  const status=(await app.inject('/status?regionId=04')).json();
  const examples=(await store.events()).filter(e=>e.sources.some(s=>s.id==='RCB')).slice(0,5).map(({id,title,publicationDate,regions,lifecycle,messageContext,geometry,sources})=>({id,title,publicationDate,regions,lifecycle,messageContext,geometry,sourceUrl:sources[0].url}));
  const report={observedAt:new Date().toISOString(),source,status,examples};
  await mkdir(directory,{recursive:true});await writeFile(`${directory}/rcb-live.json`,JSON.stringify(report,null,2)+'\n');
  console.log(JSON.stringify(report,null,2));
 }finally{await app.close();}
}finally{await db.close();}

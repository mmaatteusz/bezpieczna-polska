import {mkdir,writeFile} from 'node:fs/promises';
import {Store,openDb} from '../dist/store.js';
import {ingest,fetchPublic} from '../dist/adapters.js';
import {securityLevelsAdapter} from '../dist/security-level-adapter.js';
import {buildApp} from '../dist/app.js';
const out=process.argv[2]??'../docs/validation/levels';await mkdir(out,{recursive:true});
const db=openDb(process.env.TEST_DATABASE_URL,':memory:'),store=new Store(db);await store.init();
let app;
try{
 await ingest(store,[securityLevelsAdapter],async url=>{process.stdout.write(`Reading ${url}\n`);return fetchPublic(url);});
 app=await buildApp(store);const health=(await store.health()).find(h=>h.id==='LEVELS');
 const status=(await app.inject('/status?regionId=04')).json();
 await writeFile(`${out}/levels-live.json`,JSON.stringify({observedAt:new Date().toISOString(),database:db.kind,health,status},null,2));
 if(health.state!=='HEALTHY')throw new Error(health.errorCode);
 console.log(JSON.stringify({health,levels:status.poland.securityLevels},null,2));
}finally{await app?.close();await db.close();}

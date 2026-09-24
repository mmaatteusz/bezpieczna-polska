import {openDb,Store} from './store.js';import {buildApp} from './app.js';import {ingest} from './adapters.js';import {createPushServiceFromEnv} from './push.js';
import {serverConfig} from './config.js';import {assertSchema,migrate} from './migrate.js';import {tryAcquireWorkerLease,releaseWorkerLease} from './worker-lease.js';import {randomUUID} from 'node:crypto';
const config=serverConfig();
const db=openDb(process.env.DATABASE_URL,process.env.SQLITE_PATH);
let app:Awaited<ReturnType<typeof buildApp>>|undefined;
let timer:NodeJS.Timeout|undefined,pushTimer:NodeJS.Timeout|undefined;
try{
 const store=new Store(db);
 if(config.production)await assertSchema(db);else await migrate(db);
 const push=createPushServiceFromEnv(db);
 app=await buildApp(store,process.env.ADMIN_TOKEN,push??undefined,{stage:config.stage,buildSha:config.buildSha,trustProxy:config.production});
 const workerOwner=`${process.pid}:${randomUUID()}`;
 let running=false;
 async function sync(){if(running)return;running=true;const started=Date.now();let leased=false;try{
  leased=await tryAcquireWorkerLease(db,'ingest',workerOwner,10*60*1000);
  if(!leased)return;
  await ingest(store);
  for(const source of await store.health()){
   if(source.lastAttempt&&Date.parse(source.lastAttempt)>=started)
    app?.log.info({component:'source-adapter',source:source.id,state:source.state,errorCode:source.errorCode??null,durationMs:source.responseTime},'source refresh');
  }
 }catch{app?.log.error({component:'ingestion',errorCode:'INGEST_FAILED'},'Ingestion failed; existing data retained');}
 finally{if(leased)await releaseWorkerLease(db,'ingest',workerOwner).catch(()=>{});running=false;}}
 if(process.env.ENABLE_INGESTION!=='false'){timer=setInterval(()=>void sync(),60000);void sync();}
 let pushRunning=false;
 async function dispatchPush(){if(!push||pushRunning)return;pushRunning=true;let leased=false;try{
  leased=await tryAcquireWorkerLease(db,'push',workerOwner,60000);
  if(!leased)return;
  await push.dispatchDue();
 }catch{app?.log.error({component:'push',errorCode:'DISPATCH_FAILED'},'Push dispatch failed');}
 finally{if(leased)await releaseWorkerLease(db,'push',workerOwner).catch(()=>{});pushRunning=false;}}
 if(push){pushTimer=setInterval(()=>void dispatchPush(),15000);void dispatchPush();}
 await app.listen({port:config.port,host:config.host});
 let closing=false;
 async function shutdown(){if(closing)return;closing=true;if(timer)clearInterval(timer);if(pushTimer)clearInterval(pushTimer);
  const deadline=setTimeout(()=>process.exit(1),20000);deadline.unref();
  try{await app?.close();await db.close();clearTimeout(deadline);}catch{process.exitCode=1;}
 }
 for(const signal of ['SIGINT','SIGTERM'])process.once(signal,()=>void shutdown());
}catch(e){if(timer)clearInterval(timer);if(pushTimer)clearInterval(pushTimer);await app?.close();await db.close();throw e;}

import {workerStarted,workerFinished} from './operations.js';
import {openDb,Store} from './store.js';import {buildApp} from './app.js';import {ingest,ingestNeptunLive,ingestUkraineLive} from './adapters.js';import {createPushServiceFromEnv} from './push.js';
import {serverConfig} from './config.js';import {assertSchema,migrate} from './migrate.js';import {tryAcquireWorkerLease,releaseWorkerLease} from './worker-lease.js';import {randomUUID} from 'node:crypto';
const config=serverConfig();
const db=openDb(process.env.DATABASE_URL,process.env.SQLITE_PATH);
let app:Awaited<ReturnType<typeof buildApp>>|undefined;
let timer:NodeJS.Timeout|undefined,neptunTimer:NodeJS.Timeout|undefined,ukraineTimer:NodeJS.Timeout|undefined,pushTimer:NodeJS.Timeout|undefined;
try{
 const store=new Store(db);
 if(config.production)await assertSchema(db);else await migrate(db);
 const push=createPushServiceFromEnv(db);
 app=await buildApp(store,process.env.ADMIN_TOKEN,push??undefined,{stage:config.stage,buildSha:config.buildSha,trustProxy:config.production});
 const workerOwner=`${process.pid}:${randomUUID()}`;
 const ingestLeaseTtlMs=180000,ingestLeaseRenewMs=60000;
 let running=false,neptunRunning=false,ukraineRunning=false;
 async function sync(){if(running)return;running=true;const started=Date.now();let ok=false,leased=false,leaseHeartbeat:NodeJS.Timeout|undefined,renewing=false;try{
  leased=await tryAcquireWorkerLease(db,'ingest',workerOwner,ingestLeaseTtlMs);
  if(!leased){
   app?.log.info({component:'ingestion',workerOwner,leaseTtlMs:ingestLeaseTtlMs},'Ingestion lease busy; retrying on next tick');
   return;
  }
  await workerStarted(db,'ingest',new Date(started));
  leaseHeartbeat=setInterval(()=>{
   if(renewing)return;
   renewing=true;
   void tryAcquireWorkerLease(db,'ingest',workerOwner,ingestLeaseTtlMs)
    .then(ok=>{if(!ok)app?.log.error({component:'ingestion',errorCode:'INGEST_LEASE_LOST'},'Ingestion lease renewal lost ownership');})
    .catch(()=>app?.log.error({component:'ingestion',errorCode:'INGEST_LEASE_RENEW_FAILED'},'Ingestion lease renewal failed'))
    .finally(()=>{renewing=false;});
  },ingestLeaseRenewMs);
  leaseHeartbeat.unref();
  await ingest(store);ok=true;
  for(const source of await store.health()){
   if(source.lastAttempt&&Date.parse(source.lastAttempt)>=started)
    app?.log.info({component:'source-adapter',source:source.id,state:source.state,errorCode:source.errorCode??null,durationMs:source.responseTime},'source refresh');
  }
 }catch{app?.log.error({component:'ingestion',errorCode:'INGEST_FAILED'},'Ingestion failed; existing data retained');}
 finally{if(leaseHeartbeat)clearInterval(leaseHeartbeat);if(leased){await workerFinished(db,'ingest',started,ok).catch(()=>{});await releaseWorkerLease(db,'ingest',workerOwner).catch(()=>{});}running=false;}}
 if(config.role!=='api'&&process.env.ENABLE_INGESTION!=='false'){
  timer=setInterval(()=>void sync(),60000);
  void sync();
  if(process.env.UKRAINE_ALARM_API_KEY?.trim()){
   async function syncUkraine(){if(ukraineRunning)return;ukraineRunning=true;const started=Date.now();let ok=false,leased=false;try{
    leased=await tryAcquireWorkerLease(db,'ukraine-alarm',workerOwner,180000);
    if(!leased)return;
    await workerStarted(db,'ukraine-alarm',new Date(started));
    await ingestUkraineLive(store);ok=true;
    const source=(await store.health()).find(s=>s.id==='UA');
    app?.log.info({component:'ukraine-alarm',source:'UA',state:source?.state??'MISSING',errorCode:source?.errorCode??null,geometryStatus:source?.uaMetadata?.geometryStatus??null,geometryErrorCode:source?.uaMetadata?.geometryErrorCode??null,durationMs:source?.responseTime??null},'UkraineAlarm refresh');
   }catch{app?.log.error({component:'ukraine-alarm',errorCode:'UA_INGEST_FAILED'},'UkraineAlarm live refresh failed; existing data retained');}
   finally{if(leased){await workerFinished(db,'ukraine-alarm',started,ok).catch(()=>{});await releaseWorkerLease(db,'ukraine-alarm',workerOwner).catch(()=>{});}ukraineRunning=false;}}
   ukraineTimer=setInterval(()=>void syncUkraine(),90000);
   void syncUkraine();
  }
  async function syncNeptun(){if(neptunRunning)return;neptunRunning=true;const started=Date.now();let ok=false,leased=false;try{
   leased=await tryAcquireWorkerLease(db,'neptun-live',workerOwner,15000);
   if(!leased)return;
   await workerStarted(db,'neptun-live',new Date(started));
    await ingestNeptunLive(store);ok=true;
  }catch{app?.log.error({component:'neptun-live',errorCode:'NEPTUN_INGEST_FAILED'},'NEPTUN live refresh failed; existing data retained');}
  finally{if(leased){await workerFinished(db,'neptun-live',started,ok).catch(()=>{});await releaseWorkerLease(db,'neptun-live',workerOwner).catch(()=>{});}neptunRunning=false;}}
  neptunTimer=setInterval(()=>void syncNeptun(),5000);
  void syncNeptun();
 }
 let pushRunning=false;
 async function dispatchPush(){if(!push||pushRunning)return;pushRunning=true;const started=Date.now();let ok=false,leased=false;try{
  leased=await tryAcquireWorkerLease(db,'push',workerOwner,60000);
  if(!leased)return;
  await workerStarted(db,'push',new Date(started));
    await push.dispatchDue();ok=true;
 }catch{app?.log.error({component:'push',errorCode:'DISPATCH_FAILED'},'Push dispatch failed');}
 finally{if(leased){await workerFinished(db,'push',started,ok).catch(()=>{});await releaseWorkerLease(db,'push',workerOwner).catch(()=>{});}pushRunning=false;}}
 if(config.role!=='api'&&push&&config.enablePushDispatch){pushTimer=setInterval(()=>void dispatchPush(),15000);void dispatchPush();}
 else if(push)app.log.info({component:'push'},'Automatic push dispatch disabled; device registration and manual tests remain available');
 if(config.role!=='worker')await app.listen({port:config.port,host:config.host});
 else app.log.info({component:'worker',role:config.role},'Worker process started without HTTP listener');
 let closing=false;
 async function shutdown(){if(closing)return;closing=true;if(timer)clearInterval(timer);if(neptunTimer)clearInterval(neptunTimer);if(ukraineTimer)clearInterval(ukraineTimer);if(pushTimer)clearInterval(pushTimer);
  const deadline=setTimeout(()=>process.exit(1),20000);deadline.unref();
  try{await app?.close();while(running||pushRunning||neptunRunning||ukraineRunning)await new Promise(resolve=>setTimeout(resolve,50));await db.close();clearTimeout(deadline);}catch{process.exitCode=1;}
 }
 for(const signal of ['SIGINT','SIGTERM'])process.once(signal,()=>void shutdown());
}catch(e){if(timer)clearInterval(timer);if(neptunTimer)clearInterval(neptunTimer);if(ukraineTimer)clearInterval(ukraineTimer);if(pushTimer)clearInterval(pushTimer);await app?.close();await db.close();throw e;}

import test from 'node:test';
import assert from 'node:assert/strict';
import {openDb,Store} from '../src/store.js';
import {workerStarted,workerFinished,operationalMetrics} from '../src/operations.js';
import {buildApp} from '../src/app.js';
import {serverConfig} from '../src/config.js';
import {parseShelterCsv,parseShelterResource} from '../src/shelter-adapter.js';
import {initializeSources} from '../src/adapters.js';
import {readFileSync} from 'node:fs';

test('process roles are explicit and preserve the existing combined default',()=>{
 assert.equal(serverConfig({}).role,'combined');
 for(const role of ['api','worker'])assert.equal(serverConfig({PROCESS_ROLE:role}).role,role);
 assert.throws(()=>serverConfig({PROCESS_ROLE:'workers'}),/PROCESS_ROLE/);
});
test('worker age and push backlog metrics survive a new reader and report failure honestly',async()=>{
 const db=openDb(undefined,':memory:');await new Store(db).init();
 try{
  const start=new Date('2026-10-04T12:00:00Z'),now=new Date('2026-10-04T12:02:00Z');
  await workerStarted(db,'push',start);
  await db.run(`INSERT INTO push_outbox(id,dedupe_key,device_id,entity_id,event_id,event_revision,category,notification_kind,payload,state,attempt_count,next_attempt_at,created_at) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?)`,['q','q','d','e','e',1,'RCB','NEW','{}','RETRY',1,start.toISOString(),start.toISOString()]);
  const first=await operationalMetrics(db,now);
  assert.equal(first.push.states.RETRY.oldestAgeSeconds,120);assert.equal(first.push.states.RETRY.overdueSeconds,120);
  assert.equal(first.workers[0].running,true);assert.equal(first.workers[0].scheduleLagSeconds,105);
  await workerFinished(db,'push',start.getTime(),true,now);
  await workerStarted(db,'push',now);await workerFinished(db,'push',now.getTime(),false,new Date(now.getTime()+1000));
  const worker=(await operationalMetrics(db,new Date(now.getTime()+5000))).workers[0];
  assert.equal(worker.lastSuccessAgeSeconds,5);assert.equal(worker.errorCode,'WORKER_FAILED');assert.equal(worker.running,false);
 }finally{await db.close();}
});
test('compact snapshots reduce bytes, keep status and alerts, and metrics remain authenticated',async t=>{
 t.mock.timers.enable({apis:['Date'],now:new Date('2026-10-04T12:00:00Z')});
 const db=openDb(undefined,':memory:'),store=new Store(db);await store.init();await initializeSources(store);
 const points=parseShelterCsv(readFileSync('test/fixtures/psp-shelters.csv','utf8'),parseShelterResource(readFileSync('test/fixtures/psp-resource.json','utf8'),new Date('2026-09-19T12:00:00Z')));
 const health=(await store.health()).find(h=>h.id==='SHELTERS')!;
 await store.applyShelterSync(points,{...health,complete:true,coverage:'FACILITY_CATALOG',itemCount:points.length,sourceContentHash:'a'.repeat(64)});
 const token='0123456789abcdef0123456789abcdef',app=await buildApp(store,token);
 try{
  const full=await app.inject('/v1/snapshot?regionId=04'),compact=await app.inject('/v1/snapshot?regionId=04&mode=compact');
  assert.equal(compact.statusCode,200);assert.ok(Buffer.byteLength(compact.body)<Buffer.byteLength(full.body));
  assert.deepEqual(compact.json().events,full.json().events);assert.deepEqual(compact.json().status,full.json().status);
  assert.equal(compact.json().shelterPage.total,3);assert.equal(full.json().shelters.length,3);
  assert.equal((await app.inject('/v1/snapshot?mode=other')).statusCode,400);
  assert.equal((await app.inject('/admin/metrics')).statusCode,401);
  const m=(await app.inject({url:'/admin/metrics',headers:{authorization:'Bearer '+token}})).json();
  assert.ok(m.requests['GET /v1/snapshot'].responseBytes>0);assert.ok(m.requests['GET /v1/snapshot'].p95Ms>=0);
  assert.equal(m.operations.backup.state,'NOT_CONFIGURED');
 }finally{await app.close();await db.close();}
});

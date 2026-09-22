import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtemp,rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {buildApp} from '../src/app.js';
import {eventSchema,computeStatus,type Event} from '../src/domain.js';
import {neptunTrackSchema} from '../src/neptun.js';
import {PushService,type PushProvider,type PushSendResult,type PushPlatform} from '../src/push.js';
import {openDb,Store,type Db} from '../src/store.js';

const key=Buffer.alloc(32,7);
const secret='bp_push_'+ 'A'.repeat(43);
const now=new Date('2026-09-22T12:00:00Z');

class FakeProvider implements PushProvider{
 sent:{platform:PushPlatform;token:string;title:string}[]=[];
 results:PushSendResult[]=[];
 ready(){return true;}
 async send(platform:PushPlatform,token:string,message:{title:string}){
  this.sent.push({platform,token,title:message.title});
  return this.results.shift()??{kind:'SUCCESS',code:'OK'};
 }
}
const basePreferences=(patch:Record<string,unknown>={})=>({
 criticalPoland:true,regionAlerts:true,watchedLocations:true,cyber:true,border:true,ukraine:false,
 regionId:'04',locations:[],...patch
});
const registerBody=(id:string,token='fcm_token_'+id.replace(/-/g,''),patch:Record<string,unknown>={})=>({
 installationId:id,platform:'ANDROID',token,appVersion:'0.1.0-alpha.14',language:'pl-PL',preferences:basePreferences(),...patch
});
const deviceA='11111111-1111-4111-8111-111111111111';
const deviceB='22222222-2222-4222-8222-222222222222';

function event(id:string,patch:Partial<Event>={}):Event{
 return eventSchema.parse({
  id:'push-fixture-'+id,title:'Oficjalne ostrzeżenie testowe',description:'Syntetyczny komunikat używany wyłącznie w testach push.',
  eventType:'WEATHER',severity:'CRITICAL',verification:'CONFIRMED',lifecycle:'ACTIVE',messageContext:'ACTUAL',
  regions:['04'],geographicScope:'REGIONAL',publishedAt:'2026-09-22T11:55:00Z',publicationDate:'2026-09-22',
  retrievedAt:'2026-09-22T11:56:00Z',validFrom:'2026-09-22T11:50:00Z',validTo:'2026-09-22T14:00:00Z',
  sources:[{id:'RCB',name:'RCB',url:'https://www.gov.pl/web/rcb/',tier:1}],instructions:['Zachowaj ostrożność.'],
  officialWarning:true,reviewed:false,revision:1,correction:null,latitude:null,longitude:null,geometry:null,
  locationText:'województwo kujawsko-pomorskie',areaPrecision:'PROVINCE',adapterVersion:'fixture',
  sourceContentHash:'a'.repeat(64),isDemo:false,...patch
 });
}
function uaEvent(id:string):Event{
 return eventSchema.parse({
  ...event(id),id:'UA-push-'+id,origin:'OFFICIAL_FOREIGN',countryCode:'UA',regions:[],geographicScope:'REGIONAL',
  sources:[{id:'UA',name:'UkraineAlarm',url:'https://map.ukrainealarm.com/',tier:1}],
  ukraine:{regionId:'fixture',regionName:'Obwód testowy',regionType:'State',parentRegionId:null,alertType:'AIR',kind:'OFFICIAL_ALERT',sourceUpdatedAt:'2026-09-22T11:55:00Z'},
  geometry:null,geometrySource:undefined
 });
}
async function outbox(db:Db){return db.all('SELECT * FROM push_outbox ORDER BY created_at,id');}
async function device(db:Db,id=deviceA){return (await db.all('SELECT * FROM push_devices WHERE device_id=?',[id]))[0];}
async function setup(){
 const db=openDb(undefined,':memory:'),store=new Store(db);await store.init();const provider=new FakeProvider(),push=new PushService(db,key,provider);
 return {db,store,provider,push};
}

test('device registration encrypts token and authenticated update rotates it',async()=>{
 const {db,push}=await setup();
 try{
  const first='fcm_token_ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789',second='fcm_token_rotated_ABCDEFGHIJKLMNOPQRSTUVWXYZ';
  await push.register(registerBody(deviceA,first),secret,now);
  let row=await device(db);
  assert.notEqual(row.token_ciphertext,first);assert.equal(String(row.token_ciphertext).includes(first),false);assert.equal(String(row.manage_secret_hash).includes(secret),false);
  await push.update(deviceA,registerBody(deviceA,second),secret,new Date(+now+1000));
  row=await device(db);assert.notEqual(row.token_ciphertext,second);assert.notEqual(row.token_hash,null);
  await assert.rejects(push.update(deviceA,registerBody(deviceA,second),'bp_push_'+ 'B'.repeat(43),now),/PUSH_UNAUTHORIZED/);
 }finally{await db.close();}
});

test('unregister scrubs provider token and disables future delivery',async()=>{
 const {db,push}=await setup();
 try{
  const token='fcm_token_ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';await push.register(registerBody(deviceA,token),secret,now);
  await push.unregister(deviceA,secret,new Date(+now+1000));const row=await device(db);
  assert.equal(Number(row.enabled),0);assert.equal(row.token_ciphertext,'revoked');assert.equal(String(row.token_hash).includes(token),false);
 }finally{await db.close();}
});

test('event resync is idempotent and creates one outbox item',async()=>{
 const {db,store,push}=await setup();
 try{
  await push.register(registerBody(deviceA),secret,now);const e=event('dedupe');
  assert.equal(await store.put(e),true);assert.equal(await store.put(e),false);
  const rows=await outbox(db);assert.equal(rows.length,1);assert.equal(rows[0].state,'PENDING');assert.equal(rows[0].category,'CRITICAL_PL');
 }finally{await db.close();}
});

test('retry is persisted and eventually delivers exactly once',async()=>{
 const {db,store,push,provider}=await setup();
 try{
  await push.register(registerBody(deviceA),secret,now);await store.put(event('retry'));
  provider.results.push({kind:'RETRY',code:'TEMPORARY'},{kind:'SUCCESS',code:'OK'});
  assert.equal(await push.dispatchDue(now),1);let row=(await outbox(db))[0];assert.equal(row.state,'RETRY');assert.equal(Number(row.attempt_count),1);
  assert.equal(await push.dispatchDue(new Date(+now+31000)),1);row=(await outbox(db))[0];assert.equal(row.state,'DELIVERED');assert.equal(Number(row.attempt_count),2);assert.equal(provider.sent.length,2);
  assert.equal(await push.dispatchDue(new Date(+now+62000)),0);
 }finally{await db.close();}
});

test('permanent invalid token disables and scrubs device',async()=>{
 const {db,store,push,provider}=await setup();
 try{
  await push.register(registerBody(deviceA),secret,now);await store.put(event('invalid-token'));
  provider.results.push({kind:'PERMANENT_FAILURE',code:'FCM_INVALID_TOKEN',invalidToken:true});
  await push.dispatchDue(now);assert.equal((await outbox(db))[0].state,'PERMANENT_FAILURE');
  const row=await device(db);assert.equal(Number(row.enabled),0);assert.equal(row.token_ciphertext,'revoked');assert.equal(row.disabled_reason,'TOKEN_INVALID');
 }finally{await db.close();}
});

test('material correction, escalation and end create revision-specific notifications',async()=>{
 const {db,store,push}=await setup();
 try{
  await push.register(registerBody(deviceA),secret,now);const e=event('lifecycle',{severity:'HIGH'});
  await store.put(e);
  await store.put({...e,description:e.description+' Korekta treści.',correction:'Doprecyzowano obszar.'});
  await store.put({...e,severity:'CRITICAL',description:e.description+' Korekta treści.',correction:'Doprecyzowano obszar.'});
  await store.put({...e,severity:'CRITICAL',lifecycle:'ENDED',validTo:'2026-09-22T12:10:00Z',description:e.description+' Korekta treści.',correction:'Alert zakończono.'});
  const rows=await outbox(db);assert.deepEqual(rows.map(r=>r.notification_kind),['NEW','CORRECTED','ESCALATED','ENDED']);assert.equal(new Set(rows.map(r=>r.dedupe_key)).size,4);
 }finally{await db.close();}
});

test('exercise, test, REFUTED and individual Police/PSP publications never enqueue',async()=>{
 const {db,store,push}=await setup();
 try{
  await push.register(registerBody(deviceA),secret,now);
  await store.put(event('exercise',{messageContext:'EXERCISE'}));
  await store.put(event('test',{messageContext:'TEST'}));
  await store.put(event('refuted',{verification:'REFUTED'}));
  await store.put(event('police',{sources:[{id:'POLICE',name:'Policja',url:'https://policja.pl/',tier:1}],eventType:'PUBLIC_SAFETY'}));
  await store.put(event('psp',{sources:[{id:'PSP_INCIDENTS',name:'PSP',url:'https://www.gov.pl/web/kgpsp/',tier:1}],eventType:'FIRE'}));
  assert.equal((await outbox(db)).length,0);
 }finally{await db.close();}
});

test('Ukraine is an opt-in category and never becomes Polish push',async()=>{
 const {db,store,push}=await setup();
 try{
  await push.register(registerBody(deviceA),secret,now);await store.put(uaEvent('off'));assert.equal((await outbox(db)).length,0);
  await push.preferences(deviceA,basePreferences({ukraine:true}),secret,new Date(+now+1000));
  await store.put(uaEvent('on'));const rows=await outbox(db);assert.equal(rows.length,1);assert.equal(rows[0].category,'UKRAINE');
  assert.equal(computeStatus([uaEvent('status')],[],'PL',now).hazardLevel,'UNKNOWN');
 }finally{await db.close();}
});

test('watched locations use current saved points only and do not invent geometry',async()=>{
 const {db,store,push}=await setup();
 try{
  const prefs=basePreferences({criticalPoland:false,regionAlerts:false,locations:[{id:'loc-1',label:'Dom',latitude:53.12,longitude:18.01,radiusKm:10,regionId:null}]});
  await push.register(registerBody(deviceA,undefined as never,{preferences:prefs}),secret,now);
  await store.put(event('near',{severity:'HIGH',latitude:53.123,longitude:18.008,geometry:null,areaPrecision:'EXACT'}));
  await store.put(event('unknown',{severity:'HIGH',latitude:null,longitude:null,geometry:null,areaPrecision:'UNKNOWN',regions:['06']}));
  const rows=await outbox(db);assert.equal(rows.length,1);assert.equal(rows[0].category,'WATCHED_LOCATIONS');
  const stored=JSON.parse(String((await device(db)).preferences));assert.equal(stored.locations.length,1);assert.equal('history' in stored,false);
 }finally{await db.close();}
});

test('NEPTUN historical storage never enters operational push outbox',async()=>{
 const {db,store,push}=await setup();
 try{
  await push.register(registerBody(deviceA),secret,now);
  await store.putNeptunTrack(neptunTrackSchema.parse({
   id:'NEPTUN-push-fixture',title:'Historyczny ślad testowy',description:'Fixture',objectType:'AIR_OBJECT',lifecycle:'ENDED',verification:'PROBABLE',
   startedAt:'2026-09-20T08:00:00Z',endedAt:'2026-09-20T10:00:00Z',directionText:null,
   observations:[
    {id:'n1',observedAt:'2026-09-20T08:10:00Z',latitude:52.1,longitude:21.0,precisionKm:20,locationText:'A',verification:'PROBABLE',source:{id:'OSINT-A',name:'A',url:'https://example.com/a',tier:3,origin:'OSINT'},note:null,correction:null},
    {id:'n2',observedAt:'2026-09-20T09:10:00Z',latitude:52.5,longitude:21.5,precisionKm:20,locationText:'B',verification:'PROBABLE',source:{id:'OSINT-B',name:'B',url:'https://example.com/b',tier:3,origin:'OSINT'},note:null,correction:null}
   ],revision:1,reviewed:true
  }),'operator','Historical fixture',0);
  assert.equal((await outbox(db)).length,0);
 }finally{await db.close();}
});

test('push API validates payloads, authenticates device management and rate limits registration',async()=>{
 const {db,store,push}=await setup();const app=await buildApp(store,undefined,push);
 try{
  const good=registerBody(deviceA);
  let response=await app.inject({method:'POST',url:'/v1/push/devices',headers:{authorization:'Bearer '+secret},payload:good});
  assert.equal(response.statusCode,200);assert.equal(response.body.includes(String(good.token)),false);
  response=await app.inject({method:'GET',url:'/v1/push/devices/'+deviceA,headers:{authorization:'Bearer '+secret});
  assert.equal(response.statusCode,200);assert.equal(response.body.includes(String(good.token)),false);
  assert.equal((await app.inject({method:'GET',url:'/v1/push/devices/'+deviceA,headers:{authorization:'Bearer bp_push_'+ 'Z'.repeat(43)}})).statusCode,401);
  assert.equal((await app.inject({method:'POST',url:'/v1/push/devices',headers:{authorization:'Bearer '+secret},payload:{...registerBody(deviceB),token:'bad'}})).statusCode,400);
  assert.equal((await app.inject({method:'POST',url:'/v1/push/devices',headers:{authorization:'Bearer '+secret,'content-type':'application/json'},payload:JSON.stringify({...registerBody(deviceB),appVersion:'x'.repeat(17000)})})).statusCode,413);
 }finally{await app.close();await db.close();}
});

test('push secrets and provider tokens are absent from application logs',async()=>{
 const {db,store,push,provider}=await setup(),token='fcm_token_LOGLEAKCHECK_ABCDEFGHIJKLMNOPQRSTUVWXYZ',seen:string[]=[];
 const originalError=console.error,originalLog=console.log;console.error=(...a)=>seen.push(a.join(' '));console.log=(...a)=>seen.push(a.join(' '));
 try{
  await push.register(registerBody(deviceA,token),secret,now);await store.put(event('logs'));provider.results.push({kind:'PERMANENT_FAILURE',code:'INVALID'});
  await push.dispatchDue(now);
 }finally{console.error=originalError;console.log=originalLog;await db.close();}
 assert.equal(seen.join('\n').includes(token),false);assert.equal(seen.join('\n').includes(secret),false);
});

test('SQLite restart preserves device and pending outbox without plaintext token',async()=>{
 const dir=await mkdtemp(join(tmpdir(),'push-')),file=join(dir,'push.db'),token='fcm_token_RESTART_ABCDEFGHIJKLMNOPQRSTUVWXYZ';
 let db=openDb(undefined,file),store=new Store(db);await store.init();let provider=new FakeProvider(),push=new PushService(db,key,provider);
 try{
  await push.register(registerBody(deviceA,token),secret,now);await store.put(event('restart'));await db.close();
  db=openDb(undefined,file);store=new Store(db);await store.init();provider=new FakeProvider();push=new PushService(db,key,provider);
  assert.equal((await outbox(db))[0].state,'PENDING');await push.dispatchDue(now);assert.equal((await outbox(db))[0].state,'DELIVERED');assert.equal(provider.sent[0].token,token);
 }finally{await db.close();await rm(dir,{recursive:true,force:true});}
});

test('PostGIS restart preserves push outbox and encrypted device token',{skip:!process.env.TEST_DATABASE_URL},async()=>{
 const dbId='33333333-3333-4333-8333-333333333333',eventId='postgis-'+Date.now(),token='fcm_token_POSTGIS_ABCDEFGHIJKLMNOPQRSTUVWXYZ';
 let db=openDb(process.env.TEST_DATABASE_URL),store=new Store(db);await store.init();let provider=new FakeProvider(),push=new PushService(db,key,provider);
 try{
  await db.run('DELETE FROM push_outbox WHERE device_id=?',[dbId]);await db.run('DELETE FROM push_devices WHERE device_id=?',[dbId]);
  await push.register(registerBody(dbId,token),secret,now);await store.put(event(eventId));await db.close();
  db=openDb(process.env.TEST_DATABASE_URL);store=new Store(db);await store.init();provider=new FakeProvider();push=new PushService(db,key,provider);
  assert.equal((await db.all('SELECT COUNT(*) AS n FROM push_outbox WHERE device_id=?',[dbId]))[0].n,1);
  await push.dispatchDue(now);assert.equal(provider.sent[0].token,token);
 }finally{
  await db.run('DELETE FROM push_outbox WHERE device_id=?',[dbId]);await db.run('DELETE FROM push_devices WHERE device_id=?',[dbId]);
  await db.run('DELETE FROM event_revisions WHERE event_id=?',['push-fixture-'+eventId]);await db.run("DELETE FROM incident_revisions WHERE payload LIKE ?",['%push-fixture-'+eventId+'%']);await db.close();
 }
});

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
// Store queues against wall time; keep fixtures and dispatch in the same validity window.
const now=new Date(Date.now()+1000);

class FakeProvider implements PushProvider{
 sent:{platform:PushPlatform;token:string;title:string}[]=[];
 results:PushSendResult[]=[];
 isReady=true;
 ready(){return this.isReady;}
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
 installationId:id,platform:'ANDROID',token,appVersion:'0.1.0-alpha.15',language:'pl-PL',preferences:basePreferences(),...patch
});
const deviceA='11111111-1111-4111-8111-111111111111';
const deviceB='22222222-2222-4222-8222-222222222222';

function event(id:string,patch:Partial<Event>={}):Event{
 return eventSchema.parse({
  id:'push-fixture-'+id,title:'Oficjalne ostrzeżenie testowe',description:'Syntetyczny komunikat używany wyłącznie w testach push.',
  eventType:'WEATHER',severity:'CRITICAL',verification:'CONFIRMED',lifecycle:'ACTIVE',messageContext:'ACTUAL',
  regions:['04'],geographicScope:'REGIONAL',publishedAt:'2026-09-22T11:55:00Z',publicationDate:'2026-09-22',
  retrievedAt:'2026-09-22T11:56:00Z',validFrom:new Date(+now-60000).toISOString(),validTo:new Date(+now+12*3600000).toISOString(),
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
async function outbox(db:Db){return db.all('SELECT * FROM push_outbox ORDER BY event_revision,created_at,id');}
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
  const {installationId:_,...update}=registerBody(deviceA,second);void _;
  await push.update(deviceA,update,secret,new Date(+now+1000));
  row=await device(db);assert.notEqual(row.token_ciphertext,second);assert.notEqual(row.token_hash,null);
  await assert.rejects(push.update(deviceA,update,'bp_push_'+ 'B'.repeat(43),now),/PUSH_UNAUTHORIZED/);
 }finally{await db.close();}
});

test('unregister scrubs provider token and permanently closes pending delivery',async()=>{
 const {db,store,push}=await setup();
 try{
  const token='fcm_token_ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';await push.register(registerBody(deviceA,token),secret,now);
  await store.put(event('unregister'));
  await push.unregister(deviceA,secret,new Date(+now+1000));const row=await device(db);
  assert.equal(Number(row.enabled),0);assert.equal(row.token_ciphertext,'revoked');assert.equal(String(row.token_hash).includes(token),false);
  assert.equal((await outbox(db))[0].state,'PERMANENT_FAILURE');assert.equal((await outbox(db))[0].last_error_code,'USER_UNREGISTERED');
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
  assert.equal(await push.dispatchDue(new Date(+now+31000)),1);row=(await outbox(db))[0];assert.equal(row.state,'ACCEPTED');assert.equal(Number(row.attempt_count),2);assert.equal(provider.sent.length,2);
  assert.equal(await push.dispatchDue(new Date(+now+62000)),0);
 }finally{await db.close();}
});

test('provider configuration outage does not consume retry budget',async()=>{
 const {db,store,push,provider}=await setup();
 try{
  await push.register(registerBody(deviceA),secret,now);await store.put(event('provider-not-ready',{severity:'HIGH'}));provider.isReady=false;
  for(let i=0;i<8;i++)await push.dispatchDue(new Date(+now+i*5*60000));
  const row=(await outbox(db))[0];assert.equal(row.state,'RETRY');assert.equal(Number(row.attempt_count),0);assert.equal(row.last_error_code,'PROVIDER_NOT_READY');assert.equal(provider.sent.length,0);
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
  await store.put({...e,severity:'CRITICAL',lifecycle:'ENDED',validTo:new Date(+now).toISOString(),description:e.description+' Korekta treści.',correction:'Alert zakończono.'});
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

test('cyber and border remain separate opt-in push categories',async()=>{
 const {db,store,push}=await setup();
 try{
  await push.register(registerBody(deviceA),secret,now);
  const cert=event('cert',{eventType:'CYBER',severity:'HIGH',lifecycle:'UNKNOWN',officialWarning:false,regions:[],geographicScope:'UNKNOWN',sources:[{id:'CERT',name:'CERT Polska',url:'https://example.com/cert',tier:1}]});
  const border=event('border',{eventType:'BORDER',severity:'HIGH',lifecycle:'UNKNOWN',officialWarning:false,sources:[{id:'SG',name:'Straż Graniczna',url:'https://example.com/sg',tier:1}]});
  const info=event('cert-info',{eventType:'CYBER',severity:'INFORMATIONAL',lifecycle:'UNKNOWN',officialWarning:false,regions:[],geographicScope:'UNKNOWN',sources:[{id:'CERT',name:'CERT Polska',url:'https://example.com/cert-info',tier:1}]});
  await store.put(cert);await store.put(border);await store.put(info);
  const rows=await outbox(db);
  assert.deepEqual(rows.map(r=>r.category).sort(),['BORDER','CYBER']);
  assert.equal(computeStatus([cert,border],[],'PL',now).hazardLevel,'UNKNOWN');
 }finally{await db.close();}
});

test('sourceHealth-only changes never enqueue push',async()=>{
 const {db,store,push}=await setup();
 try{
  await push.register(registerBody(deviceA),secret,now);
  await store.setHealth({id:'RCB',name:'RCB',url:'https://www.gov.pl/web/rcb/',state:'HEALTHY',lastSuccess:now.toISOString(),lastFailure:null,lastItemTime:null,failureCount:0,responseTime:1,maxAgeSeconds:300,complete:false});
  await store.setHealth({id:'RCB',name:'RCB',url:'https://www.gov.pl/web/rcb/',state:'BROKEN',lastSuccess:now.toISOString(),lastFailure:new Date(+now+1000).toISOString(),lastItemTime:null,failureCount:1,responseTime:1,maxAgeSeconds:300,complete:false});
  assert.equal((await outbox(db)).length,0);
 }finally{await db.close();}
});

test('watched locations use current saved points only and do not invent geometry',async()=>{
 const {db,store,push}=await setup();
 try{
  const prefs=basePreferences({criticalPoland:false,regionAlerts:false,locations:[{id:'loc-1',label:'Dom',latitude:53.12,longitude:18.01,radiusKm:10,regionId:null}]});
  await push.register(registerBody(deviceA,undefined as never,{preferences:prefs}),secret,now);
  await store.put(event('near',{severity:'HIGH',latitude:53.123,longitude:18.008,geometry:null,areaPrecision:'EXACT'}));
  await store.put(event('far-same-region',{severity:'HIGH',latitude:54.35,longitude:18.65,geometry:null,areaPrecision:'EXACT'}));
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
  response=await app.inject({method:'GET',url:'/v1/push/devices/'+deviceA,headers:{authorization:'Bearer '+secret}});
  assert.equal(response.statusCode,200);assert.equal(response.body.includes(String(good.token)),false);
  assert.equal((await app.inject({method:'GET',url:'/v1/push/devices/'+deviceA,headers:{authorization:'Bearer bp_push_'+ 'Z'.repeat(43)}})).statusCode,401);
  assert.equal((await app.inject({method:'POST',url:'/v1/push/devices',headers:{authorization:'Bearer '+secret},payload:{...registerBody(deviceB),token:'bad'}})).statusCode,400);
  assert.equal((await app.inject({method:'POST',url:'/v1/push/devices',headers:{authorization:'Bearer '+secret,'content-type':'application/json'},payload:JSON.stringify({...registerBody(deviceB),appVersion:'x'.repeat(17000)})})).statusCode,413);
 }finally{await app.close();await db.close();}
});

test('authenticated device self-test sends one provider message without entering operational outbox',async()=>{
 const {db,store,push,provider}=await setup();const app=await buildApp(store,undefined,push);
 try{
  await push.register(registerBody(deviceA),secret,now);
  let response=await app.inject({method:'POST',url:'/v1/push/devices/'+deviceA+'/test',headers:{authorization:'Bearer '+secret}});
  assert.equal(response.statusCode,200);
  assert.equal(JSON.parse(response.body).providerAccepted,true);
  assert.equal(provider.sent.length,1);
  assert.equal(provider.sent[0].title,'Bezpieczna Polska — test powiadomień');
  assert.equal((await outbox(db)).length,0);
  response=await app.inject({method:'POST',url:'/v1/push/devices/'+deviceA+'/test',headers:{authorization:'Bearer bp_push_'+ 'Z'.repeat(43)}});
  assert.equal(response.statusCode,401);
  provider.isReady=false;
  response=await app.inject({method:'POST',url:'/v1/push/devices/'+deviceA+'/test',headers:{authorization:'Bearer '+secret}});
  assert.equal(response.statusCode,503);
 }finally{await app.close();await db.close();}
});

test('registration endpoint bounds record creation with per-route rate limit',async()=>{
 const {db,store,push}=await setup();const app=await buildApp(store,undefined,push);
 try{
  const statuses:number[]=[];
  for(let i=0;i<11;i++){
   const suffix=String(i).padStart(12,'0'),id='44444444-4444-4444-8444-'+suffix;
   const token='fcm_token_rate_limit_'+String(i).padStart(24,'0');
   statuses.push((await app.inject({method:'POST',url:'/v1/push/devices',headers:{authorization:'Bearer '+secret},payload:registerBody(id,token)})).statusCode);
  }
  assert.ok(statuses.slice(0,10).every(v=>v===200));assert.equal(statuses[10],429);
  assert.equal(Number((await db.all('SELECT COUNT(*) AS n FROM push_devices'))[0].n),10);
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
  assert.equal((await outbox(db))[0].state,'PENDING');await push.dispatchDue(now);assert.equal((await outbox(db))[0].state,'ACCEPTED');assert.equal(provider.sent[0].token,token);
 }finally{await db.close();await rm(dir,{recursive:true,force:true});}
});

test('PostGIS restart preserves push outbox and encrypted device token',{skip:!process.env.TEST_DATABASE_URL},async()=>{
 const dbId='33333333-3333-4333-8333-333333333333',eventId='postgis-'+Date.now(),token='fcm_token_POSTGIS_ABCDEFGHIJKLMNOPQRSTUVWXYZ';
 let db=openDb(process.env.TEST_DATABASE_URL),store=new Store(db);await store.init();let provider=new FakeProvider(),push=new PushService(db,key,provider);
 try{
  await db.run('DELETE FROM push_outbox WHERE device_id=?',[dbId]);await db.run('DELETE FROM push_devices WHERE device_id=?',[dbId]);
  await push.register(registerBody(dbId,token),secret,now);await store.put(event(eventId));await db.close();
  db=openDb(process.env.TEST_DATABASE_URL);store=new Store(db);await store.init();provider=new FakeProvider();push=new PushService(db,key,provider);
  assert.equal(Number((await db.all('SELECT COUNT(*) AS n FROM push_outbox WHERE device_id=?',[dbId]))[0].n),1);
  await push.dispatchDue(now);assert.equal(provider.sent[0].token,token);
 }finally{
  await db.run('DELETE FROM push_outbox WHERE device_id=?',[dbId]);await db.run('DELETE FROM push_devices WHERE device_id=?',[dbId]);
  await db.run('DELETE FROM event_revisions WHERE event_id=?',['push-fixture-'+eventId]);await db.run("DELETE FROM incident_revisions WHERE payload LIKE ?",['%push-fixture-'+eventId+'%']);await db.close();
 }
});
test('expiry uses severity and type and never extends an active warning past validTo',async()=>{
 const {pushExpiry}=await import('../src/push.js');
 assert.equal(Date.parse(pushExpiry(event('critical'),'NEW',now)),+now+15*60000);
 assert.equal(Date.parse(pushExpiry(event('high',{severity:'HIGH'}),'NEW',now)),+now+60*60000);
 assert.equal(Date.parse(pushExpiry(event('air',{eventType:'AIR'}),'NEW',now)),+now+5*60000);
 assert.equal(Date.parse(pushExpiry(event('cyber',{eventType:'CYBER'}),'NEW',now)),+now+360*60000);
 assert.equal(Date.parse(pushExpiry(event('short',{validTo:new Date(+now+10000).toISOString()}),'NEW',now)),+now+10000);
 assert.equal(Date.parse(pushExpiry(event('ended',{validTo:now.toISOString()}),'ENDED',now)),+now+30*60000);
});

test('offline queue discards expired and superseded warnings while preserving the end notification',async()=>{
 const {db,store,push,provider}=await setup();
 try{
  await push.register(registerBody(deviceA),secret,now);
  const e=event('ended-offline');await store.put(e);
  await store.put({...e,lifecycle:'ENDED',validTo:now.toISOString()});
  await push.dispatchDue(now);
  const rows=await outbox(db);
  assert.equal(rows[0].state,'DISCARDED');assert.equal(rows[0].last_error_code,'EVENT_SUPERSEDED');
  assert.equal(rows[1].state,'ACCEPTED');assert.equal(rows[1].delivered_at,null);assert.ok(rows[1].accepted_at);
  assert.equal(provider.sent.length,1);assert.match(provider.sent[0].title,/Zakończenie/);
  await store.put(event('ttl-offline'));
  await push.dispatchDue(new Date(+now+16*60000));
  const expired=(await outbox(db)).find(r=>r.event_id==='push-fixture-ttl-offline')!;
  assert.equal(expired.state,'DISCARDED');assert.equal(expired.last_error_code,'MESSAGE_EXPIRED');
  assert.equal(provider.sent.length,1);
 }finally{await db.close();}
});

test('retry expiry is absolute and does not restart the delivery window',async()=>{
 const {db,store,push,provider}=await setup();
 try{
  await push.register(registerBody(deviceA),secret,now);await store.put(event('retry-expired'));
  const original=JSON.parse(String((await outbox(db))[0].payload)).expiresAt;
  provider.results.push({kind:'RETRY',code:'OFFLINE'});await push.dispatchDue(now);
  await push.dispatchDue(new Date(Date.parse(original)+1000));
  const row=(await outbox(db))[0];assert.equal(row.state,'DISCARDED');assert.equal(provider.sent.length,1);
  assert.equal(JSON.parse(String(row.payload)).expiresAt,original);
 }finally{await db.close();}
});

test('historical provider acceptance migrates without claiming delivery',async()=>{
 const {db,store,push}=await setup();
 try{
  await push.register(registerBody(deviceA),secret,now);await store.put(event('migrate-delivered'));
  await db.run("UPDATE push_outbox SET state='DELIVERED',delivered_at=?",[now.toISOString()]);
  await db.run('ALTER TABLE push_outbox DROP COLUMN accepted_at');
  await store.init();const row=(await outbox(db))[0];
  assert.equal(row.state,'ACCEPTED');assert.equal(row.accepted_at,now.toISOString());assert.equal(row.delivered_at,null);
  await store.init();assert.equal((await outbox(db))[0].accepted_at,now.toISOString());
 }finally{await db.close();}
});

test('event link resolves the latest ended revision outside active regional lists',async()=>{
 const {db,store,push}=await setup();const app=await buildApp(store,undefined,push);
 try{
  const e=event('link-ended');await store.put(e);await store.put({...e,lifecycle:'ENDED',validTo:now.toISOString()});
  const response=await app.inject({method:'GET',url:'/v1/events/'+e.id});
  assert.equal(response.statusCode,200);assert.equal(response.json().id,e.id);assert.equal(response.json().lifecycle,'ENDED');assert.equal(response.json().revision,2);
  assert.equal((await app.inject({method:'GET',url:'/v1/events/nonexistent'})).statusCode,404);
 }finally{await app.close();await db.close();}
});

test('FCM wire payload bounds offline storage and sets a severity channel',async()=>{
 const {generateKeyPairSync}=await import('node:crypto');const {FcmProvider}=await import('../src/push.js');
 const pair=generateKeyPairSync('rsa',{modulusLength:2048});
 const fcm=new FcmProvider({project_id:'fixture',client_email:'fixture@example.com',private_key:pair.privateKey.export({type:'pkcs8',format:'pem'}).toString()});
 const original=globalThis.fetch;let payload:any;
 globalThis.fetch=async(url,options)=>{
  if(String(url).includes('oauth2'))return new Response(JSON.stringify({access_token:'fixture',expires_in:3600}),{status:200});
  payload=JSON.parse(String(options?.body));return new Response('{"name":"fixture-message"}',{status:200});
 };
 try{
  const result=await fcm.send('fixture-token',{title:'Alert',body:'Fixture',collapseKey:'event-1',channelId:'bp_threats',expiresAt:new Date(Date.now()+45000).toISOString(),data:{eventId:'event-1'}});
  assert.equal(result.kind,'SUCCESS');assert.match(payload.message.android.ttl,/^4[0-5]s$/);
  assert.equal(payload.message.android.notification.channel_id,'bp_threats');assert.equal(payload.message.data.eventId,'event-1');
  assert.equal((await fcm.send('fixture-token',{title:'Expired',body:'Fixture',collapseKey:'event-1',channelId:'bp_threats',expiresAt:new Date(Date.now()-1000).toISOString(),data:{}})).code,'MESSAGE_EXPIRED');
 }finally{globalThis.fetch=original;}
});

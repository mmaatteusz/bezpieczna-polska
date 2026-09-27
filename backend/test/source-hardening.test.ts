import test from 'node:test';
import assert from 'node:assert/strict';
import {buildApp} from '../src/app.js';
import {ingest,initializeSources,parseRso,SOURCES} from '../src/adapters.js';
import {Store,openDb} from '../src/store.js';

const now=new Date('2026-09-24T12:00:00Z');
const rso=(alarm:string)=>`<?xml version="1.0"?><root><pagination_info totalItems="1"/><news><id>123</id><title>Komunikat RSO</title><content>Oficjalny komunikat testowy.</content><shortcut>Komunikat</shortcut><created_at>2026-09-24 12:00:00</created_at><valid_from>2026-09-24 12:00:00</valid_from><valid_to>2026-09-24 14:00:00</valid_to><rso_alarm>${alarm}</rso_alarm></news></root>`;

test('RSO keeps feed available when alarm marker changes',()=>{
 assert.equal(parseRso(rso('1'),now)[0].severity,'HIGH');
 assert.equal(parseRso(rso('0'),now)[0].severity,'NORMAL');
 assert.equal(parseRso(rso('true'),now)[0].severity,'HIGH');
 assert.equal(parseRso(rso('false'),now)[0].severity,'NORMAL');
 assert.equal(parseRso(rso(''),now)[0].severity,'NORMAL');
 assert.equal(parseRso(rso('ALARM'),now)[0].severity,'HIGH');
});

test('source quality contracts distinguish authoritative state from publication feeds',()=>{
 const byId=new Map(SOURCES.map(s=>[s.id,s]));
 assert.equal(byId.get('IMGW_METEO')?.sourceClass,'STATUS');
 assert.equal(byId.get('IMGW_METEO')?.absenceSemantics,'AUTHORITATIVE_EMPTY_SET');
 assert.equal(byId.get('IMGW_HYDRO')?.absenceSemantics,'AUTHORITATIVE_EMPTY_SET');
 assert.equal(byId.get('RCB')?.sourceClass,'STATUS');
 assert.equal(byId.get('RCB')?.absenceSemantics,'NOT_PROVABLE');
 assert.equal(byId.get('RSO')?.absenceSemantics,'NOT_PROVABLE');
 assert.equal(byId.get('PAA')?.absenceSemantics,'NOT_PROVABLE');
 assert.equal(byId.get('CERT')?.sourceClass,'CONTEXT');
 assert.equal(byId.get('PAA_MEASUREMENTS')?.sourceClass,'REFERENCE');
 assert.equal(byId.get('NEPTUN')?.sourceClass,'SITUATIONAL');
 assert.equal(byId.get('UA')?.enabled,false);
});

test('authoritative empty-set contract fails closed when adapter becomes incomplete',async()=>{
 const store=new Store(openDb(undefined,':memory:'));await store.init();
 try{
  await ingest(store,[{id:'IMGW_METEO',version:'fixture',minSyncIntervalSeconds:0,async sync(){return {events:[],complete:false,coverage:'ACTIVE_WARNINGS',pagesFetched:1};}}],async()=>{throw new Error('UNUSED');});
  const imgw=(await store.health()).find(s=>s.id==='IMGW_METEO')!;
  assert.equal(imgw.state,'BROKEN');
  assert.equal(imgw.errorCode,'SOURCE_EMPTY_SET_CONTRACT_VIOLATION');
 }finally{await store.db.close();}
});

test('disabled sources are not synchronized and stay out of public source list',async()=>{
 const store=new Store(openDb(undefined,':memory:'));await store.init();
 try{
  await initializeSources(store);
  let called=false;
  await ingest(store,[{id:'CSIRT_GOV',version:'fixture',minSyncIntervalSeconds:0,async sync(){called=true;throw new Error('SHOULD_NOT_RUN');}}],async()=>{throw new Error('UNUSED');});
  assert.equal(called,false);
  const disabled=(await store.health()).find(s=>s.id==='CSIRT_GOV')!;
  assert.equal(disabled.enabled,false);
  assert.equal(disabled.state,'NOT_CONFIGURED');

  const app=await buildApp(store);
  try{
   const response=await app.inject({method:'GET',url:'/v1/sources'});
   assert.equal(response.statusCode,200);
   const publicSources=response.json().sourceHealth;
   const ids=publicSources.map((s:any)=>s.id);
   const imgw=publicSources.find((s:any)=>s.id==='IMGW_METEO');
   const rcb=publicSources.find((s:any)=>s.id==='RCB');
   assert.equal(imgw.sourceClass,'STATUS');
   assert.equal(imgw.absenceSemantics,'AUTHORITATIVE_EMPTY_SET');
   assert.equal(rcb.sourceClass,'STATUS');
   assert.equal(rcb.absenceSemantics,'NOT_PROVABLE');
   assert.ok(ids.includes('RCB'));
   assert.ok(!ids.includes('UA'));
   assert.ok(!ids.includes('CSIRT_GOV'));
   assert.ok(ids.includes('PAA_MEASUREMENTS'));
   assert.ok(!ids.includes('WCZK-04'));
   assert.ok(ids.includes('WCZK-18'));
  }finally{await app.close();}
 }finally{await store.db.close();}
});

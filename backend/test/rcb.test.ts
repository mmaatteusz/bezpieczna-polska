import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {parseRcbArticle,rcbAdapter,RCB_INDEX} from '../src/rcb-adapter.js';
import {ingest,initializeSources,SOURCES} from '../src/adapters.js';
import {Store,openDb} from '../src/store.js';
import {computeStatus,sourceHealth} from '../src/domain.js';
import {buildApp} from '../src/app.js';
const now=new Date('2026-09-18T12:00:00Z');
const url='https://www.gov.pl/web/rcb/alert-rcb---zagrozenie-z-powietrza-1709';
const html=readFileSync('test/fixtures/rcb-air.html','utf8');
const item=()=>parseRcbArticle(html,url,now);
const listing=(next='')=>`<main><a href="${url}">Alert RCB</a>${next?`<a id="js-pagination-page-next" href="${next}">Next</a>`:''}</main>`;
test('real RCB article: date precision, recipient provinces, provenance; no invented expiry/geometry',()=>{
 const e=item();assert.equal(e.publicationDate,'2026-09-17');assert.equal(e.publishedAt,null);
 assert.deepEqual(e.regions,['06','18']);assert.equal(e.verification,'CONFIRMED');assert.equal(e.messageContext,'ACTUAL');
 assert.equal(e.lifecycle,'UNKNOWN');assert.equal(e.validTo,null);assert.equal(e.geometry,null);assert.equal(e.reviewed,false);
 assert.match(e.sourceContentHash!,/^[a-f0-9]{64}$/);
 assert.deepEqual(parseRcbArticle(html.replace('woj. podkarpackiego','woj: podkarpackiego'),url,now).regions,['06','18']);
});
test('body update explicitly ending danger closes the original RCB warning',()=>{
 const updated=html.replace(
  '<div><p>"UWAGA!',
  '<div><p>Aktualizacja!</p><p>UWAGA! Zakończył się atak powietrzny na Ukrainę. Brak zagrożenia na terenie Polski.</p><p>"UWAGA!'
 );
 const e=parseRcbArticle(updated,url,now);
 assert.equal(e.lifecycle,'CANCELLED');assert.equal(e.officialWarning,false);assert.equal(e.severity,'INFORMATIONAL');
 assert.match(e.correction??'',/Brak zagrożenia/);
});
test('county opolski in Lubelskie must not become province Opolskie',()=>{
 const text=html.replace('woj. podkarpackiego i lubelskiego','powiatów chełmskiego i opolskiego (woj. lubelskie)');
 assert.deepEqual(parseRcbArticle(text,url,now).regions,['06']);
 assert.equal(parseRcbArticle(text,url,now).areaPrecision,'PROVINCE_SUBSET');
});
test('unknown recipient area is not guessed from places in warning body',()=>{
 const text=html.replace('Alert RCB został wysłany do odbiorców na terenie woj. podkarpackiego i lubelskiego.','');
 assert.deepEqual(parseRcbArticle(text,url,now).regions,[]);
});
test('exercise and cancellation publications do not create active warnings',()=>{
 const cancelled=parseRcbArticle('<article>'+readFileSync('test/fixtures/rcb-article.html','utf8')+'</article>',url,now);
 assert.equal(cancelled.lifecycle,'CANCELLED');assert.equal(cancelled.officialWarning,false);
 const exercise=parseRcbArticle(html.replace('Alert RCB - zagrożenie','Alert RCB - ćwiczenia, zagrożenie'),url,now);
 assert.equal(exercise.messageContext,'EXERCISE');assert.equal(exercise.officialWarning,false);
});
test('invalid date, missing body and external pagination fail closed',async()=>{
 assert.throws(()=>parseRcbArticle(html.replace('17.09.2026','31.02.2026'),url,now),/CONTRACT/);
 await assert.rejects(rcbAdapter.sync({now,fetchText:async()=>listing('https://example.com/?page=2')}),/DENIED/);
});
test('RCB pagination bounded and deduplicated; successful archive remains incomplete',async()=>{
 const requests:string[]=[];
 const batch=await rcbAdapter.sync({now,fetchText:async u=>{requests.push(u);return u===url?html:listing('?page=2&size=10');}}).catch(e=>e);
 assert.match(batch.message,/LOOP/);
 const good=await rcbAdapter.sync({now,fetchText:async u=>u===url?html:u===RCB_INDEX?listing('?page=2&size=10'):listing()});
 assert.equal(good.events.length,1);assert.equal(good.pagesFetched,2);assert.equal(good.complete,false);
});
test('sync success, deduplication, failure retention and recovery',async()=>{
 const db=openDb(undefined,':memory:'),store=new Store(db);await store.init();
 try{
  const good={...rcbAdapter,sync:async()=>({events:[item()],complete:false,coverage:'RECENT_PUBLICATIONS' as const,pagesFetched:1})};
  await ingest(store,[good]);await ingest(store,[good]);
  assert.equal((await store.timeline(item().id)).length,1);
  const first=(await store.health()).find(s=>s.id==='RCB')!;
  assert.equal(first.state,'HEALTHY');assert.ok(first.lastSuccess);assert.equal(first.itemCount,1);
  await ingest(store,[{...good,sync:async()=>{throw new Error('RCB_ARTICLE_CONTRACT_CHANGED');}}]);
  const broken=(await store.health()).find(s=>s.id==='RCB')!;
  assert.equal(broken.state,'BROKEN');assert.equal(broken.lastSuccess,first.lastSuccess);assert.equal(broken.errorCode,'RCB_ARTICLE_CONTRACT_CHANGED');
  assert.equal((await store.events()).length,1);
  await ingest(store,[good]);assert.equal((await store.health()).find(s=>s.id==='RCB')!.failureCount,0);
 }finally{await db.close();}
});
test('batch rollback never publishes half of a sync or its success health',async()=>{
 const db=openDb(undefined,':memory:'),store=new Store(db);await store.init();await initializeSources(store);
 try{
  const health=(await store.health()).find(s=>s.id==='RCB')!;
  await assert.rejects(store.applySync([item(),{...item(),id:'invalid',title:''}],{...health,state:'HEALTHY',lastSuccess:now.toISOString()}));
  assert.equal((await store.events()).length,0);assert.equal((await store.health()).find(s=>s.id==='RCB')!.lastSuccess,null);
 }finally{await db.close();}
});
test('unknown validity prevents green even with complete transport coverage',()=>{
 const health={id:'RCB',name:'RCB',url:RCB_INDEX,state:'HEALTHY' as const,lastSuccess:now.toISOString(),lastFailure:null,lastItemTime:null,failureCount:0,responseTime:1,maxAgeSeconds:600,complete:true};
 assert.equal(computeStatus([item()],[health],'06',now).hazardLevel,'UNKNOWN');
 assert.equal(sourceHealth([health],new Date(now.getTime()+601000))[0].state,'STALE');
 // Automation does not require a person to approve each structured warning.
 const active={...item(),lifecycle:'ACTIVE' as const,validTo:'2026-09-18T13:00:00Z',severity:'CRITICAL' as const};
 assert.equal(computeStatus([active],[health],'06',now).hazardLevel,'ACTIVE_DANGER');
});
test('status separates Poland and region; RCB without geometry produces no invented map point',async()=>{
 const db=openDb(undefined,':memory:'),store=new Store(db);await store.init();await store.put(item());const app=await buildApp(store);
 try{
  const status=(await app.inject('/status?regionId=04')).json();
  assert.equal(status.region.id,'04');assert.equal(status.poland.hazardLevel,'UNKNOWN');assert.equal(status.region.hazardLevel,'UNKNOWN');
  assert.equal(status.sourceHealth.length,SOURCES.length);assert.equal((await app.inject('/status?regionId=bad')).statusCode,400);
  assert.equal((await app.inject('/readyz')).statusCode,503);
  assert.deepEqual((await app.inject('/v1/layers/events.geojson')).json().features,[]);
  assert.equal((await app.inject('/v1/layers/events.geojson?bbox=bad')).statusCode,400);
 }finally{await app.close();await db.close();}
});

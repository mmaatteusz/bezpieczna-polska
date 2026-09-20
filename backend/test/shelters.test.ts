import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {shelterAdapter,parseShelterCatalog,parseShelterCsv,SHELTER_CSV,SHELTER_CATALOG,SHELTER_DATASET} from '../src/shelter-adapter.js';
import {Store,openDb} from '../src/store.js';
import {ingest,initializeSources,fetchPublic} from '../src/adapters.js';
import {computeStatus,sourceHealth} from '../src/domain.js';
import {buildApp} from '../src/app.js';
const now=new Date('2026-09-19T12:00:00Z');
const csv=readFileSync('test/fixtures/psp-shelters.csv','utf8'),xml=readFileSync('test/fixtures/psp-catalog.xml','utf8'),dataset=readFileSync('test/fixtures/psp-dataset.json','utf8');
const fetchText=async(url:string)=>{if(url===SHELTER_CSV)return csv;if(url===SHELTER_CATALOG)return xml;if(url===SHELTER_DATASET)return dataset;throw new Error('UNEXPECTED_URL');};
const batch=()=>shelterAdapter.sync({now,fetchText});
test('real PSP CSV subset preserves official IDs, addresses, coordinates and unknown protection',async()=>{
 const b=await batch();assert.equal(b.shelters!.length,3);assert.equal(b.events.length,0);
 const s=b.shelters![0];assert.equal(s.address,'ul. Narcyza Gieryna 4, Bydgoszcz');assert.equal(s.regionId,'04');
 assert.equal(s.latitude,53.1661471448123);assert.equal(s.longitude,18.1731816478461);assert.equal(s.protectionClass,'UNKNOWN');assert.equal(s.capacity,null);
 assert.deepEqual(b.shelters!.map(s=>s.availability),['ON_REQUEST','24H','LIMITED_HOURS']);assert.ok(b.shelters!.every(s=>s.openingHours===null));
 assert.equal(b.metadata!.license,'CC BY 4.0');assert.equal(b.complete,true);
});
test('CSV rejects truncation, duplicate IDs, bad columns, unknown region and swapped coordinates',()=>{
 const meta=parseShelterCatalog(xml,now);
 assert.throws(()=>parseShelterCsv(csv,{...meta,count:4}),/COUNT_MISMATCH/);
 assert.throws(()=>parseShelterCsv(csv.replace('Dostepnosc','Availability'),meta),/COLUMNS_CHANGED/);
 const lines=csv.trimEnd().split(/\r?\n/);assert.throws(()=>parseShelterCsv([lines[0],lines[1],lines[1],lines[3]].join('\n'),meta),/DUPLICATE/);
 assert.throws(()=>parseShelterCsv(csv.replaceAll('kujawsko-pomorskie','nieznane'),meta));
 assert.throws(()=>parseShelterCsv(csv.replace('53.1661471448123,18.1731816478461','18.1731816478461,53.1661471448123'),meta));
 assert.throws(()=>parseShelterCsv(csv.replace('53.1661471448123',''),meta));
});
test('catalog validates publisher, license, resource path, dates and stable export version',async()=>{
 assert.throws(()=>parseShelterCatalog(xml.replaceAll('CC BY 4.0','proprietary'),now),/CONTRACT/);
 assert.throws(()=>parseShelterCatalog('<!DOCTYPE a>'+xml,now),/UNSAFE_XML/);
 assert.throws(()=>parseShelterCatalog(xml,new Date('2026-10-10T12:00:00Z')),/OUTDATED/);
 assert.throws(()=>parseShelterCatalog(xml,new Date('2026-08-10T12:00:00Z')),/FUTURE_DATE/);
 await assert.rejects(shelterAdapter.sync({now,fetchText:async u=>u===SHELTER_DATASET?dataset.replace('"22"','"999"'):fetchText(u)}),/PUBLISHER/);
 let calls=0;await assert.rejects(shelterAdapter.sync({now,fetchText:async u=>u===SHELTER_CATALOG&&++calls===2?xml.replaceAll('08:24:06','08:25:06'):fetchText(u)}),/CHANGED_DURING_SYNC/);
 await assert.rejects(fetchPublic(SHELTER_CSV+'?redirect=https://example.com'),/DENIED/);
});
test('unknown availability is preserved without claiming all-day access',()=>{
 const s=parseShelterCsv(csv.replace('Na żądanie','Nowa wartość'),parseShelterCatalog(xml,now))[0];assert.equal(s.availability,'UNKNOWN');assert.equal(s.sourceAvailability,'Nowa wartość');
});
test('shelter sync is isolated from events, retains last good data on failure, and uses six-hour interval',async()=>{
 const db=openDb(undefined,':memory:'),store=new Store(db);await store.init();
 try{
  const b=await batch();let calls=0;const adapter={...shelterAdapter,sync:async()=>{calls++;return b;}};
  await ingest(store,[adapter]);const old=(await store.health()).find(h=>h.id==='SHELTERS')!;
  await ingest(store,[adapter]);assert.equal(calls,1);assert.equal((await store.events()).length,0);
  await ingest(store,[{...adapter,minSyncIntervalSeconds:0,sync:async()=>{throw new Error('SHELTER_COUNT_MISMATCH');}}]);
  const h=(await store.health()).find(h=>h.id==='SHELTERS')!;assert.equal(h.state,'BROKEN');assert.equal(h.lastSuccess,old.lastSuccess);assert.equal(h.sourceContentHash,old.sourceContentHash);
  const page=await store.shelterPage({regionId:'04',q:'',limit:50,offset:0});assert.equal(page.total,3);
  assert.equal(computeStatus([],[old],'04').hazardLevel,'UNKNOWN');
  assert.equal(sourceHealth([{...old,lastSuccess:now.toISOString()}],new Date('2026-09-22T12:00:00Z'))[0].state,'STALE');
 }finally{await db.close();}
});
test('whole-package replacement removes absent points, validates all records and rejects mixed-version pagination',async()=>{
 const db=openDb(undefined,':memory:'),store=new Store(db);await store.init();await initializeSources(store);
 try{
  const b=await batch();await ingest(store,[{...shelterAdapter,sync:async()=>b}]);
  const health=(await store.health()).find(h=>h.id==='SHELTERS')!;
  await assert.rejects(store.applyShelterSync([b.shelters![0],{...b.shelters![1],latitude:0}],{...health,itemCount:2,sourceContentHash:'b'.repeat(64)}));
  assert.equal((await store.shelterPage({regionId:'PL',q:'',limit:50,offset:0})).total,3);
  await store.applyShelterSync([b.shelters![0]],{...health,itemCount:1,sourceContentHash:'c'.repeat(64)});
  assert.equal((await store.shelterPage({regionId:'PL',q:'',limit:50,offset:0})).total,1);
  await assert.rejects(store.shelterPage({regionId:'PL',q:'',limit:50,offset:1,version:health.sourceContentHash}),/VERSION_CHANGED/);
 }finally{await db.close();}
});
test('shelter API provides filtered pages, source freshness, exact GeoJSON and honest empty results',async()=>{
 const db=openDb(undefined,':memory:'),store=new Store(db);await store.init();const b=await batch();await ingest(store,[{...shelterAdapter,sync:async()=>b}]);const app=await buildApp(store);
 try{
  const result=(await app.inject('/v1/shelters?regionId=04&q=Bydgoszcz&limit=1')).json();
  assert.equal(result.total,3);assert.equal(result.items.length,1);assert.equal(result.hasMore,true);assert.equal(result.health.itemCount,3);
  const next=(await app.inject(`/v1/shelters?regionId=04&limit=1&offset=1&version=${result.version}`)).json();assert.notEqual(next.items[0].id,result.items[0].id);
  const exact=(await app.inject('/v1/shelters?regionId=04&q=Gieryna')).json();assert.equal(exact.total,1);
  assert.equal((await app.inject('/v1/shelters?regionId=02')).json().total,0);
  assert.equal((await app.inject('/v1/shelters?q=%25')).json().total,0);
  assert.equal((await app.inject('/v1/shelters?limit=501')).statusCode,400);
  assert.equal((await app.inject('/v1/shelters?offset=-1')).statusCode,400);
  assert.equal((await app.inject('/v1/shelters?version='+'a'.repeat(64))).statusCode,409);
  const layer=(await app.inject('/v1/layers/shelters.geojson?q=Gieryna')).json();assert.deepEqual(layer.features[0].geometry.coordinates,[18.1731816478461,53.1661471448123]);assert.equal(layer.metadata.total,1);
  assert.equal((await app.inject('/v1/layers/shelters.geojson?bbox=17,53,19,54')).statusCode,503);
  const snap=(await app.inject('/v1/snapshot?regionId=04')).json();assert.equal(snap.shelters.length,3);assert.equal(snap.capabilities.shelters,true);assert.equal(snap.events.length,0);assert.equal(snap.nationalStatus.hazardLevel,'UNKNOWN');
 }finally{await app.close();await db.close();}
});


test('HTTP denial keeps its status code for source diagnostics',async()=>{
 const original=globalThis.fetch;
 try{
  globalThis.fetch=async()=>new Response('Access denied',{status:403});
  await assert.rejects(fetchPublic(SHELTER_CSV),/SOURCE_HTTP_403/);
 }finally{globalThis.fetch=original;}
});

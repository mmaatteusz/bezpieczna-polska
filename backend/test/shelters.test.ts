import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {deflateRawSync} from 'node:zlib';
import {shelterAdapter,parseShelterResource,parseShelterCsv,extractShelterCsv,SHELTER_DOWNLOAD,SHELTER_RESOURCE,SHELTER_DATASET,SHELTER_ORIGIN_CSV,SHELTER_ARCHIVE} from '../src/shelter-adapter.js';
import {Store,openDb} from '../src/store.js';
import {ingest,initializeSources,fetchPublicBytes} from '../src/adapters.js';
import {computeStatus,sourceHealth} from '../src/domain.js';
import {buildApp} from '../src/app.js';
const now=new Date('2026-09-19T12:00:00Z');
const csv=readFileSync('test/fixtures/psp-shelters.csv','utf8'),resource=readFileSync('test/fixtures/psp-resource.json','utf8'),dataset=readFileSync('test/fixtures/psp-dataset.json','utf8');
function zipCsv(text:string){
 const name=Buffer.from('Punkty schronienia dane CSV_1393918.csv','utf8'),raw=Buffer.from(text,'utf8'),compressed=deflateRawSync(raw);
 const dosDate=((2026-1980)<<9)|(3<<5)|10,dosTime=(9<<11)|(44<<5);
 const local=Buffer.alloc(30);local.writeUInt32LE(0x04034b50,0);local.writeUInt16LE(20,4);local.writeUInt16LE(0x800,6);local.writeUInt16LE(8,8);local.writeUInt16LE(dosTime,10);local.writeUInt16LE(dosDate,12);local.writeUInt32LE(compressed.length,18);local.writeUInt32LE(raw.length,22);local.writeUInt16LE(name.length,26);
 const central=Buffer.alloc(46);central.writeUInt32LE(0x02014b50,0);central.writeUInt16LE(20,4);central.writeUInt16LE(20,6);central.writeUInt16LE(0x800,8);central.writeUInt16LE(8,10);central.writeUInt16LE(dosTime,12);central.writeUInt16LE(dosDate,14);central.writeUInt32LE(compressed.length,20);central.writeUInt32LE(raw.length,24);central.writeUInt16LE(name.length,28);central.writeUInt32LE(0,42);
 const eocd=Buffer.alloc(22);eocd.writeUInt32LE(0x06054b50,0);eocd.writeUInt16LE(1,8);eocd.writeUInt16LE(1,10);eocd.writeUInt32LE(central.length+name.length,12);eocd.writeUInt32LE(local.length+name.length+compressed.length,16);
 return Buffer.concat([local,name,compressed,central,name,eocd]);
}
const fetchText=async(url:string)=>{if(url===SHELTER_RESOURCE)return resource;if(url===SHELTER_DATASET)return dataset;if(url===SHELTER_ORIGIN_CSV)return csv;throw new Error('UNEXPECTED_URL');};
const fetchBytes=async(url:string)=>{if(url===SHELTER_ARCHIVE)return zipCsv(csv);throw new Error('UNEXPECTED_BINARY_URL');};
const batch=()=>shelterAdapter.sync({now,fetchText,fetchBytes});
test('real PSP CSV subset preserves official IDs, addresses, coordinates and unknown protection',async()=>{
 const b=await batch();assert.equal(b.shelters!.length,3);assert.equal(b.events.length,0);
 const s=b.shelters![0];assert.equal(s.address,'ul. Narcyza Gieryna 4, Bydgoszcz');assert.equal(s.regionId,'04');
 assert.equal(s.latitude,53.1661471448123);assert.equal(s.longitude,18.1731816478461);assert.equal(s.protectionClass,'UNKNOWN');assert.equal(s.capacity,null);
 assert.deepEqual(b.shelters!.map(s=>s.availability),['ON_REQUEST','24H','LIMITED_HOURS']);assert.ok(b.shelters!.every(s=>s.openingHours===null));
 assert.equal(b.metadata!.license,'CC BY 4.0');assert.equal(b.metadata!.fallbackSelected,'PRIMARY_OFFICIAL_SOURCE');assert.equal(b.metadata!.sourceUrl,SHELTER_ORIGIN_CSV);assert.equal(b.complete,true);
});
test('CSV rejects truncation, duplicate IDs, bad columns, unknown region and swapped coordinates',()=>{
 const meta=parseShelterResource(resource,now);
 assert.throws(()=>parseShelterCsv(csv,{...meta,count:4}),/COUNT_MISMATCH/);
 assert.throws(()=>parseShelterCsv(csv.replace('Dostepnosc','Availability'),meta),/COLUMNS_CHANGED/);
 const lines=csv.trimEnd().split(/\r?\n/);assert.throws(()=>parseShelterCsv([lines[0],lines[1],lines[1],lines[3]].join('\n'),meta),/DUPLICATE/);
 assert.throws(()=>parseShelterCsv(csv.replaceAll('kujawsko-pomorskie','nieznane'),meta));
 assert.throws(()=>parseShelterCsv(csv.replace('53.1661471448123,18.1731816478461','18.1731816478461,53.1661471448123'),meta));
 assert.throws(()=>parseShelterCsv(csv.replace('53.1661471448123',''),meta));
});
test('official dane.gov.pl resource and archive validate publisher, dates and stable export version',async()=>{
 assert.throws(()=>parseShelterResource(resource.replace(SHELTER_DOWNLOAD,'https://example.com/file.csv'),now),/CONTRACT/);
 assert.throws(()=>parseShelterResource(resource,new Date('2026-10-10T12:00:00Z')),/OUTDATED/);
 assert.throws(()=>parseShelterResource(resource,new Date('2026-08-10T12:00:00Z')),/FUTURE_DATE/);
 await assert.rejects(shelterAdapter.sync({now,fetchText:async u=>u===SHELTER_DATASET?dataset.replace('"22"','"999"'):fetchText(u),fetchBytes}),/PUBLISHER/);
 let calls=0;await assert.rejects(shelterAdapter.sync({now,fetchText:async u=>u===SHELTER_RESOURCE&&++calls===2?resource.replace('08:24:06','08:25:06'):fetchText(u),fetchBytes}),/CHANGED_DURING_SYNC/);
 const extracted=extractShelterCsv(zipCsv(csv));assert.equal(extracted.csv,csv.replace(/^\uFEFF/,''));assert.equal(extracted.dataDate,'2026-03-10');
});
test('403 on current PSP CSV falls back to official dane.gov.pl archive and marks its older date',async()=>{
 const b=await shelterAdapter.sync({now,fetchText:async u=>u===SHELTER_ORIGIN_CSV?Promise.reject(new Error('SOURCE_HTTP_403')):fetchText(u),fetchBytes});
 assert.equal(b.shelters!.length,3);assert.equal(b.metadata!.fallbackSelected,'SECONDARY_OFFICIAL_SOURCE');assert.equal(b.metadata!.sourceUrl,SHELTER_ARCHIVE);
 assert.equal(b.metadata!.dataDate,'2026-03-10');assert.match(b.metadata!.sourceUpdatedAt,/^2026-03-10T09:44:/);
 const health=sourceHealth([{id:'SHELTERS',name:'S',url:'https://dane.gov.pl/',state:'HEALTHY',lastSuccess:now.toISOString(),lastFailure:null,lastItemTime:b.metadata!.sourceUpdatedAt,failureCount:0,responseTime:1,maxAgeSeconds:172800,complete:true,...b.metadata}],now)[0];
 assert.equal(health.state,'STALE');assert.equal(health.fallback.selected,'SECONDARY_OFFICIAL_SOURCE');assert.equal(health.fallback.secondaryStatus,'AVAILABLE_STALE');
});
test('unknown availability is preserved without claiming all-day access',()=>{
 const s=parseShelterCsv(csv.replace('Na żądanie','Nowa wartość'),parseShelterResource(resource,now))[0];assert.equal(s.availability,'UNKNOWN');assert.equal(s.sourceAvailability,'Nowa wartość');
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
test('older official archive never replaces a newer last-known-good shelter catalog',async()=>{
 const db=openDb(undefined,':memory:'),store=new Store(db);await store.init();
 try{
  const current=await batch();await ingest(store,[{...shelterAdapter,minSyncIntervalSeconds:0,sync:async()=>current}]);
  const before=(await store.health()).find(h=>h.id==='SHELTERS')!,count=(await store.shelterPage({regionId:'PL',q:'',limit:50,offset:0})).total;
  const stale={...current,metadata:{...current.metadata!,dataDate:'2026-03-10',sourceUpdatedAt:'2026-03-10T09:44:00Z',sourceUrl:SHELTER_ARCHIVE,fallbackSelected:'SECONDARY_OFFICIAL_SOURCE' as const}};
  await ingest(store,[{...shelterAdapter,minSyncIntervalSeconds:0,sync:async()=>stale}]);
  const after=(await store.health()).find(h=>h.id==='SHELTERS')!;
  assert.equal(after.state,'BROKEN');assert.equal(after.errorCode,'SHELTER_FALLBACK_OLDER_THAN_LAST_GOOD');assert.equal(after.sourceUpdatedAt,before.sourceUpdatedAt);
  assert.equal((await store.shelterPage({regionId:'PL',q:'',limit:50,offset:0})).total,count);
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


test('nearest shelter POST keeps precise coordinates out of URLs; legacy GET is deprecated',async()=>{
 const db=openDb(undefined,':memory:'),store=new Store(db);await store.init();const b=await batch();await ingest(store,[{...shelterAdapter,sync:async()=>b}]);const app=await buildApp(store);
 try{
  const first=b.shelters![0];
  const response=await app.inject({method:'POST',url:'/v1/shelters/nearest',payload:{latitude:first.latitude,longitude:first.longitude,limit:3}});
  assert.equal(response.statusCode,200);
  const body=response.json();assert.equal(body.items.length,3);assert.equal(body.items[0].point.id,first.id);assert.equal(body.items[0].distanceMeters,0);
  assert.ok(body.items[0].distanceMeters<=body.items[1].distanceMeters&&body.items[1].distanceMeters<=body.items[2].distanceMeters);
  assert.equal((await app.inject({method:'POST',url:'/v1/shelters/nearest',payload:{latitude:999,longitude:18}})).statusCode,400);
  const legacy=await app.inject(`/v1/shelters/nearest?lat=${first.latitude}&lon=${first.longitude}&limit=1`);
  assert.equal(legacy.statusCode,200);assert.equal(legacy.headers.deprecation,'true');assert.match(String(legacy.headers.warning),/Deprecated/);
 }finally{await app.close();await db.close();}
});


test('HTTP denial keeps its status code for source diagnostics',async()=>{
 const original=globalThis.fetch;
 try{
  globalThis.fetch=async()=>new Response('Access denied',{status:403});
  await assert.rejects(fetchPublicBytes(SHELTER_ARCHIVE),/SOURCE_HTTP_403/);
 }finally{globalThis.fetch=original;}
});

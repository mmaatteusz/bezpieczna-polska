import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {deflateRawSync} from 'node:zlib';
import {shelterAdapter,parseShelterResource,parseShelterCsv,extractShelterCsv,prepareOperatorShelterSnapshot,SHELTER_DOWNLOAD,SHELTER_RESOURCE,SHELTER_DATASET,SHELTER_ORIGIN_CSV,SHELTER_ARCHIVE} from '../src/shelter-adapter.js';
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
const fetchText=async(url:string)=>{if(url===SHELTER_RESOURCE)return resource;if(url===SHELTER_DATASET)return dataset;if(url===SHELTER_ORIGIN_CSV||url===SHELTER_DOWNLOAD)return csv;throw new Error('UNEXPECTED_URL');};
const fetchBytes=async(url:string)=>{if(url===SHELTER_ARCHIVE)return zipCsv(csv);throw new Error('UNEXPECTED_BINARY_URL');};
const batch=()=>shelterAdapter.sync({now,fetchText,fetchBytes});
test('real PSP CSV subset preserves official IDs, addresses, coordinates and unknown protection',async()=>{
 const b=await batch();assert.equal(b.shelters!.length,3);assert.equal(b.events.length,0);
 const s=b.shelters![0];assert.equal(s.address,'ul. Narcyza Gieryna 4, Bydgoszcz');assert.equal(s.regionId,'04');
 assert.equal(s.latitude,53.1661471448123);assert.equal(s.longitude,18.1731816478461);assert.equal(s.protectionClass,'UNKNOWN');assert.equal(s.capacity,null);
 assert.deepEqual(b.shelters!.map(s=>s.availability),['ON_REQUEST','24H','LIMITED_HOURS']);assert.ok(b.shelters!.every(s=>s.openingHours===null));
 assert.equal(b.metadata!.license,'CC BY 4.0');assert.equal(b.metadata!.fallbackSelected,'PRIMARY_OFFICIAL_SOURCE');assert.equal(b.metadata!.sourceUrl,SHELTER_ORIGIN_CSV);
 assert.equal(b.metadata!.catalogDataDate,'2026-09-19');assert.equal(b.metadata!.catalogItemCount,3);assert.equal(b.complete,true);
});
test('rolling current export may contain more rows than lagging catalog metadata',async()=>{
 const lines=csv.trimEnd().split(/\r?\n/),extra=lines[1].replace('OZO-D5F2DD0D35F3','OZO-AAAAAAAAAAAA');
 const rolling=[...lines,extra].join('\n')+'\n';
 const b=await shelterAdapter.sync({now,fetchText:async u=>u===SHELTER_ORIGIN_CSV?rolling:fetchText(u),fetchBytes});
 assert.equal(b.shelters!.length,4);
 assert.equal(b.metadata!.fallbackSelected,'PRIMARY_OFFICIAL_SOURCE');
 assert.equal(b.metadata!.dataDate,'2026-09-19');
});
test('operator snapshot requires at least the live catalog count',()=>{
 const behind=resource.replace('3 rekordów','4 rekordów');
 assert.throws(()=>prepareOperatorShelterSnapshot(csv,behind,now),/SHELTER_SNAPSHOT_BEHIND_CATALOG/);
 const prepared=prepareOperatorShelterSnapshot(csv,resource,now);
 assert.equal(prepared.shelters.length,3);assert.equal(prepared.metadata.fallbackSelected,'OPERATOR_OFFICIAL_SNAPSHOT');
 assert.equal(prepared.metadata.catalogItemCount,3);assert.equal(prepared.metadata.dataDate,'2026-09-19');
});
test('loaded shelter snapshot ahead of catalog counter is not marked mismatched',()=>{
 const health=sourceHealth([{
  id:'SHELTERS',name:'S',url:'https://dane.gov.pl/',enabled:true,state:'HEALTHY',
  lastSuccess:now.toISOString(),lastFailure:null,lastItemTime:now.toISOString(),failureCount:0,responseTime:1,maxAgeSeconds:1209600,
  complete:true,coverage:'FACILITY_CATALOG',itemCount:4,dataDate:'2026-09-19',sourceUpdatedAt:'2026-09-19T08:24:06Z',
  catalogItemCount:3,catalogDataDate:'2026-09-19',catalogUpdatedAt:'2026-09-19T08:24:06Z',
  sourceContentHash:'a'.repeat(64),sourceUrl:SHELTER_ORIGIN_CSV,datasetUrl:'https://dane.gov.pl/pl/dataset/28058,punkty-schronienia-w-polsce',
  license:'CC BY 4.0',fallbackSelected:'OPERATOR_OFFICIAL_SNAPSHOT'
 }],now)[0];
 assert.equal(health.catalogMismatch,false);
});
test('authenticated admin can atomically import a validated official shelter CSV',async()=>{
 const db=openDb(undefined,':memory:'),store=new Store(db),token='t'.repeat(32),original=globalThis.fetch;await store.init();
 globalThis.fetch=async input=>{
  const url=typeof input==='string'?input:input instanceof URL?input.href:input.url;
  if(url===SHELTER_RESOURCE)return new Response(resource,{status:200,headers:{'content-type':'application/json'}});
  throw new Error('UNEXPECTED_FETCH_'+url);
 };
 const app=await buildApp(store,token);
 try{
  const unauthorized=await app.inject({method:'POST',url:'/admin/shelters/import',headers:{'content-type':'text/csv'},payload:csv});
  assert.equal(unauthorized.statusCode,401);
  const response=await app.inject({method:'POST',url:'/admin/shelters/import',headers:{authorization:`Bearer ${token}`,'content-type':'text/csv'},payload:csv});
  assert.equal(response.statusCode,200);const body=response.json();assert.equal(body.itemCount,3);assert.equal(body.dataDate,'2026-09-19');assert.equal(body.provenance,'OPERATOR_OFFICIAL_SNAPSHOT');
  const page=await store.shelterPage({regionId:'PL',q:'',limit:50,offset:0});assert.equal(page.total,3);
  const health=(await store.health()).find(h=>h.id==='SHELTERS')!;assert.equal(health.state,'HEALTHY');assert.equal(health.fallbackSelected,'OPERATOR_OFFICIAL_SNAPSHOT');assert.equal(health.itemCount,3);
 }finally{await app.close();await db.close();globalThis.fetch=original;}
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
test('403 on PSP origin falls back to current dane.gov.pl resource without losing current date',async()=>{
 const b=await shelterAdapter.sync({now,fetchText:async u=>u===SHELTER_ORIGIN_CSV?Promise.reject(new Error('SOURCE_HTTP_403')):fetchText(u),fetchBytes});
 assert.equal(b.shelters!.length,3);assert.equal(b.metadata!.fallbackSelected,'SECONDARY_OFFICIAL_CURRENT_RESOURCE');assert.equal(b.metadata!.sourceUrl,SHELTER_DOWNLOAD);
 assert.equal(b.metadata!.dataDate,'2026-09-19');assert.equal(b.metadata!.sourceUpdatedAt,'2026-09-19T08:24:06Z');assert.equal(b.metadata!.fallbackReason,'SOURCE_HTTP_403');
 const health=sourceHealth([{id:'SHELTERS',name:'S',url:'https://dane.gov.pl/',state:'HEALTHY',lastSuccess:now.toISOString(),lastFailure:null,lastItemTime:b.metadata!.sourceUpdatedAt,failureCount:0,responseTime:1,maxAgeSeconds:172800,complete:true,...b.metadata}],now)[0];
 assert.equal(health.state,'HEALTHY');assert.equal(health.catalogMismatch,false);assert.equal(health.fallback.selected,'SECONDARY_OFFICIAL_CURRENT_RESOURCE');assert.equal(health.fallback.secondaryStatus,'AVAILABLE_CURRENT');assert.match(health.fallback.reason!,/SOURCE_HTTP_403/);
});
test('when PSP origin and current dane.gov.pl resource both fail, archive is tertiary and visibly stale',async()=>{
 const b=await shelterAdapter.sync({now,fetchText:async u=>[SHELTER_ORIGIN_CSV,SHELTER_DOWNLOAD].includes(u)?Promise.reject(new Error(u===SHELTER_ORIGIN_CSV?'SOURCE_HTTP_403':'SOURCE_HTTP_503')):fetchText(u),fetchBytes});
 assert.equal(b.shelters!.length,3);assert.equal(b.metadata!.fallbackSelected,'TERTIARY_OFFICIAL_ARCHIVE');assert.equal(b.metadata!.sourceUrl,SHELTER_ARCHIVE);
 assert.equal(b.metadata!.dataDate,'2026-03-10');assert.match(b.metadata!.sourceUpdatedAt,/^2026-03-10T09:44:/);assert.match(b.metadata!.fallbackReason!,/SOURCE_HTTP_403/);assert.match(b.metadata!.fallbackReason!,/SOURCE_HTTP_503/);
 const health=sourceHealth([{id:'SHELTERS',name:'S',url:'https://dane.gov.pl/',state:'HEALTHY',lastSuccess:now.toISOString(),lastFailure:null,lastItemTime:b.metadata!.sourceUpdatedAt,failureCount:0,responseTime:1,maxAgeSeconds:172800,complete:true,...b.metadata}],now)[0];
 assert.equal(health.state,'STALE');assert.equal(health.catalogMismatch,true);assert.equal(health.fallback.selected,'TERTIARY_OFFICIAL_ARCHIVE');assert.equal(health.fallback.secondaryStatus,'AVAILABLE_STALE');
 assert.match(health.fallback.reason!,/2026-09-19/);assert.match(health.fallback.reason!,/2026-03-10/);
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
  assert.equal(sourceHealth([{...old,lastSuccess:now.toISOString()}],new Date('2026-09-22T12:00:00Z'))[0].state,'HEALTHY');assert.equal(sourceHealth([{...old,lastSuccess:now.toISOString()}],new Date('2026-10-05T12:00:01Z'))[0].state,'STALE');
 }finally{await db.close();}
});
test('older official archive never replaces a newer last-known-good shelter catalog',async()=>{
 const db=openDb(undefined,':memory:'),store=new Store(db);await store.init();
 try{
  const current=await batch();await ingest(store,[{...shelterAdapter,minSyncIntervalSeconds:0,sync:async()=>current}]);
  const before=(await store.health()).find(h=>h.id==='SHELTERS')!,count=(await store.shelterPage({regionId:'PL',q:'',limit:50,offset:0})).total;
  const stale={...current,metadata:{...current.metadata!,dataDate:'2026-03-10',sourceUpdatedAt:'2026-03-10T09:44:00Z',sourceUrl:SHELTER_ARCHIVE,fallbackSelected:'TERTIARY_OFFICIAL_ARCHIVE' as const}};
  await ingest(store,[{...shelterAdapter,minSyncIntervalSeconds:0,sync:async()=>stale}]);
  const after=(await store.health()).find(h=>h.id==='SHELTERS')!;
  assert.equal(after.state,'DEGRADED');assert.equal(after.errorCode,'SHELTER_FALLBACK_OLDER_THAN_LAST_GOOD');assert.equal(after.sourceUpdatedAt,before.sourceUpdatedAt);assert.equal(after.complete,true);
  const shortlyAfterSuccess=new Date(Date.parse(after.lastSuccess!)+60_000);
  const afterSourceExpiry=new Date(Date.parse(after.sourceUpdatedAt!)+14*86400000+1000);
  assert.equal(sourceHealth([after],shortlyAfterSuccess)[0].state,'DEGRADED');
  assert.equal(sourceHealth([after],afterSourceExpiry)[0].state,'STALE');
  assert.equal((await store.shelterPage({regionId:'PL',q:'',limit:50,offset:0})).total,count);
 }finally{await db.close();}
});
test('incremental shelter sync writes only changed, new and removed rows',async()=>{
 const db=openDb(undefined,':memory:'),store=new Store(db);await store.init();await initializeSources(store);
 try{
  const b=await batch();await ingest(store,[{...shelterAdapter,sync:async()=>b}]);
  await db.run("CREATE TABLE shelter_write_audit(kind TEXT NOT NULL,id TEXT NOT NULL)");
  await db.run("CREATE TRIGGER shelter_audit_insert AFTER INSERT ON shelters BEGIN INSERT INTO shelter_write_audit(kind,id) VALUES('INSERT',NEW.id); END");
  await db.run("CREATE TRIGGER shelter_audit_update AFTER UPDATE ON shelters BEGIN INSERT INTO shelter_write_audit(kind,id) VALUES('UPDATE',NEW.id); END");
  await db.run("CREATE TRIGGER shelter_audit_delete AFTER DELETE ON shelters BEGIN INSERT INTO shelter_write_audit(kind,id) VALUES('DELETE',OLD.id); END");

  const previous=(await store.health()).find(h=>h.id==='SHELTERS')!;
  const unchanged=b.shelters![0],changed={...b.shelters![1],address:b.shelters![1].address+' / aktualizacja'};
  const removed=b.shelters![2],added={...removed,id:'OZO-BBBBBBBBBBBB',address:removed.address+' / nowy'};
  const next=[unchanged,changed,added];

  await store.applyShelterSync(next,{
   ...previous,itemCount:next.length,sourceContentHash:'d'.repeat(64),
   dataDate:'2026-09-20',sourceUpdatedAt:'2026-09-20T08:24:06Z'
  });
  const writes=(await db.all('SELECT kind,id FROM shelter_write_audit ORDER BY kind,id')).map(row=>`${row.kind}:${row.id}`);
  assert.deepEqual(writes.sort(),[
   `DELETE:${removed.id}`,
   `INSERT:${added.id}`,
   `UPDATE:${changed.id}`
  ].sort());
  assert.ok(!writes.some(value=>value.endsWith(':'+unchanged.id)));
  const page=await store.shelterPage({regionId:'PL',q:'',limit:50,offset:0});
  assert.equal(page.total,3);assert.ok(page.items.some(item=>item.id===added.id));assert.ok(!page.items.some(item=>item.id===removed.id));
  assert.equal(page.items.find(item=>item.id===changed.id)!.address,changed.address);

  await db.run('DELETE FROM shelter_write_audit');
  await store.applyShelterSync(next,{
   ...(await store.health()).find(h=>h.id==='SHELTERS')!,itemCount:next.length,
   sourceContentHash:'e'.repeat(64),dataDate:'2026-09-21',sourceUpdatedAt:'2026-09-21T08:24:06Z'
  });
  assert.deepEqual(await db.all('SELECT kind,id FROM shelter_write_audit'),[]);
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


test('nearest shelter only accepts POST so precise coordinates stay out of URLs',async()=>{
 const db=openDb(undefined,':memory:'),store=new Store(db);await store.init();const b=await batch();await ingest(store,[{...shelterAdapter,sync:async()=>b}]);const app=await buildApp(store);
 try{
  const first=b.shelters![0];
  const response=await app.inject({method:'POST',url:'/v1/shelters/nearest',payload:{latitude:first.latitude,longitude:first.longitude,limit:3}});
  assert.equal(response.statusCode,200);
  const body=response.json();assert.equal(body.items.length,3);assert.equal(body.items[0].point.id,first.id);assert.equal(body.items[0].distanceMeters,0);
  assert.ok(body.items[0].distanceMeters<=body.items[1].distanceMeters&&body.items[1].distanceMeters<=body.items[2].distanceMeters);
  assert.equal((await app.inject({method:'POST',url:'/v1/shelters/nearest',payload:{latitude:999,longitude:18}})).statusCode,400);
  const legacy=await app.inject(`/v1/shelters/nearest?lat=${first.latitude}&lon=${first.longitude}&limit=1`);
  assert.equal(legacy.statusCode,404);
 }finally{await app.close();await db.close();}
});


test('HTTP denial keeps its status code for source diagnostics',async()=>{
 const original=globalThis.fetch;
 try{
  globalThis.fetch=async()=>new Response('Access denied',{status:403});
  await assert.rejects(fetchPublicBytes(SHELTER_ARCHIVE),/SOURCE_HTTP_403/);
 }finally{globalThis.fetch=original;}
});

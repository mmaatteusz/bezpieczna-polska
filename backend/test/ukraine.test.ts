import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtemp,rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {parseUaBatch,parseUaRegions,ukraineAdapter,fetchUa,isAllowedUaUrl,UA_API} from '../src/ukraine-adapter.js';
import {enrichUaGeometry,UA_BOUNDARY_SOURCE} from '../src/ukraine-geography.js';
import {computeStatus,type Event,type Health} from '../src/domain.js';
import {Store,openDb} from '../src/store.js';
import {ingest,initializeSources} from '../src/adapters.js';
import {ukraineSnapshot} from '../src/ukraine.js';
import {buildApp} from '../src/app.js';
import {correlate} from '../src/correlation.js';
const now=new Date('2026-09-22T12:00:00Z'),start='2026-09-22T10:00:00Z',end='2026-09-22T11:00:00Z';
const registry={states:[{regionId:'fixture-a',regionName:'Область А',regionType:'State',regionChildIds:[{regionId:'fixture-city',regionName:'Місто А',regionType:'Community',regionChildIds:[]}]},{regionId:'fixture-b',regionName:'Область Б',regionType:'State',regionChildIds:[]}]};
const regions=parseUaRegions(registry);
const active=(regionId='fixture-a',type='AIR')=>[{regionId,regionName:regions.find(r=>r.id===regionId)!.name,regionType:regions.find(r=>r.id===regionId)!.type,lastUpdate:start,activeAlerts:[{regionId,regionType:regions.find(r=>r.id===regionId)!.type,type,lastUpdate:start}]}];
const history=(ended=false,regionId='fixture-a',started=start,type='AIR')=>[{regionId,regionName:regions.find(r=>r.id===regionId)!.name,alarms:[{regionId,startDate:started,endDate:ended?end:null,alertType:type,isContinue:!ended}]}];
const parse=(ended=false,previous:Event[]=[])=>parseUaBatch(regions,ended?[]:active(),history(ended),previous,now).events[0];
const health=(state:Health['state']='HEALTHY'):Health=>({id:'UA',name:'UA',url:'https://map.ukrainealarm.com/',state,lastSuccess:now.toISOString(),lastFailure:null,lastItemTime:null,failureCount:0,responseTime:1,maxAgeSeconds:180,complete:false,uaMetadata:{regions,activeEventIds:[parse().id],lastActionIndex:1}});
test('UA official start ACTIVE, end ENDED, source time only, same stable cycle',()=>{
 const a=parse(),b=parse(true);assert.equal(a.lifecycle,'ACTIVE');assert.equal(b.lifecycle,'ENDED');assert.equal(a.id,b.id);assert.equal(a.validFrom,new Date(start).toISOString());assert.equal(a.validTo,null);assert.equal(b.validTo,new Date(end).toISOString());assert.equal(a.publishedAt,null);assert.equal(a.publicationDate,null);assert.equal(a.origin,'OFFICIAL_FOREIGN');assert.equal(a.geometry,null);assert.deepEqual(a.regions,[]);
});
test('UA simultaneous oblasts and exact city scope without parent expansion',()=>{
 const batch=parseUaBatch(regions,[...active(),...active('fixture-b'),...active('fixture-city')],[...history(),...history(false,'fixture-b'),...history(false,'fixture-city')],[],now);
 assert.equal(batch.events.length,3);const city=batch.events.find(e=>e.ukraine?.regionId==='fixture-city')!;assert.equal(city.ukraine?.regionType,'Community');assert.equal(city.ukraine?.parentRegionId,'fixture-a');assert.equal(city.geometry,null);
});
test('UA missing start/end retained, lastUpdate never invented as start/end',()=>{
 const e=parseUaBatch(regions,active(),[],[],now).events[0];assert.equal(e.lifecycle,'ACTIVE');assert.equal(e.validFrom,null);assert.equal(e.validTo,null);
 const missing=parseUaBatch(regions,[],[],[parse()],now).events[0];assert.equal(missing.lifecycle,'UNKNOWN');assert.equal(missing.validTo,null);
 const noEnd=history();noEnd[0].alarms[0].isContinue=false;assert.equal(parseUaBatch(regions,[],noEnd,[],now).events[0].lifecycle,'UNKNOWN');
});
test('UA new start creates distinct cycle; old unresolved cycle is not silently ended',()=>{
 const first=parse();const next=parseUaBatch(regions,active(),history(false,'fixture-a','2026-09-22T11:30:00Z'),[first],now).events;
 assert.equal(next.length,2);assert.notEqual(next[0].id,first.id);assert.equal(next.find(e=>e.id===first.id)?.lifecycle,'UNKNOWN');
});
test('UA INFO is separate from official alert and never an official warning',()=>{
 const e=parseUaBatch(regions,active('fixture-a','INFO'),history(false,'fixture-a',start,'INFO'),[],now).events[0];assert.equal(e.ukraine?.kind,'OFFICIAL_INFORMATION');assert.equal(e.officialWarning,false);
});
test('UA accepts documented nullable v3 metadata and keeps UNKNOWN informational',()=>{
 const activePayload=[{regionId:'fixture-a',regionName:'Область А',regionType:null,regionEngName:null,lastUpdate:start,activeAlerts:[{regionId:'fixture-a',regionType:null,type:'UNKNOWN',lastUpdate:start}]}];
 const historyPayload=[{regionId:'fixture-a',regionName:null,alarms:[{regionId:'fixture-a',startDate:start,endDate:null,alertType:'UNKNOWN',regionName:null,isContinue:true}]}];
 const e=parseUaBatch(regions,activePayload,historyPayload,[],now).events[0];
 assert.equal(e.ukraine?.alertType,'UNKNOWN');assert.equal(e.ukraine?.kind,'OFFICIAL_INFORMATION');assert.equal(e.officialWarning,false);assert.equal(e.severity,'INFORMATIONAL');
});
test('UA region registry accepts null child collections without inventing regions',()=>{
 const parsed=parseUaRegions({states:[{regionId:'fixture-null-children',regionName:'Область без підрегіонів',regionType:'State',regionChildIds:null}]});
 assert.deepEqual(parsed,[{id:'fixture-null-children',name:'Область без підрегіонів',type:'State',parentId:null}]);
});
test('UA changed contracts, unknown regions, contradictory end and unknown types fail closed',()=>{
 for(const broken of [{},[{regionName:'Область А',activeAlerts:[]}],active('fixture-a','MISSILE_POSITION')])assert.throws(()=>parseUaBatch(regions,broken,[],[],now));
 const h=history(true);h[0].alarms[0].isContinue=true;assert.throws(()=>parseUaBatch(regions,[],h,[],now),/UA_TIME_CONFLICT/);
 assert.throws(()=>parseUaBatch(regions,[],history(),[],now),/UA_SNAPSHOT_HISTORY_CONFLICT/);
 assert.throws(()=>parseUaRegions({states:[{...registry.states[0],regionType:'Null'}]}));
});
test('UA safe allowlist and missing key; credentials never in URL',async()=>{
 assert.equal(isAllowedUaUrl(UA_API+'/alerts'),true);for(const u of [UA_API+'/alerts?token=x',UA_API+'/alerts/regionHistory?regionId=x&token=y','https://evil.test/api/v3/alerts',UA_API+'/missiles'])assert.equal(isAllowedUaUrl(u),false);
 await assert.rejects(fetchUa(UA_API+'/alerts',''),/NOT_CONFIGURED_UA_API_KEY_MISSING/);
});
test('UA adapter reads documented endpoints and rejects mid-sync source change',async()=>{
 let status=0;const fetchText=async(url:string)=>{if(url.endsWith('/status'))return JSON.stringify({lastActionIndex:++status});if(url.endsWith('/regions'))return JSON.stringify(registry);if(url.endsWith('/alerts'))return JSON.stringify(active());return JSON.stringify([]);};
 await assert.rejects(ukraineAdapter.sync({now,fetchText}),/UA_SOURCE_CHANGED_DURING_SYNC/);
});
test('UA status accepts actionIndex compatibility alias used by current service',async()=>{
 let calls=0;const fetchText=async(url:string)=>{if(url.endsWith('/status'))return JSON.stringify({actionIndex:7});if(url.endsWith('/regions'))return JSON.stringify(registry);if(url.endsWith('/alerts'))return JSON.stringify([]);if(url.includes('/regionHistory'))return JSON.stringify([]);calls++;return JSON.stringify([]);};
 const batch=await ukraineAdapter.sync({now,fetchText});
 assert.equal(batch.uaMetadata.lastActionIndex,'7');assert.equal(batch.coverage,'ACTIVE_WARNINGS');assert.ok(calls>=0);
});
test('UA status preserves full signed-int64 precision from JSON token',async()=>{
 const huge='9223372036854775807';
 const fetchText=async(url:string)=>url.endsWith('/status')?'{"lastActionIndex":'+huge+'}':url.endsWith('/regions')?JSON.stringify(registry):url.endsWith('/alerts')?JSON.stringify([]):JSON.stringify([]);
 const batch=await ukraineAdapter.sync({now,fetchText});
 assert.equal(batch.uaMetadata.lastActionIndex,huge);
});
test('UA status diagnostics fail closed without exposing response values',async()=>{
 const cases=[
  [{},/UA_STATUS_INDEX_MISSING/],
  [{lastActionIndex:null},/UA_STATUS_INDEX_NULL/],
  [{lastActionIndex:'7'},/UA_STATUS_INDEX_STRING/],
  [[],/UA_STATUS_SHAPE_NOT_OBJECT/]
 ] as const;
 for(const [statusBody,pattern] of cases){
  const fetchText=async(url:string)=>url.endsWith('/status')?JSON.stringify(statusBody):url.endsWith('/regions')?JSON.stringify(registry):url.endsWith('/alerts')?JSON.stringify([]):JSON.stringify([]);
  await assert.rejects(ukraineAdapter.sync({now,fetchText}),pattern);
 }
});


test('UA alert, source failure or healthy UA alone never changes Polish status or correlation',()=>{
 const before=computeStatus([],[],'PL',now);assert.deepEqual(computeStatus([parse()],[health()],'PL',now),before);assert.equal(computeStatus([parse()],[health()],'04',now).hazardLevel,'UNKNOWN');assert.deepEqual(correlate([parse()]),[]);
});
test('UA polygons require exact official administrative match and never use city parent',()=>{
 // Synthetic geometry exclusively for validation; not shipped as real geography.
 const geo={type:'FeatureCollection',features:[{type:'Feature',properties:{adm1_name:'Область А',adm1_name1:null,adm1_name2:null,adm1_name3:null,adm1_pcode:'UA01'},geometry:{type:'Polygon',coordinates:[[[30,48],[31,48],[31,49],[30,48]]]}}]};
 const e=enrichUaGeometry([parse()],regions,geo)[0];assert.equal(e.geometry?.type,'Polygon');assert.equal(e.geometrySource,UA_BOUNDARY_SOURCE);
 const city=parseUaBatch(regions,active('fixture-city'),history(false,'fixture-city'),[],now).events[0];assert.equal(enrichUaGeometry([city],regions,geo)[0].geometry,null);
 assert.throws(()=>enrichUaGeometry([parse()],regions,{...geo,exceededTransferLimit:true}));
});
test('UA revisions, official correction, resync idempotence, backend restart and bounded offline snapshot',async()=>{
 const dir=await mkdtemp(join(tmpdir(),'ua-')),file=join(dir,'test.db');let db=openDb(undefined,file),store=new Store(db);await store.init();
 try{
  await store.applySync([parse()],health());await store.applySync([parse()],health());assert.equal((await store.timeline(parse().id)).length,1);
  await store.applySync([parse(true)],health());const correction={...parse(true),validTo:'2026-09-22T11:15:00.000Z'};await store.applySync([correction],health());assert.equal((await store.timeline(parse().id)).length,3);
  await db.close();db=openDb(undefined,file);store=new Store(db);await store.init();assert.equal((await store.get(parse().id))?.validTo,correction.validTo);
  const s=await ukraineSnapshot(store,now);assert.equal(s.revisions.length,3);assert.equal(s.coverage,'partial');assert.notEqual(s.hazardLevel,'NO_ACTIVE_WARNINGS');
  assert.equal((await ukraineSnapshot(store,new Date(+now+181000))).coverage,'stale');
  await store.setHealth(health('BROKEN'));const down=await ukraineSnapshot(store,now);assert.equal(down.healthStatus,'DOWN');assert.equal(down.events.length,1);assert.equal(down.events[0].freshness,'STALE');
 }finally{await db.close();await rm(dir,{recursive:true,force:true});}
});
test('UA stays NOT_CONFIGURED and preserves last-known-good while default runtime is disabled',async()=>{
 const db=openDb(undefined,':memory:'),store=new Store(db);await store.init();await initializeSources(store);
 try{
  await store.applySync([parse()],{...health(),lastSuccess:'2026-01-01T00:00:00Z'});
  let called=false;
  const dormant={...ukraineAdapter,minSyncIntervalSeconds:0,sync:async()=>{called=true;throw new Error('UA_CONTRACT_CHANGED');}};
  await ingest(store,[dormant]);
  const ua=(await store.health()).find(h=>h.id==='UA')!;
  assert.equal(called,false);assert.equal(ua.enabled,false);assert.equal(ua.state,'NOT_CONFIGURED');
  assert.equal((await store.events()).length,1);assert.equal((await store.timeline(parse().id)).length,1);
 }finally{await db.close();}
});
test('UA API snapshot and map separate from Polish feed; no operational position fields',async()=>{
 const db=openDb(undefined,':memory:'),store=new Store(db);await store.init();await store.applySync([parse()],health());const app=await buildApp(store);
 try{
  const result=await app.inject('/v1/ukraine');assert.equal(result.statusCode,200);assert.equal(result.headers['cache-control'],'no-store');assert.equal(result.json().events.length,1);
  const pl=(await app.inject('/v1/snapshot')).json();assert.equal(pl.events.length,0);assert.equal(pl.status.hazardLevel,'UNKNOWN');
  assert.equal((await app.inject('/v1/layers/events.geojson')).json().features.length,0);
  assert.equal((await app.inject('/v1/layers/ukraine.geojson')).json().features.length,0);
  for(const key of ['militaryPosition','trajectory','velocity','heading','unitId'])assert.equal(result.body.includes('"'+key+'"'),false);
 }finally{await app.close();await db.close();}
});
test('UA real PostGIS persistence, revisions and resync after reconnect',{skip:!process.env.TEST_DATABASE_URL},async()=>{
 let db=openDb(process.env.TEST_DATABASE_URL),store=new Store(db);await store.init();const e={...parse(),id:'UA-postgis-'+Date.now()};
 try{
  await store.put(e);await db.close();db=openDb(process.env.TEST_DATABASE_URL);store=new Store(db);await store.init();await store.put(e);assert.equal((await store.timeline(e.id)).length,1);await store.put({...e,lifecycle:'ENDED',validTo:new Date(end).toISOString()});assert.equal((await store.timeline(e.id)).length,2);
 }finally{await db.run('DELETE FROM event_revisions WHERE event_id=?',[e.id]);await db.close();}
});

test('UA geography distinguishes Kyiv city from Kyiv oblast despite common name stem',()=>{
 const city={id:'kyiv-city',name:'м. Київ',type:'State' as const,parentId:null},oblast={id:'kyiv-oblast',name:'Київська область',type:'State' as const,parentId:null};
 const geometry={type:'Polygon',coordinates:[[[30,48],[31,48],[31,49],[30,48]]]};
 const geo={type:'FeatureCollection',features:[['Київ','UA80'],['Київська','UA32']].map(([name,code])=>({type:'Feature',properties:{adm1_name:name,adm1_name1:null,adm1_name2:null,adm1_name3:null,adm1_pcode:code},geometry}))};
 for(const r of [city,oblast]){const e={...parse(),ukraine:{...parse().ukraine!,regionId:r.id,regionName:r.name}};assert.ok(enrichUaGeometry([e],[r],geo)[0].geometry);}
});

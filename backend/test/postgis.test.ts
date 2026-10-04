import test from 'node:test';
import assert from 'node:assert/strict';
import {Store,openDb} from '../src/store.js';
import {parseRcbArticle} from '../src/rcb-adapter.js';
import {readFileSync} from 'node:fs';
import {buildApp} from '../src/app.js';
import {parseShelterResource,parseShelterCsv} from '../src/shelter-adapter.js';
import {initializeSources} from '../src/adapters.js';

// CI supplies a disposable PostGIS service. Never run against a production DB.
test('PostGIS migration, SRID, GiST, bbox and geometry/payload atomicity', {skip:!process.env.TEST_DATABASE_URL},async()=>{
 const db=openDb(process.env.TEST_DATABASE_URL),store=new Store(db);
 const e=parseRcbArticle(readFileSync('test/fixtures/rcb-air.html','utf8'),'https://www.gov.pl/web/rcb/alert-rcb-test',new Date('2026-09-18T12:00:00Z'));
 e.id='fixture-postgis-'+Date.now();e.latitude=53.12;e.longitude=18.01;e.areaPrecision='EXACT';
 try{
  await store.init();await store.init();
  const version=await db.all('SELECT PostGIS_Version() AS version');assert.ok(version[0].version);
  await store.put(e);
  const beforeVersion=(await db.all('SELECT xmin::text AS version FROM shelters WHERE id=?',[points[0].id]))[0].version;
  const changed=[points[0],{...points[1],name:points[1].name+' updated'}];
  await store.applyShelterSync(changed,{...health,itemCount:2,sourceContentHash:'e'.repeat(64)});
  assert.equal((await db.all('SELECT xmin::text AS version FROM shelters WHERE id=?',[points[0].id]))[0].version,beforeVersion,'unchanged rows must not be rewritten');
  assert.equal((await store.shelterPage({regionId:'PL',q:'',offset:0,limit:50})).total,2);
  assert.equal((await store.shelterPage({regionId:'PL',q:'',offset:0,limit:50})).items.find(p=>p.id===points[1].id)!.name,changed[1].name);
  await store.applyShelterSync(points,health);
  const row=(await db.all('SELECT ST_SRID(geom) AS srid, ST_X(geom) AS lon FROM event_revisions WHERE event_id=?',[e.id]))[0];
  assert.equal(row.srid,4326);assert.equal(row.lon,18.01);
  assert.ok((await db.all("SELECT indexdef FROM pg_indexes WHERE indexname='event_geometry_gist'"))[0].indexdef.toString().includes('gist'));
  assert.ok((await store.spatialEvents([18,53,19,54])).some(v=>v.id===e.id));
  assert.ok(!(await store.spatialEvents([20,50,21,51])).some(v=>v.id===e.id));
  await store.put({...e,latitude:50.1,longitude:20.1});
  assert.ok(!(await store.spatialEvents([18,53,19,54])).some(v=>v.id===e.id),'old revision must not leak into map');
  const app=await buildApp(store);
  try{
   const layer=(await app.inject('/v1/layers/events.geojson?regionId=PL&bbox=20,50,21,51')).json();
   assert.ok(layer.features.some((f:{id:string})=>f.id===e.id));
  }finally{await app.close();}
  // A self-intersecting polygon passes structural JSON validation, but PostGIS
  // rejects it. The first valid item in the same batch must also roll back.
  const h=(await store.health()).find(v=>v.id==='RCB')!;
  await assert.rejects(store.applySync([
   {...e,id:e.id+'-rollback'},
   {...e,id:e.id+'-invalid',latitude:null,longitude:null,geometry:{type:'Polygon',coordinates:[[[0,0],[1,1],[0,1],[1,0],[0,0]]]}}
  ],{...h,state:'HEALTHY',lastSuccess:new Date().toISOString()}));
  assert.equal(await store.get(e.id+'-rollback'),null);
 }finally{
  await db.run('DELETE FROM event_revisions WHERE event_id LIKE ?',[e.id+'%']);await db.close();
 }
});

test('PostGIS shelters: exact points, regional bbox, full replacement and transaction rollback',{skip:!process.env.TEST_DATABASE_URL},async()=>{
 const db=openDb(process.env.TEST_DATABASE_URL),store=new Store(db);await store.init();await initializeSources(store);
 const points=parseShelterCsv(readFileSync('test/fixtures/psp-shelters.csv','utf8'),parseShelterResource(readFileSync('test/fixtures/psp-resource.json','utf8'),new Date('2026-09-19T12:00:00Z')));
 const original=(await store.health()).find(h=>h.id==='SHELTERS')!;
 const health={...original,state:'HEALTHY' as const,complete:true,coverage:'FACILITY_CATALOG' as const,itemCount:points.length,lastSuccess:new Date().toISOString(),sourceContentHash:'a'.repeat(64)};
 try{
  await store.applyShelterSync(points,health);
  const row=(await db.all('SELECT ST_SRID(geom) AS srid,ST_X(geom) AS lon FROM shelters WHERE id=?',[points[0].id]))[0];assert.equal(row.srid,4326);assert.equal(row.lon,points[0].longitude);
  assert.ok((await db.all("SELECT indexdef FROM pg_indexes WHERE indexname='shelter_geometry_gist'"))[0].indexdef.toString().includes('gist'));
  const bbox:[number,number,number,number]=[17.8,53,18.3,53.3];
  assert.equal((await store.shelterPage({regionId:'04',q:'',offset:0,limit:50,bbox})).total,3);
  assert.equal((await store.shelterPage({regionId:'02',q:'',offset:0,limit:50,bbox})).total,0);
  const app=await buildApp(store);try{const geo=(await app.inject('/v1/layers/shelters.geojson?bbox=17.8,53,18.3,53.3')).json();assert.equal(geo.features.length,3);}finally{await app.close();}
  // Bounded map contract, zoom-tier clustering, count conservation and atomic refresh.
  const mapApp=await buildApp(store);
  try{
   const detailPath='/v1/map/shelters?bbox=17.8,53,18.3,53.3&zoom=15';
   const detail=(await mapApp.inject(detailPath)).json();assert.equal(detail.features.length,3);assert.equal(detail.metadata.clustered,false);
   assert.equal((await mapApp.inject(detailPath+'&regionId=02')).json().metadata.total,0);
   const many=Array.from({length:1200},(_,i)=>({...points[0],id:'PSP-OZO-'+i.toString(16).toUpperCase().padStart(12,'0'),longitude:18+(i%40)*0.001,latitude:53.1+Math.floor(i/40)*0.001}));
   await store.applyShelterSync(many,{...health,itemCount:many.length,sourceContentHash:'c'.repeat(64)});
   assert.equal(Number((await db.all("SELECT COUNT(*) AS total FROM pg_tables WHERE schemaname='public' AND tablename LIKE 'shelters_stage_%'"))[0].total),0,'successful replacement must clean staging tables');

   const regionCluster=(await mapApp.inject('/v1/map/shelters?bbox=17.8,53,18.3,53.3&zoom=8')).json();
   assert.equal(regionCluster.metadata.total,1200);assert.equal(regionCluster.metadata.clustered,true);assert.equal(regionCluster.metadata.clusterTier,'REGION');assert.equal(regionCluster.features.length,1);assert.equal(regionCluster.features[0].properties.point_count,1200);

   const localPath='/v1/map/shelters?bbox=17.8,53,18.3,53.3&zoom=10';
   const localCluster=(await mapApp.inject(localPath)).json();
   assert.equal(localCluster.metadata.total,1200);assert.equal(localCluster.metadata.clustered,true);assert.equal(localCluster.metadata.clusterTier,'LOCAL');assert.ok(localCluster.features.length<=36);assert.equal(localCluster.features.reduce((n:number,f:any)=>n+f.properties.point_count,0),1200);

   const nearCluster=(await mapApp.inject('/v1/map/shelters?bbox=17.8,53,18.3,53.3&zoom=13')).json();
   assert.equal(nearCluster.metadata.clusterTier,'NEAR');assert.ok(nearCluster.features.length<=144);assert.equal(nearCluster.features.reduce((n:number,f:any)=>n+f.properties.point_count,0),1200);

   assert.equal((await mapApp.inject(localPath+'&availability=UNKNOWN')).json().metadata.total,many[0].availability==='UNKNOWN'?1200:0);
   const near=(await mapApp.inject('/v1/map/shelters?bbox=18,53.1,18.002,53.102&zoom=18')).json();assert.ok(near.metadata.total<500);assert.equal(near.metadata.clustered,false);assert.ok(near.features.every((f:any)=>f.geometry.coordinates[0]<=18.002));
   const overflow=(await mapApp.inject(detailPath)).json();
   assert.equal(overflow.metadata.clusterTier,'DETAIL_OVERFLOW');assert.ok(overflow.features.length<=324);
   assert.equal(overflow.features.reduce((n:number,f:any)=>n+f.properties.point_count,0),1200);
   const distant=[
    {...points[0],id:'PSP-OZO-FFFFFFFFFFF1',regionId:'02',longitude:16.98,latitude:51.1},
    {...points[0],id:'PSP-OZO-FFFFFFFFFFF2',regionId:'06',longitude:22.57,latitude:51.25},
   ];
   await store.applyShelterSync([...many,...distant],{...health,itemCount:1202,sourceContentHash:'d'.repeat(64)});
   const national=(await mapApp.inject('/v1/map/shelters?bbox=14,49,24.2,55&zoom=5.2')).json();
   assert.equal(national.metadata.total,1202);assert.equal(national.features.length,3);
   assert.equal(national.features.reduce((n:number,f:any)=>n+f.properties.point_count,0),1202);
   // Pan across distant voivodeships and back; selected home region must not leak.
   for(const [bbox,expected] of [['16.9,51,17.1,51.2',distant[0]],['22.4,51.1,22.7,51.4',distant[1]],['16.9,51,17.1,51.2',distant[0]]] as const){
    const pan=(await mapApp.inject(`/v1/map/shelters?bbox=${bbox}&zoom=15&regionId=PL`)).json();
    assert.equal(pan.metadata.total,1);assert.equal(pan.features[0].id,expected.id);
    assert.deepEqual(pan.features[0].geometry.coordinates,[expected.longitude,expected.latitude]);
   }
   await store.applyShelterSync(points,health);
   assert.equal((await mapApp.inject(detailPath)).json().metadata.version,health.sourceContentHash);
   assert.equal((await mapApp.inject(detailPath)).json().metadata.total,3);
  }finally{await mapApp.close();}
  // Force a real database error during replacement, after DELETE and INSERT.
  await db.run("CREATE OR REPLACE FUNCTION fixture_reject_shelter() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN RAISE EXCEPTION 'fixture_write_failure'; END $$");
  await db.run('CREATE TRIGGER fixture_shelter_failure BEFORE INSERT ON shelters FOR EACH ROW EXECUTE FUNCTION fixture_reject_shelter()');
  await assert.rejects(store.applyShelterSync([points[0]],{...health,itemCount:1,sourceContentHash:'b'.repeat(64)}),/fixture_write_failure/);
  assert.equal((await store.shelterPage({regionId:'PL',q:'',offset:0,limit:50})).total,3);
  assert.equal((await store.health()).find(h=>h.id==='SHELTERS')!.sourceContentHash,health.sourceContentHash);
  assert.equal(Number((await db.all("SELECT COUNT(*) AS total FROM pg_tables WHERE schemaname='public' AND tablename LIKE 'shelters_stage_%'"))[0].total),0,'failed replacement must clean staging tables');
  await db.run('DROP TRIGGER fixture_shelter_failure ON shelters');
  await store.applyShelterSync([points[0]],{...health,itemCount:1,sourceContentHash:'b'.repeat(64)});
  assert.equal((await store.shelterPage({regionId:'PL',q:'',offset:0,limit:50})).total,1);
 }finally{
  await db.run('DROP TRIGGER IF EXISTS fixture_shelter_failure ON shelters');await db.run('DROP FUNCTION IF EXISTS fixture_reject_shelter()');
  for(const row of await db.all("SELECT tablename FROM pg_tables WHERE schemaname='public' AND tablename LIKE 'shelters_stage_%'"))await db.run('DROP TABLE IF EXISTS '+String(row.tablename));
  for(const p of points)await db.run('DELETE FROM shelters WHERE id=?',[p.id]);await store.setHealth(original);await db.close();
 }
});

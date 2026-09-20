import test from 'node:test';
import assert from 'node:assert/strict';
import {Store,openDb} from '../src/store.js';
import {parseRcbArticle} from '../src/rcb-adapter.js';
import {readFileSync} from 'node:fs';
import {buildApp} from '../src/app.js';
import {parseShelterCatalog,parseShelterCsv} from '../src/shelter-adapter.js';
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
 const points=parseShelterCsv(readFileSync('test/fixtures/psp-shelters.csv','utf8'),parseShelterCatalog(readFileSync('test/fixtures/psp-catalog.xml','utf8'),new Date('2026-09-19T12:00:00Z')));
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
  // Bounded map contract, count conservation and atomic refresh with a new version.
  const mapApp=await buildApp(store);
  try{
   const path='/v1/map/shelters?bbox=17.8,53,18.3,53.3&zoom=10';
   const detail=(await mapApp.inject(path)).json();assert.equal(detail.features.length,3);assert.equal(detail.metadata.clustered,false);
   assert.equal((await mapApp.inject(path+'&regionId=02')).json().metadata.total,0);
   const many=Array.from({length:1200},(_,i)=>({...points[0],id:'PSP-OZO-'+i.toString(16).toUpperCase().padStart(12,'0'),longitude:18+(i%40)*0.001,latitude:53.1+Math.floor(i/40)*0.001}));
   await store.applyShelterSync(many,{...health,itemCount:many.length,sourceContentHash:'c'.repeat(64)});
   const clustered=(await mapApp.inject(path)).json();assert.equal(clustered.metadata.total,1200);assert.equal(clustered.metadata.clustered,true);assert.ok(clustered.features.length<=1089);assert.equal(clustered.features.reduce((n:number,f:any)=>n+f.properties.point_count,0),1200);
   assert.equal((await mapApp.inject(path+'&availability=UNKNOWN')).json().metadata.total,many[0].availability==='UNKNOWN'?1200:0);
   const near=(await mapApp.inject('/v1/map/shelters?bbox=18,53.1,18.002,53.102&zoom=18')).json();assert.ok(near.metadata.total<500);assert.equal(near.metadata.clustered,false);assert.ok(near.features.every((f:any)=>f.geometry.coordinates[0]<=18.002));
   await store.applyShelterSync(points,health);
   assert.equal((await mapApp.inject(path)).json().metadata.version,health.sourceContentHash);
   assert.equal((await mapApp.inject(path)).json().metadata.total,3);
  }finally{await mapApp.close();}
  // Force a real database error during replacement, after DELETE and INSERT.
  await db.run("CREATE OR REPLACE FUNCTION fixture_reject_shelter() RETURNS trigger LANGUAGE plpgsql AS $$ BEGIN RAISE EXCEPTION 'fixture_write_failure'; END $$");
  await db.run('CREATE TRIGGER fixture_shelter_failure BEFORE INSERT ON shelters FOR EACH ROW EXECUTE FUNCTION fixture_reject_shelter()');
  await assert.rejects(store.applyShelterSync([points[0]],{...health,itemCount:1,sourceContentHash:'b'.repeat(64)}),/fixture_write_failure/);
  assert.equal((await store.shelterPage({regionId:'PL',q:'',offset:0,limit:50})).total,3);
  assert.equal((await store.health()).find(h=>h.id==='SHELTERS')!.sourceContentHash,health.sourceContentHash);
  await db.run('DROP TRIGGER fixture_shelter_failure ON shelters');
  await store.applyShelterSync([points[0]],{...health,itemCount:1,sourceContentHash:'b'.repeat(64)});
  assert.equal((await store.shelterPage({regionId:'PL',q:'',offset:0,limit:50})).total,1);
 }finally{
  await db.run('DROP TRIGGER IF EXISTS fixture_shelter_failure ON shelters');await db.run('DROP FUNCTION IF EXISTS fixture_reject_shelter()');
  for(const p of points)await db.run('DELETE FROM shelters WHERE id=?',[p.id]);await store.setHealth(original);await db.close();
 }
});

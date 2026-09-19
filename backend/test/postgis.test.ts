import test from 'node:test';
import assert from 'node:assert/strict';
import {Store,openDb} from '../src/store.js';
import {parseRcbArticle} from '../src/rcb-adapter.js';
import {readFileSync} from 'node:fs';
import {buildApp} from '../src/app.js';

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

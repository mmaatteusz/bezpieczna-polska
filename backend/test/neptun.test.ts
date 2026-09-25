import test from 'node:test';
import assert from 'node:assert/strict';
import {mkdtemp,rm} from 'node:fs/promises';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {buildApp} from '../src/app.js';
import {openDb,Store} from '../src/store.js';
import {NEPTUN_MIN_PRECISION_KM,NEPTUN_SAFETY_DELAY_HOURS,neptunSnapshot,neptunTrackSchema,publicNeptunTrack,type NeptunTrack} from '../src/neptun.js';
import {NEPTUN_API,NEPTUN_PUBLIC_MIN_PRECISION_KM,neptunLiveAdapter,parseNeptunLive} from '../src/neptun-live-adapter.js';

const now=new Date('2026-09-22T12:00:00Z');
const track=(overrides:Partial<NeptunTrack>={}):NeptunTrack=>neptunTrackSchema.parse({
 id:'NEPTUN-fixture-1',
 title:'Historyczny przebieg obiektu testowego',
 description:'Syntetyczny fixture testowy; nie opisuje rzeczywistego zdarzenia.',
 objectType:'AIR_OBJECT',
 lifecycle:'ENDED',
 verification:'PROBABLE',
 startedAt:'2026-09-20T08:00:00Z',
 endedAt:'2026-09-20T10:00:00Z',
 directionText:'zachód → wschód',
 observations:[
  {id:'obs-1',observedAt:'2026-09-20T08:10:00Z',latitude:52.12345,longitude:20.98765,precisionKm:20,locationText:'obszar testowy A',verification:'PROBABLE',source:{id:'OSINT-A',name:'Źródło testowe A',url:'https://example.com/a',tier:3,origin:'OSINT'},note:null,correction:null},
  {id:'obs-2',observedAt:'2026-09-20T09:40:00Z',latitude:52.54321,longitude:21.45678,precisionKm:25,locationText:'obszar testowy B',verification:'PROBABLE',source:{id:'OSINT-B',name:'Źródło testowe B',url:'https://example.com/b',tier:3,origin:'OSINT'},note:null,correction:null}
 ],
 revision:1,
 reviewed:true,
 ...overrides
});

test('NEPTUN rejects active tracks, exact coordinates and inconsistent time',()=>{
 assert.throws(()=>neptunTrackSchema.parse({...track(),lifecycle:'ACTIVE'}));
 const tooExact={...track(),observations:[{...track().observations[0],precisionKm:1}]};
 assert.throws(()=>neptunTrackSchema.parse(tooExact));
 const afterEnd={...track(),observations:[...track().observations,{...track().observations[1],id:'obs-3',observedAt:'2026-09-20T11:00:00Z'}]};
 assert.throws(()=>neptunTrackSchema.parse(afterEnd));
});

test('NEPTUN public track coarsens coordinates and preserves provenance',()=>{
 const raw=track(),pub=publicNeptunTrack(raw);
 assert.notEqual(pub.observations[0].latitude,raw.observations[0].latitude);
 assert.notEqual(pub.observations[0].longitude,raw.observations[0].longitude);
 assert.ok(pub.observations.every(o=>o.precisionKm===null||o.precisionKm>=NEPTUN_MIN_PRECISION_KM));
 assert.equal(pub.observations[0].source.url,'https://example.com/a');
});

test('NEPTUN live parser removes operational motion data and coarsens positions',()=>{
 const input={
  serverTime:now.toISOString(),
  threats:[{
   id:'trk-live-1',type:'uav',title:'БпЛА',region:'Одеська область',district:'Одеський район',locality:'Чорноморськ',
   lat:46.30123,lon:30.65123,heading:42,confidenceLevel:'high',sourceCount:3,count:2,updatedAt:now.toISOString(),
   status:'active',explanationShort:'БпЛА у регіоні',velocity:{bearingDeg:42,speedKmh:150},confirmedAt:now.toISOString(),
   uncertaintyKm:4,positionQuality:'confirmed',advisory:false,areaOnly:false
  },{
   id:'trk-area',type:'missile',title:'Ракета',region:'Одеська область',district:null,locality:'Одеська область',
   lat:46.5,lon:30.7,heading:null,confidenceLevel:'medium',sourceCount:1,count:null,updatedAt:now.toISOString(),
   status:'active',explanationShort:'Ракета на область',velocity:null,confirmedAt:null,
   uncertaintyKm:20,positionQuality:'approx',advisory:false,areaOnly:true
  }]
 };
 const parsed=parseNeptunLive(input,now);
 assert.equal(parsed.threats.length,2);
 const point=parsed.threats[0];
 assert.ok(point.precisionKm!>=NEPTUN_PUBLIC_MIN_PRECISION_KM);
 assert.notEqual(point.latitude,input.threats[0].lat);
 assert.notEqual(point.longitude,input.threats[0].lon);
 assert.equal('heading' in point,false);
 assert.equal('velocity' in point,false);
 assert.equal('confirmedAt' in point,false);
 assert.equal('positionQuality' in point,false);
 assert.equal('explanationShort' in point,false);
 assert.equal(parsed.threats[1].latitude,null);
 assert.equal(parsed.threats[1].longitude,null);
});

test('NEPTUN live parser maps new upstream categories to unknown without dropping snapshot',()=>{
 const input={serverTime:now.toISOString(),threats:[{
  id:'trk-new-type',type:'new-upstream-category',title:'Nowy typ obiektu',region:'Київська область',district:'',locality:'Київ',
  lat:50.45,lon:30.52,heading:90,confidenceLevel:'medium',sourceCount:1,count:null,updatedAt:now.toISOString(),
  status:'active',explanationShort:'Nowa kategoria źródła',confirmedAt:now.toISOString(),uncertaintyKm:10,positionQuality:'approx'
 }]};
 const parsed=parseNeptunLive(input,now);
 assert.equal(parsed.threats.length,1);
 assert.equal(parsed.threats[0].type,'unknown');
 assert.ok(parsed.threats[0].precisionKm!>=NEPTUN_PUBLIC_MIN_PRECISION_KM);
 assert.equal('heading' in parsed.threats[0],false);
 assert.equal('explanationShort' in parsed.threats[0],false);
});

test('NEPTUN live adapter uses the public endpoint and stores no event object',async()=>{
 let requested='';
 const batch=await neptunLiveAdapter.sync({
  now,
  fetchText:async url=>{
   requested=url;
   return JSON.stringify({serverTime:now.toISOString(),threats:[]});
  }
 });
 assert.equal(requested,NEPTUN_API);
 assert.deepEqual(batch.events,[]);
 assert.equal(batch.neptunMetadata?.serverTime,now.toISOString());
});

test('NEPTUN persistence is revisioned and snapshot is historical-only with safety delay',async()=>{
 const dir=await mkdtemp(join(tmpdir(),'neptun-')),file=join(dir,'test.db');
 let db=openDb(undefined,file),store=new Store(db);await store.init();
 try{
  await store.putNeptunTrack(track(),'operator','Initial historical review',0);
  await store.putNeptunTrack(track(),'operator','Idempotent historical review',1);
  assert.equal((await store.neptunTimeline(track().id)).length,1);
  const corrected=track({directionText:'zachód → północny wschód'});
  await store.putNeptunTrack(corrected,'operator','Direction corrected from source review',1);
  assert.equal((await store.neptunTimeline(track().id)).length,2);
  await db.close();db=openDb(undefined,file);store=new Store(db);await store.init();
  assert.equal((await store.neptunTrack(track().id))?.revision,2);
  const snapshot=await neptunSnapshot(store,now);
  assert.equal(snapshot.mode,'LIVE_AND_HISTORY');
  assert.equal(snapshot.schemaVersion,2);
  assert.equal(snapshot.safetyDelayHours,NEPTUN_SAFETY_DELAY_HOURS);
  assert.equal(snapshot.tracks.length,1);
  assert.equal(snapshot.map.features.length,1);
  assert.equal(snapshot.map.features[0].geometry.type,'LineString');
  const recent=track({id:'NEPTUN-recent',startedAt:'2026-09-22T09:00:00Z',endedAt:'2026-09-22T10:00:00Z',observations:[
   {...track().observations[0],id:'recent-1',observedAt:'2026-09-22T09:10:00Z'},
   {...track().observations[1],id:'recent-2',observedAt:'2026-09-22T09:50:00Z'}
  ]});
  await store.putNeptunTrack(recent,'operator','Recent track retained internally but not published',0);
  assert.equal((await neptunSnapshot(store,now)).tracks.some(t=>t.id==='NEPTUN-recent'),false);
 }finally{await db.close();await rm(dir,{recursive:true,force:true});}
});

test('NEPTUN API is separate from Polish snapshot and admin requires authorization',async()=>{
 const db=openDb(undefined,':memory:'),store=new Store(db);await store.init();
 await store.putNeptunTrack(track(),'operator','Historical fixture review',0);
 const token='0123456789abcdef0123456789abcdef',app=await buildApp(store,token);
 try{
  const n=await app.inject('/v1/neptun');assert.equal(n.statusCode,200);assert.equal(n.json().tracks.length,1);
  const map=await app.inject('/v1/layers/neptun.geojson');assert.equal(map.statusCode,200);assert.equal(map.json().features.length,1);
  const pl=await app.inject('/v1/snapshot');assert.equal(pl.statusCode,200);assert.equal(pl.json().events.some((e:any)=>String(e.id).startsWith('NEPTUN-')),false);assert.equal(pl.json().capabilities.neptun,true);
  const denied=await app.inject({method:'POST',url:'/admin/neptun',payload:{track:track(),expectedRevision:1,reason:'Correction after public-source review'}});assert.equal(denied.statusCode,401);
  const accepted=await app.inject({method:'POST',url:'/admin/neptun',headers:{authorization:'Bearer '+token},payload:{track:{...track(),directionText:'kierunek skorygowany'},expectedRevision:1,reason:'Correction after public-source review'}});assert.equal(accepted.statusCode,200);
  assert.equal((await store.neptunTrack(track().id))?.revision,2);
 }finally{await app.close();await db.close();}
});

test('NEPTUN PostGIS-independent revision storage survives database reconnect',{skip:!process.env.TEST_DATABASE_URL},async()=>{
 let db=openDb(process.env.TEST_DATABASE_URL),store=new Store(db);await store.init();const id='NEPTUN-postgis-'+Date.now(),t=track({id});
 try{
  await store.putNeptunTrack(t,'operator','PostGIS persistence fixture',0);
  await db.close();db=openDb(process.env.TEST_DATABASE_URL);store=new Store(db);await store.init();
  assert.equal((await store.neptunTrack(id))?.id,id);
  await store.putNeptunTrack({...t,directionText:'korekta'},'operator','PostGIS correction fixture',1);
  assert.equal((await store.neptunTimeline(id)).length,2);
 }finally{await db.run('DELETE FROM neptun_track_revisions WHERE track_id=?',[id]);await db.close();}
});

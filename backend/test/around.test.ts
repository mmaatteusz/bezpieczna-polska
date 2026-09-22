import test from 'node:test';
import assert from 'node:assert/strict';
import {buildApp} from '../src/app.js';
import {eventSchema,type Event} from '../src/domain.js';
import {Store,openDb} from '../src/store.js';

const now=new Date('2026-09-22T06:00:00Z');

function event(id:string,patch:Partial<Event>={}):Event{
 return eventSchema.parse({
  id:'around-fixture-'+id,
  title:'Zdarzenie testowe',
  description:'Oficjalny komunikat używany wyłącznie do testu zapytania przestrzennego.',
  eventType:'RESCUE',
  severity:'NORMAL',
  verification:'CONFIRMED',
  lifecycle:'ACTIVE',
  messageContext:'ACTUAL',
  regions:['04'],
  geographicScope:'REGIONAL',
  publishedAt:'2026-09-22T05:30:00Z',
  publicationDate:'2026-09-22',
  retrievedAt:'2026-09-22T05:31:00Z',
  validFrom:'2026-09-22T05:00:00Z',
  validTo:'2026-09-22T08:00:00Z',
  sources:[{id:'RCB',name:'RCB',url:'https://www.gov.pl/web/rcb/',tier:1}],
  instructions:[],
  officialWarning:true,
  reviewed:false,
  revision:1,
  correction:null,
  latitude:53.123,
  longitude:18.008,
  geometry:null,
  locationText:'Bydgoszcz',
  areaPrecision:'EXACT',
  adapterVersion:'fixture',
  sourceContentHash:'a'.repeat(64),
  isDemo:false,
  ...patch,
 });
}

test('around endpoint requires PostGIS and validates coordinates',async()=>{
 const store=new Store(openDb(undefined,':memory:'));await store.init();
 const app=await buildApp(store);
 try{
  assert.equal((await app.inject('/v1/around?lat=53.1&lon=18.0')).statusCode,503);
  assert.equal((await app.inject('/v1/around?lat=999&lon=18.0')).statusCode,400);
 }finally{await app.close();await store.db.close();}
});

test('PostGIS around keeps distance and regional relevance separate',{skip:!process.env.TEST_DATABASE_URL},async()=>{
 const db=openDb(process.env.TEST_DATABASE_URL),store=new Store(db);await store.init();
 const ids=['near','far','regional','subset','ended','exercise'];
 try{
  await store.put(event('near'));
  await store.put(event('far',{latitude:54.35,longitude:18.65,locationText:'Gdańsk'}));
  await store.put(event('regional',{latitude:null,longitude:null,geometry:null,locationText:null,areaPrecision:'PROVINCE'}));
  await store.put(event('subset',{latitude:null,longitude:null,geometry:null,locationText:'Powiat bydgoski',areaPrecision:'PROVINCE_SUBSET'}));
  await store.put(event('ended',{lifecycle:'ENDED'}));
  await store.put(event('exercise',{messageContext:'EXERCISE'}));
  const app=await buildApp(store);
  try{
   const response=await app.inject('/v1/around?lat=53.12&lon=18.01&radiusKm=5&regionId=04');
   assert.equal(response.statusCode,200);
   const body=response.json();
   assert.equal(body.schemaVersion,1);
   assert.deepEqual(body.query,{latitude:53.12,longitude:18.01,radiusKm:5,regionId:'04'});
   assert.equal(body.coverage.spatial,'PARTIAL_GEOMETRY_ONLY');
   assert.equal(body.coverage.regional,'EXPLICIT_NATIONAL_OR_PROVINCE_SCOPE_ONLY');
   assert.match(body.coverage.statement,/Brak geometrii/);
   assert.deepEqual(body.nearbyEvents.map((r:any)=>r.event.id),['around-fixture-near']);
   assert.equal(body.nearbyEvents[0].relevance,'NEARBY');
   assert.ok(body.nearbyEvents[0].distanceMeters>=0&&body.nearbyEvents[0].distanceMeters<1000);
   assert.deepEqual(body.regionalEvents.map((r:any)=>r.event.id),['around-fixture-regional']);
   assert.equal(body.regionalEvents[0].relevance,'REGION_RELEVANT');
   assert.equal(body.regionalEvents[0].event.geometry,null);
   assert.ok(Array.isArray(body.nearestShelters.items));
   assert.ok('health' in body.nearestShelters);

   const noRegion=(await app.inject('/v1/around?lat=53.12&lon=18.01&radiusKm=5')).json();
   assert.deepEqual(noRegion.regionalEvents,[]);
   assert.equal(noRegion.coverage.regional,'NOT_REQUESTED');

   assert.equal((await app.inject('/v1/around?lat=91&lon=18.01')).statusCode,400);
   assert.equal((await app.inject('/v1/around?lat=53.12&lon=18.01&radiusKm=101')).statusCode,400);
   assert.equal((await app.inject('/v1/around?lat=53.12&lon=18.01&regionId=XX')).statusCode,400);
  }finally{await app.close();}
 }finally{
  for(const id of ids)await db.run('DELETE FROM event_revisions WHERE event_id=?',['around-fixture-'+id]);
  await db.run("DELETE FROM incident_revisions WHERE payload LIKE '%around-fixture-%'");
  await db.close();
 }
});

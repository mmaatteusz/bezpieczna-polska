import test from 'node:test';import assert from 'node:assert/strict';
import {mapQuery,mapLayers} from '../src/map-layers.js';import {Store,openDb} from '../src/store.js';import {buildApp} from '../src/app.js';
test('map rejects missing, reversed, malformed bbox, unknown region/filter and excessive zoom',()=>{
 for(const q of [{},{bbox:'1,2,3',zoom:5},{bbox:'1,2,1,4',zoom:5},{bbox:'181,0,182,2',zoom:5},{bbox:'1,2,3,4',zoom:30},{bbox:'1,2,3,4',zoom:5,availability:'OPEN_NOW'},{bbox:'1,2,3,4',zoom:5,regionId:'99'}])assert.equal(mapQuery.safeParse(q).success,false);
 assert.equal(mapQuery.parse({bbox:'14,49,25,55',zoom:5}).regionId,'PL');
 assert.equal(mapLayers.find(l=>l.id==='NEPTUN')?.authority,'OSINT');assert.equal(mapLayers.filter(l=>l.enabled).length,2);
});
test('viewport requires actual PostGIS; missing data is never fabricated',async()=>{
 const db=openDb(undefined,':memory:'),store=new Store(db);await store.init();const app=await buildApp(store);
 try{assert.equal((await app.inject('/v1/map/shelters?bbox=14,49,25,55&zoom=5')).statusCode,503);assert.equal((await app.inject('/v1/map/shelters')).statusCode,400);}finally{await app.close();await db.close();}
});

import assert from 'node:assert/strict';
import {openDb,Store} from '../dist/store.js';
import {parseUaBatch} from '../dist/ukraine-adapter.js';
const db=openDb(process.env.TEST_DATABASE_URL),store=new Store(db);await store.init();
const mode=process.argv[2],id='UA-ci-restart';
try{
 if(mode==='seed'){
  const r={id:'fixture',name:'Fixture region',type:'State',parentId:null};
  const e=parseUaBatch([r],[{regionId:'fixture',regionName:r.name,regionType:'State',activeAlerts:[{regionId:'fixture',regionType:'State',type:'AIR',lastUpdate:'2026-01-01T10:00:00Z'}]}],[],[],new Date('2026-01-01T11:00:00Z')).events[0];
  await store.put({...e,id});
 }else{
  const e=await store.get(id);assert.ok(e);assert.equal(e.lifecycle,'ACTIVE');assert.equal(e.validTo,null);await store.put(e);assert.equal((await store.timeline(id)).length,1);await db.run('DELETE FROM event_revisions WHERE event_id=?',[id]);
 }
 console.log('UA PostGIS process/database restart '+mode+': PASS');
}finally{await db.close();}

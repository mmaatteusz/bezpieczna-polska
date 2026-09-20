import {mkdir,writeFile} from 'node:fs/promises';
import {Store,openDb} from '../dist/store.js';
import {ingest} from '../dist/adapters.js';
import {shelterAdapter} from '../dist/shelter-adapter.js';
import {buildApp} from '../dist/app.js';
const directory=process.argv[2];if(!directory)throw new Error('Supply output directory');
const db=openDb(process.env.TEST_DATABASE_URL,process.env.SQLITE_PATH??':memory:'),store=new Store(db);
try{
 await store.init();await ingest(store,[shelterAdapter]);
 const source=(await store.health()).find(s=>s.id==='SHELTERS');
 if(source?.state!=='HEALTHY'){
  await mkdir(directory,{recursive:true});
  await writeFile(`${directory}/shelters-live-failure.json`,JSON.stringify({observedAt:new Date().toISOString(),database:db.kind,source},null,2)+'\n');
  throw new Error(`PSP_LIVE_FAILED: ${source?.errorCode}`);
 }
 const app=await buildApp(store);
 try{
  const national=(await app.inject('/v1/shelters?limit=1')).json();
  const region=(await app.inject('/v1/shelters?regionId=04&limit=1')).json();
  const city=(await app.inject('/v1/shelters?regionId=04&q=Bydgoszcz&limit=3')).json();
  const mapPath='/v1/layers/shelters.geojson?regionId=04&limit=3'+(db.kind==='postgres'?'&bbox=17.8,53,18.3,53.3':'');
  const geo=(await app.inject(mapPath)).json();
  if(national.total!==source.itemCount||!city.items.length||!geo.features.length)throw new Error('PSP_LIVE_API_FAILED');
  const report={observedAt:new Date().toISOString(),database:db.kind,source,total:national.total,kujawskoPomorskie:region.total,bydgoszcz:city.total,examples:city.items,geojson:geo};
  await mkdir(directory,{recursive:true});await writeFile(`${directory}/shelters-live.json`,JSON.stringify(report,null,2)+'\n');
  console.log(JSON.stringify({observedAt:report.observedAt,database:db.kind,total:report.total,kujawskoPomorskie:report.kujawskoPomorskie,bydgoszcz:report.bydgoszcz,source,examples:city.items},null,2));
 }finally{await app.close();}
}finally{await db.close();}

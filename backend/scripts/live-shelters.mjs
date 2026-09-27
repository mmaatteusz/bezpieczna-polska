import {mkdir,writeFile} from 'node:fs/promises';
import {Store,openDb} from '../dist/store.js';
import {ingest} from '../dist/adapters.js';
import {shelterAdapter,SHELTER_DOWNLOAD,SHELTER_RESOURCE} from '../dist/shelter-adapter.js';
import {buildApp} from '../dist/app.js';
const directory=process.argv[2];if(!directory)throw new Error('Supply output directory');
async function redirectObservation(url){
 const chain=[];let current=url;
 for(let i=0;i<5;i++){
  const response=await fetch(current,{redirect:'manual',signal:AbortSignal.timeout(20000),headers:{'User-Agent':'BezpiecznaPolska-live-source-observer/1.0'}});
  const location=response.headers.get('location'),next=location?new URL(location,current):null;
  chain.push({status:response.status,url:new URL(current).origin+new URL(current).pathname,location:next?next.origin+next.pathname:null});
  if(!next||![301,302,303,307,308].includes(response.status))break;
  current=next.href;
 }
 return chain;
}

async function publicApiObservation(url){
 try{
  const response=await fetch(url,{redirect:'manual',signal:AbortSignal.timeout(15000),headers:{'User-Agent':'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 Chrome/140 Safari/537.36','Accept':'application/json,text/plain,*/*'}});
  const location=response.headers.get('location'),contentType=response.headers.get('content-type');
  let body='';
  if(response.body){
   const reader=response.body.getReader();let size=0;
   while(size<4096){const {done,value}=await reader.read();if(done)break;size+=value.length;body+=new TextDecoder().decode(value,{stream:true});}
   await reader.cancel().catch(()=>{});
  }
  return {status:response.status,contentType,location:location?new URL(location,url).origin+new URL(location,url).pathname:null,bodyPrefix:body.slice(0,500).replace(/\s+/g,' ')};
 }catch(error){return {error:error instanceof Error?error.message:'probe failed'};}
}
const db=openDb(process.env.TEST_DATABASE_URL,process.env.SQLITE_PATH??':memory:'),store=new Store(db);
try{
 const candidates=[
  SHELTER_DOWNLOAD,
  'https://api.dane.gov.pl/resources/1393918/download/',
  'https://api.dane.gov.pl/1.4/resources/1393918/download/'
 ];
 for(const candidate of candidates){
  const observation=await redirectObservation(candidate).catch(error=>[{error:error instanceof Error?error.message:'probe failed'}]);
  console.log('SHELTER_DOWNLOAD_CANDIDATE',candidate,JSON.stringify(observation));
 }
 const apiCandidates=[
  'https://gdziesieukryc.pl/api/health',
  'https://gdziesieukryc.pl/api/shelters/count',
  'https://gdziesieukryc.pl/api/shelters?limit=1',
  'https://gdziesieukryc.pl/api/shelters',
  'https://gdziesieukryc.pl/api/points/count',
  'https://gdziesieukryc.pl/api/points?limit=1'
 ];
 for(const candidate of apiCandidates)console.log('SHELTER_PUBLIC_API_CANDIDATE',candidate,JSON.stringify(await publicApiObservation(candidate)));
 const tabularCandidates=[
  'https://api.dane.gov.pl/1.4/resources/1393918/data',
  'https://api.dane.gov.pl/1.4/resources/1393918/data?page=1&per_page=1',
  'https://api.dane.gov.pl/1.4/resources/1393918/data?page[number]=1&page[size]=1',
  'https://api.dane.gov.pl/1.4/resources/1393918/data?limit=1&offset=0',
  'https://api.dane.gov.pl/resources/1393918,punkty-schronienia-dane-csv/jsonld'
 ];
 for(const candidate of tabularCandidates)console.log('SHELTER_TABULAR_API_CANDIDATE',candidate,JSON.stringify(await publicApiObservation(candidate)));
 try{
  const response=await fetch(SHELTER_RESOURCE,{signal:AbortSignal.timeout(20000),headers:{'User-Agent':'BezpiecznaPolska-live-source-observer/1.0','Accept':'application/json'}});
  const root=await response.json(),attributes=root?.data?.attributes??{};
  const publicUrls=Object.fromEntries(Object.entries(attributes).filter(([key,value])=>typeof value==='string'&&(key.includes('url')||key.includes('link')||String(value).startsWith('https://'))));
  console.log('SHELTER_RESOURCE_PUBLIC_URL_FIELDS',JSON.stringify(publicUrls));
 }catch(error){console.log('SHELTER_RESOURCE_PUBLIC_URL_FIELDS_ERROR',error instanceof Error?error.message:'probe failed');}
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

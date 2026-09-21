import {sgAdapter,isAllowedSgUrl} from './sg-adapter.js';
import {certAdapter,CERT_FEED,CSIRT_GOV_RSS_PAGE} from './cyber-adapter.js';
import {paaAdapter} from './paa-adapter.js';
import {wczkAdapters,WCZK_PODKARPACKIE} from './wczk-adapter.js';
import {securityLevelsAdapter} from './security-level-adapter.js';
import * as cheerio from 'cheerio';
import {DateTime} from 'luxon';
import {eventSchema,REGIONS,type Event,type Health} from './domain.js';
import {Store} from './store.js';
import {SOURCES, type SourceAdapter} from './source-adapter.js';
import {rcbAdapter} from './rcb-adapter.js';
import {shelterAdapter,SHELTER_DATASET,SHELTER_RESOURCE,SHELTER_ORIGIN_CSV,SHELTER_ARCHIVE} from './shelter-adapter.js';
export {SOURCES} from './source-adapter.js';
export {parseRcbIndex,parseRcbArticle} from './rcb-adapter.js';
export async function initializeSources(store:Store){
 const existing=await store.health();
 for(const s of SOURCES){
  const previous=existing.find(h=>h.id===s.id);
  if(!previous)await store.setHealth({...s,state:'NOT_CONFIGURED',lastSuccess:null,lastFailure:null,lastItemTime:null,failureCount:0,responseTime:null,maxAgeSeconds:s.id==='SHELTERS'?172800:s.id==='LEVELS'?7200:s.id==='CERT'||s.id==='SG'?3600:s.id.startsWith('WCZK-')?1800:900,complete:false,lastAttempt:null,errorCode:null,itemCount:0,adapterVersion:null});
  else if(!s.enabled)await store.setHealth({...previous,...s,state:'NOT_CONFIGURED',complete:false});
  else await store.setHealth({...previous,...s,maxAgeSeconds:s.id==='SHELTERS'?172800:s.id==='LEVELS'?7200:s.id==='CERT'||s.id==='SG'?3600:s.id.startsWith('WCZK-')?1800:900});
 }
}
export function messageContext(text:string):Event['messageContext']{return /ćwicz|cwicz|exercise/i.test(text)?'EXERCISE':/test syren|test systemu/i.test(text)?'TEST':'UNKNOWN';}
function base(id:string,title:string,description:string,sourceId:string,url:string,now:Date):Event{return eventSchema.parse({id,title,description,eventType:'OTHER',severity:'NORMAL',verification:'UNVERIFIED',lifecycle:'UNKNOWN',messageContext:messageContext(title+' '+description),regions:[],geographicScope:'UNKNOWN',publishedAt:null,retrievedAt:now.toISOString(),validFrom:null,validTo:null,sources:[{id:sourceId,name:SOURCES.find(s=>s.id===sourceId)!.name,url,tier:1}],instructions:[],officialWarning:false,reviewed:false,revision:1,correction:null,latitude:null,longitude:null,isDemo:false});}
export function parseRso(xml:string,now=new Date()):Event[]{
 if(/<!DOCTYPE|<!ENTITY/i.test(xml))throw new Error('UNSAFE_XML');
 const $=cheerio.load(xml,{xml:true});const total=Number($('pagination_info').attr('totalItems'));const nodes=$('news');if(!Number.isInteger(total)||total!==nodes.length||!nodes.length)throw new Error('RSO_INCOMPLETE_OR_EMPTY');
 return nodes.map((_,node)=>{const n=$(node);const text=(k:string)=>n.children(k).text().trim();const id=text('id');if(!/^\d+$/.test(id))throw new Error('RSO_ID_INVALID');
  const e=base('RSO-'+id,text('title'),text('content')||text('shortcut'),'RSO',`https://komunikaty.tvp.pl/komunikaty/${id}/detale`,now);
  const date=(v:string)=>{if(!v)return null;const d=DateTime.fromFormat(v,'yyyy-MM-dd HH:mm:ss',{zone:'Europe/Warsaw'});if(!d.isValid||d.getPossibleOffsets().length!==1)throw new Error('RSO_DATE_INVALID_OR_AMBIGUOUS');return d.toUTC().toISO();};
  e.publishedAt=date(text('created_at'));e.validFrom=date(text('valid_from'));e.validTo=date(text('valid_to'));if(e.validFrom&&e.validTo&&e.validTo<=e.validFrom)throw new Error('RSO_DATE_ORDER');
  e.lifecycle=e.validFrom&&Date.parse(e.validFrom)>now.getTime()?'SCHEDULED':e.validTo&&Date.parse(e.validTo)<=now.getTime()?'EXPIRED':e.validTo?'ACTIVE':'UNKNOWN';
  e.regions=n.find('province').map((_,p)=>{const name=$(p).text().toLocaleLowerCase('pl');const code=Object.keys(REGIONS).find(k=>REGIONS[k].toLocaleLowerCase('pl')===name);if(!code)throw new Error('RSO_UNKNOWN_REGION');return code;}).get();e.geographicScope=e.regions.length?'REGIONAL':'UNKNOWN';
  const alarm=text('rso_alarm');if(!['0','1'].includes(alarm))throw new Error('RSO_ALARM_INVALID');e.severity=alarm==='1'?'HIGH':'NORMAL';
  for(const k of ['latitude','longitude'] as const){if(text(k))e[k]=Number(text(k));}
  return eventSchema.parse(e);
 }).get();
}
const RSO_XML='https://komunikaty.tvp.pl/komunikatyxml/wszystkie/wszystkie/0?_format=xml';
export const rsoAdapter:SourceAdapter={
 id:'RSO',version:'1.0.0',minSyncIntervalSeconds:300,
 async sync({now,fetchText}){
  const xml=await fetchText(RSO_XML),events=parseRso(xml,now);
  return {events,complete:true,coverage:'ACTIVE_WARNINGS',pagesFetched:1};
 }
};
export async function fetchPublic(url:string):Promise<string>{
 const shelterMeta=[SHELTER_DATASET,SHELTER_RESOURCE].includes(url),shelterCurrent=url===SHELTER_ORIGIN_CSV,certFeed=url===CERT_FEED,csirtRssPage=url===CSIRT_GOV_RSS_PAGE,sgSource=isAllowedSgUrl(url);
 const u=new URL(url);if(u.protocol!=='https:'||u.username||u.password||u.port||(!shelterMeta&&!shelterCurrent&&!certFeed&&!csirtRssPage&&!sgSource&&url!==WCZK_PODKARPACKIE&&!['www.gov.pl','komunikaty.tvp.pl'].includes(u.hostname)))throw new Error('SOURCE_URL_DENIED');
 if(shelterCurrent&&(u.hostname!=='gdziesieukryc.pl'||u.pathname!=='/PS_XML/punkty_schronienia.csv'||u.search||u.hash))throw new Error('SOURCE_URL_DENIED');
 if(certFeed&&(u.hostname!=='moje.cert.pl'||u.pathname!=='/advisory_feed/advisory/feed/'||u.search||u.hash))throw new Error('SOURCE_URL_DENIED');
 if(csirtRssPage&&(u.hostname!=='www.csirt.gov.pl'||u.pathname!=='/cer/rss'||u.search||u.hash))throw new Error('SOURCE_URL_DENIED');
 if(sgSource&&!isAllowedSgUrl(u.href))throw new Error('SOURCE_URL_DENIED');
 const response=await fetch(u,{redirect:'error',signal:AbortSignal.timeout(shelterCurrent?90000:20000),headers:{'User-Agent':'BezpiecznaPolska-preview/0.1 (source contract evaluation)','Accept':'text/html,application/xml,application/json,text/csv'}});
 if(!response.ok)throw new Error(`SOURCE_HTTP_${response.status}`);if(!response.body)throw new Error('SOURCE_EMPTY_BODY');
 const limit=(shelterCurrent?64:4)*1024*1024;let size=0;const chunks:Uint8Array[]=[];
 for await(const chunk of response.body){size+=chunk.length;if(size>limit)throw new Error('SOURCE_TOO_LARGE');chunks.push(chunk);}
 return new TextDecoder('utf-8',{fatal:true}).decode(Buffer.concat(chunks));
}
export async function fetchPublicBytes(url:string):Promise<Uint8Array>{
 if(url!==SHELTER_ARCHIVE)throw new Error('SOURCE_URL_DENIED');
 const u=new URL(url);if(u.protocol!=='https:'||u.hostname!=='api.dane.gov.pl'||u.username||u.password||u.port||u.search||u.hash)throw new Error('SOURCE_URL_DENIED');
 const response=await fetch(u,{redirect:'error',signal:AbortSignal.timeout(120000),headers:{'User-Agent':'BezpiecznaPolska-preview/0.1 (official open-data archive)','Accept':'application/zip'}});
 if(!response.ok)throw new Error(`SOURCE_HTTP_${response.status}`);if(!response.body)throw new Error('SOURCE_EMPTY_BODY');
 const declared=Number(response.headers.get('content-length')??'0');if(declared&&(!Number.isInteger(declared)||declared>32*1024*1024))throw new Error('SOURCE_TOO_LARGE');
 let size=0;const chunks:Uint8Array[]=[];for await(const chunk of response.body){size+=chunk.length;if(size>32*1024*1024)throw new Error('SOURCE_TOO_LARGE');chunks.push(chunk);}
 if(size<22)throw new Error('SOURCE_EMPTY_BODY');return Buffer.concat(chunks);
}
// Sharing the same coordinator prevents timer/admin overlap on this Store.
const running = new WeakMap<Store, Promise<void>>();
export function ingest(store:Store, adapters:SourceAdapter[]=[rcbAdapter,securityLevelsAdapter,shelterAdapter,rsoAdapter,...wczkAdapters,paaAdapter,certAdapter,sgAdapter], fetchText=fetchPublic, fetchBytes=fetchPublicBytes):Promise<void>{
 const existing=running.get(store);if(existing)return existing;
 const task=syncSources(store,adapters,fetchText,fetchBytes).finally(()=>running.delete(store));
 running.set(store,task);return task;
}
async function syncSources(store:Store,adapters:SourceAdapter[],fetchText:(url:string)=>Promise<string>,fetchBytes:(url:string)=>Promise<Uint8Array>){
 await initializeSources(store);
 for(const adapter of adapters){
  const previous=(await store.health()).find(s=>s.id===adapter.id);
  if(!previous)throw new Error('UNKNOWN_ADAPTER');
  const begin=Date.now(),lastAttempt=new Date(begin).toISOString();
  if(adapter.minSyncIntervalSeconds&&previous.lastSuccess&&previous.state==='HEALTHY'&&begin-Date.parse(previous.lastSuccess)>=0&&begin-Date.parse(previous.lastSuccess)<adapter.minSyncIntervalSeconds*1000)continue;
  try{
   const batch=await adapter.sync({now:new Date(begin),fetchText,fetchBytes,previousEvents:['PAA','SG'].includes(adapter.id)?await store.events():undefined});
   const items=batch.events.map(e=>eventSchema.parse(e));
   if(items.some(e=>e.isDemo||!e.sources.some(s=>s.id===adapter.id)))throw new Error('SOURCE_INVALID_EVENT');
   const published=items.map(e=>e.publishedAt??(e.securityLevel?.publishedAt?e.securityLevel.publishedAt:null)).filter((v):v is string=>v!==null).sort();
   const health:Health={...previous,...batch.metadata,...(adapter.id==='PAA'?{checkedEventIds:items.map(e=>e.id)}:{}),enabled:true,state:'HEALTHY',lastAttempt,lastSuccess:new Date().toISOString(),lastItemTime:batch.metadata?.sourceUpdatedAt??published.at(-1)??null,responseTime:Date.now()-begin,failureCount:0,complete:batch.complete,coverage:batch.coverage,pagesFetched:batch.pagesFetched,itemCount:batch.shelters?.length??items.length,errorCode:null,adapterVersion:adapter.version};
   if(batch.shelters){
    if(adapter.id!=='SHELTERS'||items.length||batch.coverage!=='FACILITY_CATALOG'||!batch.complete||!batch.metadata)throw new Error('SOURCE_INVALID_BATCH');
    if(previous.sourceUpdatedAt&&Date.parse(batch.metadata.sourceUpdatedAt)<Date.parse(previous.sourceUpdatedAt))throw new Error('SHELTER_FALLBACK_OLDER_THAN_LAST_GOOD');
    await store.applyShelterSync(batch.shelters,health);
   }else await store.applySync(items,health);
  }catch(error){
   const message=error instanceof Error?error.message:'';
   const errorCode=/^[A-Z][A-Z0-9_]{2,100}$/.test(message)?message:'SOURCE_SYNC_FAILED';
   await store.setHealth({...previous,enabled:true,state:'BROKEN',lastAttempt,lastFailure:new Date().toISOString(),failureCount:previous.failureCount+1,responseTime:Date.now()-begin,complete:false,errorCode,adapterVersion:adapter.version});
  }
 }
}

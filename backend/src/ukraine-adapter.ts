import {UA_BOUNDARY_QUERY,enrichUaGeometry} from './ukraine-geography.js';
import {createHash} from 'node:crypto';
import {z} from 'zod';
import {eventSchema,type Event} from './domain.js';
import type {SourceAdapter,SourceContext} from './source-adapter.js';

// Published contract: UkraineAlarm/UkraineAlarm-javascript, API v3.
export const UA_API='https://api.ukrainealarm.com/api/v3';
export const UA_MAP='https://map.ukrainealarm.com/';
export const UA_VERSION='ukrainealarm-v3/1.0.0';
export const uaRegionSchema=z.object({id:z.string().min(1).max(80),name:z.string().min(1).max(200),type:z.enum(['State','District','Community']),parentId:z.string().nullable()});
export type UaRegion=z.infer<typeof uaRegionSchema>;
const id=z.string().regex(/^[A-Za-z0-9_-]{1,80}$/);
const regionType=z.enum(['State','District','Community']);
const alertType=z.enum(['AIR','ARTILLERY','URBAN_FIGHTS','CHEMICAL','NUCLEAR','INFO']);
const timestamp=z.iso.datetime({offset:true}).transform(s=>new Date(s).toISOString());
const optionalTime=timestamp.nullish().transform(v=>v??null);
const activeSchema=z.array(z.object({regionId:id,regionName:z.string().min(1).max(200),regionType,regionEngName:z.string().optional(),lastUpdate:optionalTime,activeAlerts:z.array(z.object({regionId:id,regionType,type:alertType,lastUpdate:optionalTime})).max(20)})).max(2000);
const historySchema=z.array(z.object({regionId:id,regionName:z.string().min(1).max(200),alarms:z.array(z.object({regionId:id,startDate:timestamp,endDate:optionalTime,alertType,regionName:z.string().optional(),isContinue:z.boolean()})).max(100)})).max(2000);
const hash=(value:unknown)=>createHash('sha256').update(JSON.stringify(value)).digest('hex');
export function parseUaRegions(input:unknown):UaRegion[]{
 const root=z.object({states:z.array(z.unknown()).min(1).max(50)}).parse(input),rows:UaRegion[]=[];
 const visit=(input:unknown,parentId:string|null,depth:number)=>{
  if(depth>3||rows.length>=5000)throw new Error('UA_REGISTRY_LIMIT');
  const r=z.object({regionId:id,regionName:z.string().min(1).max(200),regionType,regionChildIds:z.array(z.unknown()).max(1000)}).parse(input);
  if(rows.some(v=>v.id===r.regionId)||(!parentId&&r.regionType!=='State'))throw new Error('UA_REGISTRY_CONFLICT');
  rows.push({id:r.regionId,name:r.regionName,type:r.regionType,parentId});
  for(const c of r.regionChildIds)visit(c,r.regionId,depth+1);
 };
 root.states.forEach(r=>visit(r,null,0));return rows;
}
const labels:Record<string,string>={AIR:'Alarm powietrzny',ARTILLERY:'Zagrożenie ostrzałem artyleryjskim',URBAN_FIGHTS:'Zagrożenie walkami ulicznymi',CHEMICAL:'Zagrożenie chemiczne',NUCLEAR:'Zagrożenie radiacyjne',INFO:'Oficjalna informacja'};
export function parseUaBatch(registry:UaRegion[],activeInput:unknown,historyInput:unknown,previous:Event[],now:Date){
 const active=activeSchema.parse(activeInput),history=historySchema.parse(historyInput),byId=new Map(registry.map(r=>[r.id,r]));
 const getRegion=(regionId:string)=>{const r=byId.get(regionId);if(!r)throw new Error('UA_UNKNOWN_REGION');return r;};
 const timeCheck=(v:string|null)=>{if(v&&Date.parse(v)>+now+30000)throw new Error('UA_FUTURE_TIMESTAMP');};
 const events=new Map<string,Event>(),activeKeys=new Set<string>(),historyActive=new Map<string,Event>();
 const create=(regionId:string,type:z.infer<typeof alertType>,start:string|null,end:string|null,continuing:boolean,sourceUpdatedAt:string|null):Event=>{
  const r=getRegion(regionId);timeCheck(start);timeCheck(end);timeCheck(sourceUpdatedAt);
  if(end&&(!start||end<=start||continuing))throw new Error('UA_TIME_CONFLICT');
  const lifecycle=end?'ENDED':continuing?'ACTIVE':'UNKNOWN';
  const cycle=hash([regionId,type,start??'START_UNKNOWN']).slice(0,32),eventId='UA-'+cycle;
  return eventSchema.parse({id:eventId,origin:'OFFICIAL_FOREIGN',countryCode:'UA',ukraine:{regionId:r.id,regionName:r.name,regionType:r.type,parentRegionId:r.parentId,alertType:type,kind:type==='INFO'?'OFFICIAL_INFORMATION':'OFFICIAL_ALERT',sourceUpdatedAt},title:`${labels[type]} — ${r.name}`,description:type==='INFO'?'Oficjalna informacja UkraineAlarm. Nie jest automatycznie alarmem.':'Oficjalny alarm obrony cywilnej Ukrainy. Nie określa zagrożenia w Polsce.',eventType:type==='NUCLEAR'?'RADIATION':type==='CHEMICAL'?'HAZMAT':type==='AIR'?'AIR':'PUBLIC_SAFETY',severity:type==='INFO'?'INFORMATIONAL':'HIGH',verification:'CONFIRMED',lifecycle,messageContext:'ACTUAL',regions:[],geographicScope:'REGIONAL',publishedAt:null,publicationDate:null,retrievedAt:now.toISOString(),validFrom:start,validTo:end,sources:[{id:'UA',name:'UkraineAlarm / Повітряна тривога',url:UA_MAP,tier:1}],instructions:[],officialWarning:type!=='INFO',reviewed:false,revision:1,locationText:r.name,areaPrecision:r.type==='State'?'PROVINCE':'PROVINCE_SUBSET',geometry:null,latitude:null,longitude:null,adapterVersion:UA_VERSION,sourceContentHash:hash([regionId,type,start,end,continuing,sourceUpdatedAt]),correction:null,isDemo:false});
 };
 for(const group of history){
  getRegion(group.regionId);
  for(const a of group.alarms){
   if(a.regionId!==group.regionId)throw new Error('UA_HISTORY_REGION_CONFLICT');
   const e=create(a.regionId,a.alertType,a.startDate,a.endDate,a.isContinue,null),key=a.regionId+':'+a.alertType;
   if(events.has(e.id)&&JSON.stringify(events.get(e.id))!==JSON.stringify(e))throw new Error('UA_DUPLICATE_CONFLICT');
   events.set(e.id,e);
   if(a.isContinue){if(historyActive.has(key)&&historyActive.get(key)!.id!==e.id)throw new Error('UA_CYCLE_CONFLICT');historyActive.set(key,e);}
  }
 }
 for(const group of active){
  const groupRegion=getRegion(group.regionId);
  if(groupRegion.type!==group.regionType)throw new Error('UA_REGION_TYPE_CONFLICT');
  timeCheck(group.lastUpdate);
  for(const a of group.activeAlerts){
   const r=getRegion(a.regionId);if(r.type!==a.regionType)throw new Error('UA_REGION_TYPE_CONFLICT');
   // Parent rows may include child alerts; retain the child's exact scope.
   let ancestor:UaRegion|undefined=r;
   while(ancestor&&ancestor.id!==group.regionId)ancestor=ancestor.parentId?byId.get(ancestor.parentId):undefined;
   if(!ancestor)throw new Error('UA_REGION_RELATION_CONFLICT');
   timeCheck(a.lastUpdate);const key=a.regionId+':'+a.type;activeKeys.add(key);
   const existing=historyActive.get(key);
   if(existing){existing.ukraine!.sourceUpdatedAt=a.lastUpdate;events.set(existing.id,existing);}
   else {const e=create(a.regionId,a.type,null,null,true,a.lastUpdate);events.set(e.id,e);}
  }
 }
 for(const [key] of historyActive)if(!activeKeys.has(key))throw new Error('UA_SNAPSHOT_HISTORY_CONFLICT');
 // An absent record in a bounded history cannot terminate an old cycle.
 for(const old of previous.filter(e=>e.countryCode==='UA'&&e.ukraine&&['ACTIVE','UNKNOWN'].includes(e.lifecycle))){
  if(events.has(old.id))continue;
  // Keep unresolved cycles, marked UNKNOWN. No synthetic end or expiry.
  events.set(old.id,{...old,lifecycle:'UNKNOWN',retrievedAt:now.toISOString()});
 }
 return {events:[...events.values()],activeEventIds:[...events.values()].filter(e=>e.lifecycle==='ACTIVE').map(e=>e.id)};
}
export function isAllowedUaUrl(url:string){
 try{const u=new URL(url);return u.origin==='https://api.ukrainealarm.com'&&!u.username&&!u.password&&!u.hash&&(
  ['/api/v3/regions','/api/v3/alerts','/api/v3/alerts/status'].includes(u.pathname)&&!u.search||
  u.pathname==='/api/v3/alerts/regionHistory'&&[...u.searchParams.keys()].length===1&&id.safeParse(u.searchParams.get('regionId')).success);
 }catch{return false;}
}
export async function fetchUa(url:string,key=process.env.UKRAINE_ALARM_API_KEY){
 if(!isAllowedUaUrl(url))throw new Error('UA_URL_DENIED');
 if(!key?.trim())throw new Error('NOT_CONFIGURED_UA_API_KEY_MISSING');
 const response=await fetch(url,{headers:{Authorization:key,Accept:'application/json'},redirect:'error',signal:AbortSignal.timeout(20000)});
 if(!response.ok)throw new Error(`UA_HTTP_${response.status}`);
 if(!response.headers.get('content-type')?.toLowerCase().includes('application/json')||!response.body)throw new Error('UA_CONTENT_TYPE_CHANGED');
 let size=0;const chunks:Uint8Array[]=[];for await(const c of response.body){size+=c.length;if(size>4*1024*1024)throw new Error('UA_RESPONSE_LIMIT');chunks.push(c);}
 return new TextDecoder('utf-8',{fatal:true}).decode(Buffer.concat(chunks));
}
export const ukraineAdapter:SourceAdapter={id:'UA',version:UA_VERSION,minSyncIntervalSeconds:60,
 async sync({now,fetchText,previousEvents=[]}:SourceContext){
  const read=async(path:string)=>JSON.parse(await fetchText(UA_API+path));
  const status=z.object({lastActionIndex:z.number().int().nonnegative()});
  const before=status.parse(await read('/alerts/status'));
  const regions=parseUaRegions(await read('/regions')),active=activeSchema.parse(await read('/alerts'));
  const ids=new Set([...regions.filter(r=>r.type==='State').map(r=>r.id),...active.flatMap(r=>r.activeAlerts.map(a=>a.regionId)),...previousEvents.filter(e=>e.countryCode==='UA'&&e.ukraine&&['ACTIVE','UNKNOWN'].includes(e.lifecycle)).map(e=>e.ukraine!.regionId)]);
  if(ids.size>300)throw new Error('UA_HISTORY_SCOPE_LIMIT');
  const history:unknown[]=[];
  for(const regionId of ids){const rows=historySchema.parse(await read('/alerts/regionHistory?regionId='+encodeURIComponent(regionId)));if(rows.some(r=>r.regionId!==regionId))throw new Error('UA_HISTORY_REGION_CONFLICT');history.push(...rows);}
  if(status.parse(await read('/alerts/status')).lastActionIndex!==before.lastActionIndex)throw new Error('UA_SOURCE_CHANGED_DURING_SYNC');
  const batch=parseUaBatch(regions,active,history,previousEvents,now);
  // Geography failure must not suppress valid civil alerts. Retain prior geometry.
  let events=batch.events.map(e=>{const old=previousEvents.find(p=>p.id===e.id);return old?.geometry?{...e,geometry:old.geometry,geometrySource:old.geometrySource}:e;});
  try {events=enrichUaGeometry(events,regions,JSON.parse(await fetchText(UA_BOUNDARY_QUERY)));}catch{/* Missing geometry remains explicit. */}
  return {events,uaMetadata:{regions,activeEventIds:batch.activeEventIds,lastActionIndex:before.lastActionIndex},complete:false,coverage:'ACTIVE_WARNINGS',pagesFetched:4+ids.size};
 }
};

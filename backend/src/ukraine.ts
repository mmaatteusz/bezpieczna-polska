import {sourceHealth,type Event} from './domain.js';
import {Store} from './store.js';
import {UA_MAP,UA_VERSION} from './ukraine-adapter.js';
export const isUa=(e:Event)=>e.countryCode==='UA'||!!e.ukraine||e.sources.some(s=>s.id==='UA');
export async function ukraineSnapshot(store:Store,now=new Date()){
 return store.db.transaction(async db=>{
  const scoped=new Store(db),events=(await scoped.events()).filter(e=>isUa(e)&&!e.isDemo),raw=(await scoped.health()).find(h=>h.id==='UA');
  const health=raw?sourceHealth([raw],now)[0]:null;
  const fresh=health?.state==='HEALTHY';
  const verifiedIds=new Set(raw?.uaMetadata?.activeEventIds??[]);
  const current=events.filter(e=>['ACTIVE','UNKNOWN'].includes(e.lifecycle));
  const history=events.filter(e=>!current.includes(e)).sort((a,b)=>(b.validFrom??'').localeCompare(a.validFrom??'')).slice(0,100);
  // Never silently truncate unresolved alarms. Refuse oversized snapshots.
  if(current.length>1000)throw new Error('UA_SNAPSHOT_LIMIT');
  const items=[...current,...history].map(e=>({...e,freshness:fresh&&(e.lifecycle==='ENDED'||verifiedIds.has(e.id))?'FRESH':'STALE'}));
  const revisions=[];
  for(const e of items){const rows=await scoped.timeline(e.id);revisions.push(...rows.slice(-5));}
  const coverage=health?.state==='NOT_CONFIGURED'||!raw?.lastSuccess?'unavailable':!fresh?'stale':'partial';
  const active=items.filter(e=>e.ukraine?.kind==='OFFICIAL_ALERT'&&e.lifecycle==='ACTIVE');
  return {schemaVersion:1,countryCode:'UA',serverTime:now.toISOString(),lastSuccessfulSyncAt:raw?.lastSuccess??null,validUntil:raw?.lastSuccess?new Date(Date.parse(raw.lastSuccess)+raw.maxAgeSeconds*1000).toISOString():null,sourceHealth:health?{...health,uaMetadata:undefined}:null,healthStatus:health?.state==='BROKEN'?'DOWN':health?.state??'NOT_CONFIGURED',coverage,hazardLevel:active.length?'CAUTION':'UNKNOWN',displayText:active.length?(fresh?'Aktywny alarm w Ukrainie':'Ostatni znany alarm w Ukrainie — STALE'):'Brak potwierdzonego bieżącego stanu alarmów',reasonCodes:['UA_INDEPENDENT_OF_POLAND','BOUNDED_SOURCE_HISTORY',...(fresh?[]:['UA_NO_CURRENT_COVERAGE'])],sourceUrl:UA_MAP,contract:UA_VERSION,regions:raw?.uaMetadata?.regions??[],events:items,revisions,historyLimit:100,revisionsPerEvent:5,geometryCoverage:'PARTIAL_OFFICIAL_ADMIN_BOUNDARIES_ONLY',map:{type:'FeatureCollection',features:items.filter(e=>e.ukraine?.kind==='OFFICIAL_ALERT'&&['ACTIVE','UNKNOWN'].includes(e.lifecycle)&&e.geometry&&e.geometry.type!=='Point').map(e=>({type:'Feature',id:e.id,geometry:e.geometry,properties:{eventId:e.id,regionId:e.ukraine!.regionId,title:e.title,lifecycle:e.lifecycle,freshness:e.freshness,sourceUrl:UA_MAP,geometrySource:e.geometrySource}}))}};
 });
}

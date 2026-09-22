import {z} from 'zod';
import {REGIONS,sourceHealth,type Event} from './domain.js';
import {Store} from './store.js';

export const aroundQuerySchema=z.object({
 latitude:z.coerce.number().min(-90).max(90),
 longitude:z.coerce.number().min(-180).max(180),
 radiusKm:z.coerce.number().min(1).max(100).default(20),
 regionId:z.string().refine(v=>v in REGIONS).optional(),
});

export type AroundQuery=z.infer<typeof aroundQuerySchema>;

function usable(e:Event,now:Date){
 if(e.isDemo||e.securityLevel||e.messageContext!=='ACTUAL'||e.verification==='REFUTED')return false;
 if(['ENDED','CANCELLED','EXPIRED'].includes(e.lifecycle))return false;
 if(e.validFrom&&Date.parse(e.validFrom)>now.getTime())return false;
 if(e.validTo&&Date.parse(e.validTo)<=now.getTime())return false;
 return true;
}

function regional(e:Event,regionId:string){
 if(e.regions.includes('PL')&&(e.geographicScope==='NATIONAL'||e.areaPrecision==='COUNTRY'))return true;
 return e.regions.includes(regionId)&&e.geographicScope==='REGIONAL'&&e.areaPrecision==='PROVINCE';
}

export async function aroundLocation(store:Store,q:AroundQuery,now=new Date()){
 if(store.db.kind!=='postgres')throw new Error('POSTGIS_REQUIRED');
 return store.db.transaction(async db=>{
  const scoped=new Store(db);
  const [all,health,nearRows,nearestShelters]=await Promise.all([
   scoped.events(),
   scoped.health(),
   scoped.nearbyEvents(q.latitude,q.longitude,Math.round(q.radiusKm*1000),50),
   scoped.nearestShelters(q.latitude,q.longitude,3),
  ]);
  const nearby=nearRows
   .filter(row=>usable(row.event,now))
   .map(row=>({event:row.event,distanceMeters:row.distanceMeters,relevance:'NEARBY' as const}));
  const nearbyIds=new Set(nearby.map(row=>row.event.id));
  const regionalEvents=q.regionId
   ? all.filter(e=>usable(e,now)&&!nearbyIds.has(e.id)&&regional(e,q.regionId!)).map(event=>({event,relevance:'REGION_RELEVANT' as const}))
   : [];
  const shelterHealth=health.find(h=>h.id==='SHELTERS');
  return {
   schemaVersion:1,
   serverTime:now.toISOString(),
   query:{latitude:q.latitude,longitude:q.longitude,radiusKm:q.radiusKm,regionId:q.regionId??null},
   nearbyEvents:nearby,
   regionalEvents,
   nearestShelters:{
    items:nearestShelters,
    health:shelterHealth?sourceHealth([shelterHealth],now)[0]:null,
   },
   coverage:{
    spatial:'PARTIAL_GEOMETRY_ONLY',
    regional:q.regionId?'EXPLICIT_NATIONAL_OR_PROVINCE_SCOPE_ONLY':'NOT_REQUESTED',
    statement:'Brak geometrii nie jest interpretowany jako brak zdarzeń w pobliżu.',
   },
  };
 });
}

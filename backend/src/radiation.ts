import {z} from 'zod';
import {publicSourceHealth,sourceHealth,type Event,type Health} from './domain.js';
// Internal storage contract, NOT a claimed PAA API. No production measurement
// adapter is enabled until the official source format and geometry are verified.
export const radiationMeasurementSchema=z.object({
 stationId:z.string().min(1).max(100),name:z.string().min(1).max(200),
 latitude:z.number().min(49).max(55).nullable(),longitude:z.number().min(14).max(24.2).nullable(),
 measuredAt:z.iso.datetime({offset:true}),value:z.number().finite().nonnegative(),
 unit:z.enum(['nSv/h','µSv/h']),sourceUpdatedAt:z.iso.datetime({offset:true}),
 regionId:z.string().regex(/^(PL|02|04|06|08|10|12|14|16|18|20|22|24|26|28|30|32)$/).nullable(),
}).superRefine((p,c)=>{if((p.latitude===null)!==(p.longitude===null))c.addIssue({code:'custom',message:'Coordinates must be paired'});});
export type RadiationMeasurement=z.infer<typeof radiationMeasurementSchema>;
export function measurementFreshness(p:RadiationMeasurement,h:Health|undefined,now=new Date()){
 const ms=now.getTime();return h&&h.state==='HEALTHY'&&h.lastSuccess&&[p.measuredAt,p.sourceUpdatedAt,h.lastSuccess].every(d=>Date.parse(d)<=ms+30000&&ms-Date.parse(d)<h.maxAgeSeconds*1000)?'FRESH':'STALE';
}
export function radiationStatus(events:Event[],health:Health[],region='PL',now=new Date(),measurements:RadiationMeasurement[]=[]){
 const messages=events.filter(e=>e.sources.some(s=>s.id==='PAA')&&(region==='PL'||!e.regions.length||e.regions.includes('PL')||e.regions.includes(region)));
 const states=sourceHealth(health.filter(h=>['PAA','PAA_MEASUREMENTS'].includes(h.id)),now);
 const communication=states.find(h=>h.id==='PAA'),measurementHealth=health.find(h=>h.id==='PAA_MEASUREMENTS');
 const fresh=communication?.state==='HEALTHY';
 const warnings=messages.filter(e=>(!e.validTo?communication?.checkedEventIds?.includes(e.id):true)&&e.officialWarning&&e.radiationAssessment?.state==='WARNING'&&e.lifecycle==='ACTIVE'&&(!e.validTo||Date.parse(e.validTo)>now.getTime())&&(!e.validFrom||Date.parse(e.validFrom)<=now.getTime()));
 const unknown=messages.filter(e=>e.radiationAssessment?.state==='UNDETERMINED');
 const items=measurements.filter(p=>region==='PL'||p.regionId===null||p.regionId===region).map(p=>({...p,freshness:measurementFreshness(p,measurementHealth,now)}));
 return {schemaVersion:1,regionId:region,communicationState:!fresh?'UNAVAILABLE':warnings.length?'ACTIVE':unknown.length?'UNDETERMINED':'NO_ACTIVE_MESSAGE_IN_WINDOW',measurementState:!measurementHealth?.enabled?'NOT_CONFIGURED':!items.length?'NO_DATA':items.every(p=>p.freshness==='FRESH')?'FRESH':'STALE',sourceHealth:publicSourceHealth(health.filter(h=>['PAA','PAA_MEASUREMENTS'].includes(h.id)),now),activeMessageIds:warnings.map(e=>e.id),messages,measurements:items,complete:false,measuredValuesAffectHazard:false};
}

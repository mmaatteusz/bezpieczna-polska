import {z} from 'zod';
import type {Event,Health} from './domain.js';
import {sourceHealth} from './domain.js';
export const securityLevelSchema=z.object({
 id:z.string().min(1),level:z.enum(['ALFA','BRAVO','CHARLIE','DELTA']),type:z.enum(['PHYSICAL','CRP']),
 scope:z.enum(['NATIONAL','REGIONAL','INFRASTRUCTURE','EXTRATERRITORIAL_INFRASTRUCTURE']),
 description:z.string().min(1),area:z.string().min(1),regions:z.array(z.string().refine(v=>/^(PL|02|04|06|08|10|12|14|16|18|20|22|24|26|28|30|32)$/.test(v))),geometry:z.null(),
 validFrom:z.iso.datetime({offset:true}),validTo:z.iso.datetime({offset:true}),issuedBy:z.string().min(1),sourceUrl:z.url(),
 // gov.pl exposes a calendar publication date, no publication/update timestamp.
 publishedAt:z.iso.date(),updatedAt:z.iso.datetime({offset:true}).nullable(),rawSourceId:z.string().min(1),isActive:z.boolean(),
}).refine(v=>Date.parse(v.validFrom)<Date.parse(v.validTo),'Invalid security-level interval');
export type SecurityLevel=z.infer<typeof securityLevelSchema>;
export function securityLevels(events:Event[],region:string,now=new Date()):SecurityLevel[]{
 return events.filter(e=>e.securityLevel&&!e.isDemo&&e.sources.some(s=>s.id==='LEVELS')).map(e=>({...e.securityLevel!,isActive:e.lifecycle!=='CANCELLED'&&Date.parse(e.securityLevel!.validFrom)<=+now&&Date.parse(e.securityLevel!.validTo)>=+now}))
 .filter(s=>s.isActive&&(region==='PL'||s.regions.includes('PL')||s.regions.includes(region)))
 .sort((a,b)=>a.type.localeCompare(b.type)||a.scope.localeCompare(b.scope)||a.id.localeCompare(b.id));
}
export function securityLevelStatus(events:Event[],health:Health[],region:string,now=new Date()){
 const h=sourceHealth(health,now).find(s=>s.id==='LEVELS'),items=securityLevels(events,region,now);
 return {securityLevels:items,securityLevelsStatus:h?.state==='HEALTHY'?(items.length?'AVAILABLE':'UNKNOWN'):h?.lastSuccess?'STALE':'UNKNOWN',securityLevelsLastSuccess:h?.lastSuccess??null,
 securityLevelsCoverage:'PUBLISHED_DECISIONS_ONLY',securityLevelsNotice:'Stopnie dotyczą gotowości służb i administracji; same nie potwierdzają bezpośredniego zagrożenia. Wykaz opiera się na publikacjach RCB.'};
}

import {z} from 'zod';
export const REGIONS:Record<string,string>={'02':'Dolnośląskie','04':'Kujawsko-pomorskie','06':'Lubelskie','08':'Lubuskie','10':'Łódzkie','12':'Małopolskie','14':'Mazowieckie','16':'Opolskie','18':'Podkarpackie','20':'Podlaskie','22':'Pomorskie','24':'Śląskie','26':'Świętokrzyskie','28':'Warmińsko-mazurskie','30':'Wielkopolskie','32':'Zachodniopomorskie'};
const date=z.iso.datetime({offset:true});
export const eventSchema=z.object({
 id:z.string().min(1).max(150),title:z.string().min(1).max(350),description:z.string().max(40000),
 eventType:z.enum(['AIR','BORDER','CYBER','RADIATION','FIRE','EVACUATION','OUTAGE','WEATHER','OTHER']),
 severity:z.enum(['CRITICAL','HIGH','NORMAL','INFORMATIONAL']),
 verification:z.enum(['CONFIRMED','PROBABLE','UNVERIFIED','REFUTED','DISPUTED']),
 lifecycle:z.enum(['SCHEDULED','ACTIVE','ENDED','CANCELLED','EXPIRED','UNKNOWN']),
 messageContext:z.enum(['ACTUAL','EXERCISE','TEST','UNKNOWN']),
 regions:z.array(z.string().refine(s=>s==='PL'||s in REGIONS)).max(17),
 geographicScope:z.enum(['NATIONAL','REGIONAL','UNKNOWN']),
 publishedAt:date.nullable(),retrievedAt:date,validFrom:date.nullable(),validTo:date.nullable(),
 sources:z.array(z.object({id:z.string().max(80),name:z.string().max(200),url:z.url().refine(v=>new URL(v).protocol==='https:'&&!new URL(v).username),tier:z.number().int().min(1).max(4)})).min(1).max(30),
 instructions:z.array(z.string().max(2000)).max(20),officialWarning:z.boolean(),reviewed:z.boolean(),revision:z.number().int().positive(),
 correction:z.string().max(4000).nullable(),latitude:z.number().min(-90).max(90).nullable(),longitude:z.number().min(-180).max(180).nullable(),isDemo:z.boolean().default(false)
});
export type Event=z.infer<typeof eventSchema>;
export type Health={id:string;name:string;url:string;state:'HEALTHY'|'DEGRADED'|'BROKEN'|'NOT_CONFIGURED';lastSuccess:string|null;lastFailure:string|null;lastItemTime:string|null;failureCount:number;responseTime:number|null;maxAgeSeconds:number;complete:boolean};
export function computeStatus(events:Event[],health:Health[],region:string,now=new Date()){
 const ms=now.getTime();
 const relevant=events.filter(e=>!e.isDemo&&e.reviewed&&e.officialWarning&&e.messageContext==='ACTUAL'&&e.verification==='CONFIRMED'&&e.sources.some(s=>s.tier===1)&&(region==='PL'||e.regions.includes('PL')||e.regions.includes(region)));
 const fresh=health.filter(h=>h.state==='HEALTHY'&&h.complete&&h.lastSuccess&&Date.parse(h.lastSuccess)<=ms+30000&&ms-Date.parse(h.lastSuccess)<h.maxAgeSeconds*1000);
 const coverage=health.length>0&&fresh.length===health.length?'COMPLETE_FOR_CONFIGURED_SCOPE':fresh.length?'PARTIAL':'UNAVAILABLE';
 const active=relevant.filter(e=>e.lifecycle==='ACTIVE'&&e.validTo&&Date.parse(e.validTo)>ms&&(!e.validFrom||Date.parse(e.validFrom)<=ms));
 const critical=active.filter(e=>e.severity==='CRITICAL');const caution=active.filter(e=>['HIGH','NORMAL'].includes(e.severity));
 const stale=relevant.filter(e=>e.lifecycle==='ACTIVE'&&!active.includes(e));
 let hazardLevel='UNKNOWN',displayText='Brak wystarczających aktualnych danych';const reasonCodes:string[]=[];
 if(critical.length){hazardLevel='ACTIVE_DANGER';displayText=region==='PL'&&!critical.some(e=>e.geographicScope==='NATIONAL')?'Aktywne zagrożenie lokalne w Polsce':'Aktywne ostrzeżenie o bezpośrednim zagrożeniu';reasonCodes.push('OFFICIAL_ACTIVE_WARNING');}
 else if(caution.length){hazardLevel='CAUTION';displayText='Obowiązują istotne ostrzeżenia';reasonCodes.push('OFFICIAL_CAUTION');}
 else if(stale.length){displayText='Nie potwierdzono zakończenia wcześniejszego zagrożenia';reasonCodes.push('LAST_KNOWN_WARNING');}
 else if(coverage==='COMPLETE_FOR_CONFIGURED_SCOPE'){hazardLevel='NO_ACTIVE_WARNINGS';displayText='Brak aktywnych ostrzeżeń w monitorowanych źródłach';}
 if(coverage!=='COMPLETE_FOR_CONFIGURED_SCOPE')reasonCodes.push('INCOMPLETE_SOURCE_COVERAGE');
 return {hazardLevel,displayText,coverageState:coverage,reasonCodes,supportingEventIds:[...critical,...caution].map(e=>e.id),lastKnownEventIds:stale.map(e=>e.id),evaluatedAt:now.toISOString(),validUntil:new Date(Math.min(ms+60000,...active.map(e=>Date.parse(e.validTo!)),...fresh.map(h=>Date.parse(h.lastSuccess!)+h.maxAgeSeconds*1000))).toISOString(),rulesetVersion:'1.0.0'};
}

import {correlate,choosePrimary,type Incident} from './correlation.js';
import {z} from 'zod';
import {securityLevelSchema} from './security-level.js';
export const REGIONS:Record<string,string>={'02':'Dolnośląskie','04':'Kujawsko-pomorskie','06':'Lubelskie','08':'Lubuskie','10':'Łódzkie','12':'Małopolskie','14':'Mazowieckie','16':'Opolskie','18':'Podkarpackie','20':'Podlaskie','22':'Pomorskie','24':'Śląskie','26':'Świętokrzyskie','28':'Warmińsko-mazurskie','30':'Wielkopolskie','32':'Zachodniopomorskie'};
const date=z.iso.datetime({offset:true});
const position=z.tuple([z.number().min(-180).max(180),z.number().min(-90).max(90)]);
const ring=z.array(position).min(4).refine(v=>v[0][0]===v.at(-1)![0]&&v[0][1]===v.at(-1)![1],'Ring must be closed');
export const geometrySchema=z.discriminatedUnion('type',[
 z.object({type:z.literal('Point'),coordinates:position}),
 z.object({type:z.literal('Polygon'),coordinates:z.array(ring).min(1)}),
 z.object({type:z.literal('MultiPolygon'),coordinates:z.array(z.array(ring).min(1)).min(1)})
]);
export const eventSchema=z.object({
 radiationAssessment:z.object({state:z.enum(['WARNING','ENDED','INFORMATION','UNDETERMINED']),evidence:z.string().nullable()}).optional(),
 securityLevel:securityLevelSchema.optional(),
 id:z.string().min(1).max(150),title:z.string().min(1).max(350),description:z.string().max(40000),
 eventType:z.enum(['AIR','BORDER','CYBER','RADIATION','FIRE','EXPLOSION','HAZMAT','RESCUE','PUBLIC_SAFETY','EVACUATION','OUTAGE','WEATHER','OTHER']),
 severity:z.enum(['CRITICAL','HIGH','NORMAL','INFORMATIONAL']),
 verification:z.enum(['CONFIRMED','PROBABLE','UNVERIFIED','REFUTED','DISPUTED']),
 lifecycle:z.enum(['SCHEDULED','ACTIVE','ENDED','CANCELLED','EXPIRED','UNKNOWN']),
 messageContext:z.enum(['ACTUAL','EXERCISE','TEST','UNKNOWN']),
 regions:z.array(z.string().refine(s=>s==='PL'||s in REGIONS)).max(17),
 geographicScope:z.enum(['NATIONAL','REGIONAL','UNKNOWN']),
 publishedAt:date.nullable(),retrievedAt:date,validFrom:date.nullable(),validTo:date.nullable(),
 sources:z.array(z.object({id:z.string().max(80),name:z.string().max(200),url:z.url().refine(v=>new URL(v).protocol==='https:'&&!new URL(v).username),tier:z.number().int().min(1).max(4)})).min(1).max(30),
 instructions:z.array(z.string().max(2000)).max(20),officialWarning:z.boolean(),reviewed:z.boolean(),revision:z.number().int().positive(),
 publicationDate:z.iso.date().nullable().default(null),locationText:z.string().max(10000).nullable().default(null),areaPrecision:z.enum(['COUNTRY','PROVINCE','PROVINCE_SUBSET','EXACT','UNKNOWN']).default('UNKNOWN'),geometry:geometrySchema.nullable().default(null),adapterVersion:z.string().max(100).nullable().default(null),sourceContentHash:z.string().regex(/^[a-f0-9]{64}$/).nullable().default(null),
 correction:z.string().max(4000).nullable(),latitude:z.number().min(-90).max(90).nullable(),longitude:z.number().min(-180).max(180).nullable(),isDemo:z.boolean().default(false)
}).superRefine((e,ctx)=>{
 if((e.latitude===null)!==(e.longitude===null))ctx.addIssue({code:'custom',message:'Coordinates must be paired'});
 if(e.validFrom&&e.validTo&&Date.parse(e.validTo)<=Date.parse(e.validFrom))ctx.addIssue({code:'custom',message:'Invalid validity interval'});
 if(e.geometry&&e.latitude!==null&&(e.geometry.type!=='Point'||e.geometry.coordinates[0]!==e.longitude||e.geometry.coordinates[1]!==e.latitude))ctx.addIssue({code:'custom',message:'Conflicting event geometry'});
}).transform(e=>({...e,geometry:e.geometry??(e.latitude!==null&&e.longitude!==null?{type:'Point' as const,coordinates:[e.longitude,e.latitude] as [number,number]}:null)}));
export type Event=z.infer<typeof eventSchema>;
export type Health={checkedEventIds?:string[];regionId?:string;implementation?:string;integrationNote?:string;id:string;name:string;url:string;state:'HEALTHY'|'DEGRADED'|'BROKEN'|'NOT_CONFIGURED';lastSuccess:string|null;lastFailure:string|null;lastItemTime:string|null;failureCount:number;responseTime:number|null;maxAgeSeconds:number;complete:boolean;enabled?:boolean;lastAttempt?:string|null;errorCode?:string|null;itemCount?:number;adapterVersion?:string|null;coverage?:'RECENT_PUBLICATIONS'|'ACTIVE_WARNINGS'|'FACILITY_CATALOG';pagesFetched?:number;dataDate?:string;sourceUpdatedAt?:string;sourceContentHash?:string;sourceUrl?:string;datasetUrl?:string;license?:string;fallbackSelected?:'PRIMARY_OFFICIAL_SOURCE'|'SECONDARY_OFFICIAL_SOURCE';fallback?:{selected:'PRIMARY_OFFICIAL_SOURCE'|'SECONDARY_OFFICIAL_SOURCE'|'LAST_KNOWN_GOOD_COPY'|'NONE';secondaryStatus:'NOT_NEEDED'|'AVAILABLE_STALE'|'NOT_VERIFIED';reason:string|null}};
export function computeStatus(events:Event[],health:Health[],region:string,now=new Date(),incidents?:Incident[]){
 const ms=now.getTime();
 // Facilities are reference data, never evidence of the absence of hazards.
 health=health.filter(h=>!['SHELTERS','CERT','CSIRT_GOV','SG','POLICE','PSP_INCIDENTS'].includes(h.id)&&h.coverage!=='FACILITY_CATALOG'&&(!h.regionId||region==='PL'||h.regionId===region));
 const relevant=events.filter(e=>!e.isDemo&&e.officialWarning&&e.messageContext==='ACTUAL'&&e.verification==='CONFIRMED'&&e.sources.some(s=>s.tier===1)&&(region==='PL'||!e.regions.length||e.regions.includes('PL')||e.regions.includes(region)));
 const fresh=health.filter(h=>h.state==='HEALTHY'&&h.lastSuccess&&Date.parse(h.lastSuccess)<=ms+30000&&ms-Date.parse(h.lastSuccess)<h.maxAgeSeconds*1000);
 const coverage=health.length>0&&fresh.length===health.length&&fresh.every(h=>h.complete&&h.id!=='PAA_MEASUREMENTS')?'COMPLETE_FOR_CONFIGURED_SCOPE':fresh.length?'PARTIAL':'UNAVAILABLE';
 const paaCurrent=(e:Event)=>e.sources.some(s=>s.id==='PAA')&&e.radiationAssessment?.state==='WARNING'&&fresh.some(h=>h.id==='PAA'&&h.checkedEventIds?.includes(e.id));
 const active=relevant.filter(e=>e.lifecycle==='ACTIVE'&&e.regions.length>0&&((e.validTo&&Date.parse(e.validTo)>ms)||(!e.validTo&&paaCurrent(e)))&&(!e.validFrom||Date.parse(e.validFrom)<=ms));
 const critical=active.filter(e=>e.severity==='CRITICAL');const caution=active.filter(e=>['HIGH','NORMAL'].includes(e.severity));
 const stale=relevant.filter(e=>(e.lifecycle==='ACTIVE'&&!active.includes(e))||e.lifecycle==='UNKNOWN');
 let hazardLevel='UNKNOWN',displayText='Brak wystarczających aktualnych danych';const reasonCodes:string[]=[];
 if(critical.length){hazardLevel='ACTIVE_DANGER';displayText=region==='PL'&&!critical.some(e=>e.geographicScope==='NATIONAL')?'Aktywne zagrożenie lokalne w Polsce':'Aktywne ostrzeżenie o bezpośrednim zagrożeniu';reasonCodes.push('OFFICIAL_ACTIVE_WARNING');}
 else if(caution.length){hazardLevel='CAUTION';displayText='Obowiązują istotne ostrzeżenia';reasonCodes.push('OFFICIAL_CAUTION');}
 else if(stale.length){displayText='Nie potwierdzono zakończenia wcześniejszego zagrożenia';reasonCodes.push('LAST_KNOWN_WARNING');}
 else if(coverage==='COMPLETE_FOR_CONFIGURED_SCOPE'){hazardLevel='NO_ACTIVE_WARNINGS';displayText='Brak aktywnych ostrzeżeń w monitorowanych źródłach';}
 if(events.some(e=>e.securityLevel&&e.validFrom&&e.validTo&&Date.parse(e.validFrom)<=ms&&Date.parse(e.validTo)>=ms&&(region==='PL'||e.regions.includes('PL')||e.regions.includes(region))))reasonCodes.push('ADMINISTRATIVE_READINESS_LEVELS');
 if(coverage!=='COMPLETE_FOR_CONFIGURED_SCOPE')reasonCodes.push('INCOMPLETE_SOURCE_COVERAGE');
 const groups=incidents??correlate(events),supporting=[...critical,...caution];
 const supportingIncidents=groups.flatMap(g=>{const members=supporting.filter(e=>g.relatedEventIds.includes(e.id));if(!members.length)return [];return [{...g,primaryEventId:choosePrimary(members,now).id,supportingEventIds:members.map(e=>e.id)}];});
 const grouped=new Set(supportingIncidents.flatMap(g=>g.relatedEventIds));
 return {supportingIncidents,incidentCount:supportingIncidents.length+supporting.filter(e=>!grouped.has(e.id)).length,hazardLevel,displayText,coverageState:coverage,reasonCodes,supportingEventIds:[...supportingIncidents.map(g=>g.primaryEventId),...supporting.filter(e=>!grouped.has(e.id)).map(e=>e.id)],lastKnownEventIds:stale.map(e=>e.id),evaluatedAt:now.toISOString(),validUntil:new Date(Math.min(ms+60000,...active.filter(e=>e.validTo).map(e=>Date.parse(e.validTo!)),...fresh.map(h=>Date.parse(h.lastSuccess!)+h.maxAgeSeconds*1000))).toISOString(),rulesetVersion:'1.3.0'};
}

export function sourceHealth(health:Health[],now=new Date()){
 return health.map(h=>{
  const stale=h.state==='HEALTHY'&&(!h.lastSuccess||Date.parse(h.lastSuccess)>now.getTime()+30000||now.getTime()-Date.parse(h.lastSuccess)>=h.maxAgeSeconds*1000||(h.sourceUpdatedAt!==undefined&&now.getTime()-Date.parse(h.sourceUpdatedAt)>14*86400000));
  const fallback=h.id==='SHELTERS'?(()=>{
   const selected:NonNullable<Health['fallback']>['selected']=!h.lastSuccess?'NONE':h.state!=='HEALTHY'?'LAST_KNOWN_GOOD_COPY':h.fallbackSelected??'PRIMARY_OFFICIAL_SOURCE';
   const archive=selected==='SECONDARY_OFFICIAL_SOURCE';
   const reason=selected==='LAST_KNOWN_GOOD_COPY'
    ?'Bieżąca synchronizacja nie powiodła się; zachowano ostatnią poprawną kopię.'
    :archive
     ?`Bieżący plik PSP był niedostępny; użyto oficjalnego archiwum dane.gov.pl z datą ${h.dataDate??'nieustaloną'}. Archiwum może być starsze od bieżącego wykazu.`
     :null;
   return {selected,secondaryStatus:archive?'AVAILABLE_STALE' as const:'NOT_NEEDED' as const,reason};
  })():undefined;
  return {...h,...(fallback?{fallback}:{}),healthStatus:stale?'STALE':h.state,state:stale?'STALE':h.state,lastSuccessfulSyncAt:h.lastSuccess,lastAttemptAt:h.lastAttempt??null,errorCode:h.errorCode??null};
 });
}

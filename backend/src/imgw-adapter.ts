import {createHash} from 'node:crypto';
import {DateTime} from 'luxon';
import {eventSchema,REGIONS,type Event} from './domain.js';
import type {SourceAdapter} from './source-adapter.js';

export const IMGW_METEO_URL='https://danepubliczne.imgw.pl/api/data/warningsmeteo';
export const IMGW_HYDRO_URL='https://danepubliczne.imgw.pl/api/data/warningshydro';
export const IMGW_VERSION='imgw-warnings-json/1.0.0';

type Raw=Record<string,unknown>;
const clean=(v:string)=>v.replace(/\s+/g,' ').trim();
const isRaw=(v:unknown):v is Raw=>typeof v==='object'&&v!==null&&!Array.isArray(v);
function textField(raw:Raw,keys:string[],required=true){
 for(const key of keys){const v=raw[key];if(typeof v==='string'&&clean(v))return clean(v);if(typeof v==='number'&&Number.isFinite(v))return String(v);}
 if(required)throw new Error('IMGW_FIELD_MISSING_'+keys[0].toUpperCase());
 return null;
}
function numberField(raw:Raw,keys:string[]){
 const value=textField(raw,keys);
 const parsed=Number(value);
 if(!Number.isFinite(parsed))throw new Error('IMGW_FIELD_INVALID_'+keys[0].toUpperCase());
 return parsed;
}
function dateField(raw:Raw,keys:string[]){
 const value=textField(raw,keys)!;
 const parsed=DateTime.fromFormat(value,'yyyy-MM-dd HH:mm:ss',{zone:'Europe/Warsaw'});
 if(!parsed.isValid||parsed.getPossibleOffsets().length!==1)throw new Error('IMGW_DATE_INVALID_'+keys[0].toUpperCase());
 const iso=parsed.toUTC().toISO();
 if(!iso)throw new Error('IMGW_DATE_INVALID_'+keys[0].toUpperCase());
 return iso;
}
function parsePayload(text:string):Raw[]{
 let value:unknown;
 try{value=JSON.parse(text);}catch{throw new Error('IMGW_JSON_INVALID');}
 if(isRaw(value)&&value.status===false&&value.message==='No products were found')return [];
 if(!Array.isArray(value)||value.length>500||value.some(v=>!isRaw(v)))throw new Error('IMGW_JSON_CONTRACT_CHANGED');
 return value as Raw[];
}
function unique<T>(items:T[]){return [...new Set(items)];}
function regionByName(name:string){
 const normalized=name.normalize('NFD').replace(/\p{M}/gu,'').toLocaleLowerCase('pl').replace(/[^a-z-]/g,'');
 const found=Object.entries(REGIONS).find(([,value])=>value.normalize('NFD').replace(/\p{M}/gu,'').toLocaleLowerCase('pl').replace(/[^a-z-]/g,'')===normalized);
 if(!found)throw new Error('IMGW_UNKNOWN_REGION');
 return found[0];
}
function severity(level:number):Event['severity']{
 if(level>=3)return 'CRITICAL';
 if(level===2)return 'HIGH';
 return 'NORMAL';
}
function lifecycle(validFrom:string,validTo:string,now:Date):Event['lifecycle']{
 if(Date.parse(validFrom)>now.getTime())return 'SCHEDULED';
 if(Date.parse(validTo)<=now.getTime())return 'EXPIRED';
 return 'ACTIVE';
}
function stableId(prefix:string,raw:Raw,eventName:string,office:string,validFrom:string){
 const direct=textField(raw,['id','numer','numer_ostrzezenia','nr'],false);
 const year=new Date(validFrom).getUTCFullYear();
 const key=direct?office+'|'+year+'|'+direct:office+'|'+eventName+'|'+validFrom;
 return prefix+'-'+createHash('sha256').update(key).digest('hex').slice(0,24);
}
function probability(raw:Raw){
 const p=numberField(raw,['prawdopodobienstwo','prawdopodobieństwo']);
 if(!Number.isInteger(p)||p<0||p>100)throw new Error('IMGW_PROBABILITY_INVALID');
 return p;
}
function warningLevel(raw:Raw,kind:'METEO'|'HYDRO'){
 const value=numberField(raw,['stopien','stopień']);
 if(!Number.isInteger(value)||(kind==='METEO'?![1,2,3].includes(value):![-1,1,2,3].includes(value)))throw new Error('IMGW_WARNING_LEVEL_INVALID');
 return value;
}
function eventBase(args:{kind:'METEO'|'HYDRO';raw:Raw;eventName:string;office:string;level:number;publishedAt:string;validFrom:string;validTo:string;regions:string[];description:string;locationText:string;areaPrecision:Event['areaPrecision'];now:Date}):Event{
 const sourceId=args.kind==='METEO'?'IMGW_METEO':'IMGW_HYDRO';
 const sourceUrl=args.kind==='METEO'?IMGW_METEO_URL:IMGW_HYDRO_URL;
 return eventSchema.parse({
  id:stableId(sourceId,args.raw,args.eventName,args.office,args.validFrom),
  title:args.level>0?'IMGW: '+args.eventName+' — stopień '+args.level:'IMGW: '+args.eventName,
  description:args.description,eventType:'WEATHER',severity:severity(args.level),verification:'CONFIRMED',
  lifecycle:lifecycle(args.validFrom,args.validTo,args.now),messageContext:'ACTUAL',regions:args.regions,geographicScope:'REGIONAL',
  publishedAt:args.publishedAt,publicationDate:null,retrievedAt:args.now.toISOString(),validFrom:args.validFrom,validTo:args.validTo,
  sources:[{id:sourceId,name:args.kind==='METEO'?'IMGW-PIB — ostrzeżenia meteorologiczne':'IMGW-PIB — ostrzeżenia hydrologiczne',url:sourceUrl,tier:1}],
  instructions:[],officialWarning:true,reviewed:false,revision:1,correction:null,latitude:null,longitude:null,geometry:null,
  locationText:args.locationText,areaPrecision:args.areaPrecision,origin:'OFFICIAL_PL',countryCode:'PL',
  adapterVersion:IMGW_VERSION,sourceContentHash:createHash('sha256').update(JSON.stringify(args.raw)).digest('hex'),isDemo:false,
 });
}
function parseMeteo(raw:Raw,now:Date):Event{
 const eventName=textField(raw,['nazwa_zdarzenia','zdarzenie'])!,office=textField(raw,['biuro'])!,level=warningLevel(raw,'METEO');
 const publishedAt=dateField(raw,['opublikowano']),validFrom=dateField(raw,['obowiazuje_od','data_od']),validTo=dateField(raw,['obowiazuje_do','data_do']);
 if(Date.parse(validTo)<=Date.parse(validFrom))throw new Error('IMGW_VALIDITY_ORDER_INVALID');
 const p=probability(raw),body=textField(raw,['tresc','przebieg'])!,comment=textField(raw,['komentarz','uwagi'],false);
 const terytRaw=raw.teryt;
 if(!Array.isArray(terytRaw)||!terytRaw.length||terytRaw.length>1000||terytRaw.some(v=>typeof v!=='string'||!/^\d{2,7}$/.test(v)))throw new Error('IMGW_METEO_TERYT_INVALID');
 const teryt=unique(terytRaw as string[]);
 const regions=unique(teryt.map(code=>{const region=code.slice(0,2);if(!(region in REGIONS))throw new Error('IMGW_UNKNOWN_REGION');return region;})).sort();
 const parts=[body,'Prawdopodobieństwo: '+p+'%'];if(comment)parts.push('Komentarz: '+comment);
 return eventBase({kind:'METEO',raw,eventName,office,level,publishedAt,validFrom,validTo,regions,description:parts.join('\n\n'),locationText:'TERYT: '+teryt.join(', '),areaPrecision:teryt.some(v=>v.length>2)?'PROVINCE_SUBSET':'PROVINCE',now});
}
function parseHydro(raw:Raw,now:Date):Event{
 const eventName=textField(raw,['zdarzenie','nazwa_zdarzenia'])!,office=textField(raw,['biuro'])!,level=warningLevel(raw,'HYDRO');
 const publishedAt=dateField(raw,['opublikowano']),validFrom=dateField(raw,['data_od','obowiazuje_od']),validTo=dateField(raw,['data_do','obowiazuje_do']);
 if(Date.parse(validTo)<=Date.parse(validFrom))throw new Error('IMGW_VALIDITY_ORDER_INVALID');
 const p=probability(raw),body=textField(raw,['przebieg','tresc'])!,comment=textField(raw,['komentarz','uwagi'],false),areasRaw=raw.obszary;
 if(!Array.isArray(areasRaw)||!areasRaw.length||areasRaw.length>100||areasRaw.some(v=>!isRaw(v)))throw new Error('IMGW_HYDRO_AREAS_INVALID');
 const descriptions:string[]=[],regions:string[]=[];
 for(const area of areasRaw as Raw[]){
  regions.push(regionByName(textField(area,['wojewodztwo'])!));descriptions.push(textField(area,['opis'])!);
  const basins=area.kod_zlewni;if(basins!==undefined&&(!Array.isArray(basins)||basins.some(v=>typeof v!=='string')))throw new Error('IMGW_HYDRO_BASIN_CODES_INVALID');
 }
 const parts=[body,'Prawdopodobieństwo: '+p+'%'];if(comment)parts.push('Komentarz: '+comment);
 return eventBase({kind:'HYDRO',raw,eventName,office,level,publishedAt,validFrom,validTo,regions:unique(regions).sort(),description:parts.join('\n\n'),locationText:unique(descriptions).join('; '),areaPrecision:'PROVINCE_SUBSET',now});
}
export function parseImgwMeteo(text:string,now=new Date()){return parsePayload(text).map(raw=>parseMeteo(raw,now));}
export function parseImgwHydro(text:string,now=new Date()){return parsePayload(text).map(raw=>parseHydro(raw,now));}
export function isAllowedImgwUrl(url:string){return url===IMGW_METEO_URL||url===IMGW_HYDRO_URL;}
export const imgwMeteoAdapter:SourceAdapter={id:'IMGW_METEO',version:IMGW_VERSION,minSyncIntervalSeconds:300,async sync({now,fetchText}){return {events:parseImgwMeteo(await fetchText(IMGW_METEO_URL),now),complete:true,coverage:'ACTIVE_WARNINGS',pagesFetched:1};}};
export const imgwHydroAdapter:SourceAdapter={id:'IMGW_HYDRO',version:IMGW_VERSION,minSyncIntervalSeconds:300,async sync({now,fetchText}){return {events:parseImgwHydro(await fetchText(IMGW_HYDRO_URL),now),complete:true,coverage:'ACTIVE_WARNINGS',pagesFetched:1};}};

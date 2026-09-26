import {DateTime} from 'luxon';
import {REGIONS} from './domain.js';
import {radiationMeasurementSchema,type RadiationMeasurement} from './radiation.js';
import type {SourceAdapter} from './source-adapter.js';

export const PAA_MEASUREMENTS_BASE='https://monitoring.paa.gov.pl/geoserver/ows';
export const PAA_MEASUREMENTS_VERSION='paa-wfs/1.0.0';

export function paaMeasurementsUrl(now=new Date()){
 const day=DateTime.fromJSDate(now,{zone:'utc'}).toFormat("yyyy-MM-dd'T'00:00:00.000'Z'");
 const u=new URL(PAA_MEASUREMENTS_BASE);
 u.searchParams.set('service','WFS');
 u.searchParams.set('version','2.0.0');
 u.searchParams.set('request','GetFeature');
 u.searchParams.set('typeNames','paa:kcad_siec_pms_moc_dawki_mapa');
 u.searchParams.set('outputFormat','application/json');
 u.searchParams.set('viewparams',`date_from:${day};date_to:${day}`);
 return u.href;
}

export function isAllowedPaaMeasurementsUrl(value:string){
 try{
  const u=new URL(value);
  if(u.protocol!=='https:'||u.hostname!=='monitoring.paa.gov.pl'||u.port||u.username||u.password||u.pathname!=='/geoserver/ows'||u.hash)return false;
  const expected=new URL(paaMeasurementsUrl(new Date('2026-01-02T12:00:00Z')));
  const keys=[...u.searchParams.keys()].sort();
  if(keys.join(',')!==[...expected.searchParams.keys()].sort().join(','))return false;
  if(u.searchParams.get('service')!=='WFS'||u.searchParams.get('version')!=='2.0.0'||u.searchParams.get('request')!=='GetFeature'||u.searchParams.get('typeNames')!=='paa:kcad_siec_pms_moc_dawki_mapa'||u.searchParams.get('outputFormat')!=='application/json')return false;
  return /^date_from:\d{4}-\d{2}-\d{2}T00:00:00\.000Z;date_to:\d{4}-\d{2}-\d{2}T00:00:00\.000Z$/.test(u.searchParams.get('viewparams')??'');
 }catch{return false;}
}

function parseUtcMinute(value:unknown){
 if(typeof value!=='string')throw new Error('PAA_MEASUREMENTS_CONTRACT_CHANGED');
 for(const format of ['yyyy-MM-dd HH:mm','yyyy-MM-dd HH:mm:ss']){
  const d=DateTime.fromFormat(value,format,{zone:'utc'});
  if(d.isValid)return d.toUTC().toISO()!;
 }
 throw new Error('PAA_MEASUREMENTS_CONTRACT_CHANGED');
}
function numberValue(value:unknown){
 if(typeof value==='number'&&Number.isFinite(value)&&value>=0)return value;
 if(typeof value!=='string')throw new Error('PAA_MEASUREMENTS_CONTRACT_CHANGED');
 const match=value.trim().replace(',','.').match(/^(\d+(?:\.\d+)?)\s*(?:µSv\/h|uSv\/h)?$/i);
 if(!match)throw new Error('PAA_MEASUREMENTS_CONTRACT_CHANGED');
 const n=Number(match[1]);if(!Number.isFinite(n)||n<0)throw new Error('PAA_MEASUREMENTS_CONTRACT_CHANGED');return n;
}
function regionId(properties:Record<string,unknown>){
 const raw=[properties.wojewodztwo,properties.województwo,properties.province,properties.region].find(v=>typeof v==='string') as string|undefined;
 if(!raw)return null;
 const normalized=raw.trim().toLocaleLowerCase('pl');
 return Object.keys(REGIONS).find(id=>REGIONS[id].toLocaleLowerCase('pl')===normalized)??null;
}

export function parsePaaMeasurements(raw:string,now=new Date()):RadiationMeasurement[]{
 let body:unknown;try{body=JSON.parse(raw);}catch{throw new Error('PAA_MEASUREMENTS_JSON_INVALID');}
 if(!body||typeof body!=='object'||(body as any).type!=='FeatureCollection'||!Array.isArray((body as any).features))throw new Error('PAA_MEASUREMENTS_CONTRACT_CHANGED');
 const features=(body as any).features as unknown[];
 if(!features.length)throw new Error('PAA_MEASUREMENTS_EMPTY');
 if(features.length>500)throw new Error('PAA_MEASUREMENTS_TOO_MANY_FEATURES');
 const items=features.map((feature):RadiationMeasurement=>{
  if(!feature||typeof feature!=='object'||(feature as any).type!=='Feature')throw new Error('PAA_MEASUREMENTS_CONTRACT_CHANGED');
  const properties=(feature as any).properties;
  const geometry=(feature as any).geometry;
  if(!properties||typeof properties!=='object'||!geometry||geometry.type!=='Point'||!Array.isArray(geometry.coordinates)||geometry.coordinates.length<2)throw new Error('PAA_MEASUREMENTS_CONTRACT_CHANGED');
  const p=properties as Record<string,unknown>,coordinates=geometry.coordinates as unknown[];
  const longitude=Number(coordinates[0]),latitude=Number(coordinates[1]);
  if(!Number.isFinite(latitude)||!Number.isFinite(longitude)||latitude<49||latitude>55||longitude<14||longitude>24.2)throw new Error('PAA_MEASUREMENTS_GEOMETRY_INVALID');
  const stationId=typeof p.id==='string'?p.id.trim():'';
  const name=typeof p.stacja==='string'?p.stacja.trim():'';
  if(!stationId||stationId.length>100||!name||name.length>200)throw new Error('PAA_MEASUREMENTS_CONTRACT_CHANGED');
  const measuredAt=parseUtcMinute(p.tip_date);
  if(Date.parse(measuredAt)>now.getTime()+5*60*1000)throw new Error('PAA_MEASUREMENTS_FUTURE_READING');
  return radiationMeasurementSchema.parse({
   stationId,name,latitude,longitude,measuredAt,value:numberValue(p.tip_value),unit:'µSv/h',
   sourceUpdatedAt:measuredAt,regionId:regionId(p),
  });
 });
 if(new Set(items.map(p=>p.stationId)).size!==items.length)throw new Error('PAA_DUPLICATE_STATION');
 return items;
}

export const paaMeasurementsAdapter:SourceAdapter={
 id:'PAA_MEASUREMENTS',version:PAA_MEASUREMENTS_VERSION,minSyncIntervalSeconds:300,
 async sync({now,fetchText}){
  const radiationMeasurements=parsePaaMeasurements(await fetchText(paaMeasurementsUrl(now)),now);
  return {events:[],radiationMeasurements,complete:true,coverage:'MEASUREMENT_NETWORK',pagesFetched:1};
 }
};

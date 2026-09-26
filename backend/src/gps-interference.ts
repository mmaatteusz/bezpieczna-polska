import {parse} from 'csv-parse/sync';
import {cellToBoundary,cellToLatLng,getResolution,isValidCell} from 'h3-js';
import {z} from 'zod';

export const GPSJAM_BASE='https://gpsjam.org/data';
export const GPS_INTERFERENCE_AUTHORITY='OSINT';
export const GPS_INTERFERENCE_MAX_AGE_SECONDS=36*60*60;

const bounds=z.tuple([
  z.number().min(-180).max(180),
  z.number().min(-85).max(85),
  z.number().min(-180).max(180),
  z.number().min(-85).max(85),
]).refine(v=>v[0]<v[2]&&v[1]<v[3]);

export const gpsInterferenceQuery=z.object({
  bbox:z.string()
    .regex(/^-?\d+(?:\.\d+)?,-?\d+(?:\.\d+)?,-?\d+(?:\.\d+)?,-?\d+(?:\.\d+)?$/)
    .transform(v=>v.split(',').map(Number))
    .pipe(bounds)
    .refine(v=>(v[2]-v[0])<=60&&(v[3]-v[1])<=40,'BBOX_TOO_LARGE'),
  date:z.string().regex(/^\d{4}-\d{2}-\d{2}$/).optional(),
});

export type GpsInterferenceQuery=z.infer<typeof gpsInterferenceQuery>;

type GpsCell={
  h3:string;
  goodAircraft:number;
  badAircraft:number;
  percentBad:number;
  level:'LOW'|'MEDIUM'|'HIGH';
  center:[number,number];
  boundary:[number,number][];
};

type CacheEntry={expiresAt:number;cells:GpsCell[];date:string};
const cache=new Map<string,CacheEntry>();

function utcDate(daysAgo:number,now=new Date()){
  const d=new Date(Date.UTC(now.getUTCFullYear(),now.getUTCMonth(),now.getUTCDate()-daysAgo));
  return d.toISOString().slice(0,10);
}

export function defaultGpsInterferenceDate(now=new Date()){return utcDate(1,now);}

export function gpsJamPercent(good:number,bad:number){
  const total=good+bad;
  if(total<=0)return 0;
  return Math.max(0,100*(bad-1)/total);
}

export function gpsJamLevel(percent:number):GpsCell['level']{
  if(percent>10)return 'HIGH';
  if(percent>2)return 'MEDIUM';
  return 'LOW';
}

export function parseGpsJamCsv(text:string):GpsCell[]{
  const rows=parse(text,{columns:true,skip_empty_lines:true,trim:true}) as Record<string,string>[];
  if(!rows.length)throw new Error('GPSJAM_EMPTY');
  const expected=['hex','count_good_aircraft','count_bad_aircraft'];
  if(!expected.every(k=>Object.prototype.hasOwnProperty.call(rows[0],k)))throw new Error('GPSJAM_CONTRACT_CHANGED');

  const cells:GpsCell[]=[];
  for(const row of rows){
    const h3=row.hex;
    const good=Number(row.count_good_aircraft);
    const bad=Number(row.count_bad_aircraft);
    if(!isValidCell(h3)||getResolution(h3)!==4||!Number.isInteger(good)||good<0||!Number.isInteger(bad)||bad<0)continue;
    const [lat,lon]=cellToLatLng(h3);
    if(!Number.isFinite(lat)||!Number.isFinite(lon))continue;
    const rawBoundary=cellToBoundary(h3,true);
    if(rawBoundary.length<6)continue;
    const boundary=rawBoundary.map(([lng,latitude])=>[lng,latitude] as [number,number]);
    if(boundary[0][0]!==boundary.at(-1)![0]||boundary[0][1]!==boundary.at(-1)![1]){
      boundary.push([...boundary[0]] as [number,number]);
    }
    const percentBad=gpsJamPercent(good,bad);
    cells.push({
      h3,
      goodAircraft:good,
      badAircraft:bad,
      percentBad,
      level:gpsJamLevel(percentBad),
      center:[lon,lat],
      boundary,
    });
  }
  if(!cells.length)throw new Error('GPSJAM_NO_VALID_CELLS');
  return cells;
}

async function fetchCsv(date:string):Promise<string|null>{
  const url=`${GPSJAM_BASE}/${date}-h3_4.csv`;
  const response=await fetch(url,{
    redirect:'error',
    signal:AbortSignal.timeout(20000),
    headers:{
      'User-Agent':'BezpiecznaPolska/0.1 (GPS interference map; source attribution GPSJAM)',
      'Accept':'text/csv',
    },
  });
  if(response.status===404)return null;
  if(!response.ok)throw new Error(`GPSJAM_HTTP_${response.status}`);
  if(!response.body)throw new Error('GPSJAM_EMPTY_BODY');
  const declared=Number(response.headers.get('content-length')??'0');
  if(declared&&(!Number.isInteger(declared)||declared>32*1024*1024))throw new Error('GPSJAM_TOO_LARGE');
  let size=0;
  const chunks:Uint8Array[]=[];
  for await(const chunk of response.body){
    size+=chunk.length;
    if(size>32*1024*1024)throw new Error('GPSJAM_TOO_LARGE');
    chunks.push(chunk);
  }
  return new TextDecoder('utf-8',{fatal:true}).decode(Buffer.concat(chunks));
}

async function loadDate(date:string):Promise<CacheEntry|null>{
  const existing=cache.get(date);
  if(existing&&existing.expiresAt>Date.now())return existing;
  const text=await fetchCsv(date);
  if(text===null)return null;
  const entry={expiresAt:Date.now()+6*60*60*1000,cells:parseGpsJamCsv(text),date};
  cache.set(date,entry);
  while(cache.size>4){
    const first=cache.keys().next().value as string|undefined;
    if(first===undefined)break;
    cache.delete(first);
  }
  return entry;
}

function inBbox(cell:GpsCell,bbox:number[]){
  const [west,south,east,north]=bbox;
  const [lon,lat]=cell.center;
  if(lon>=west&&lon<=east&&lat>=south&&lat<=north)return true;
  return cell.boundary.some(([x,y])=>x>=west&&x<=east&&y>=south&&y<=north);
}

export async function gpsInterferenceViewport(query:GpsInterferenceQuery,now=new Date()){
  let requested=query.date;
  let entry:CacheEntry|null=null;
  if(requested){
    entry=await loadDate(requested);
  }else{
    for(let daysAgo=1;daysAgo<=3&&!entry;daysAgo++){
      requested=utcDate(daysAgo,now);
      entry=await loadDate(requested);
    }
  }
  if(!entry)throw new Error('GPSJAM_DATA_UNAVAILABLE');

  const visible=entry.cells.filter(cell=>inBbox(cell,query.bbox));
  const features=visible.map(cell=>({
    type:'Feature',
    id:cell.h3,
    geometry:{type:'Polygon',coordinates:[cell.boundary]},
    properties:{
      h3:cell.h3,
      level:cell.level,
      percentBad:Number(cell.percentBad.toFixed(2)),
      goodAircraft:cell.goodAircraft,
      badAircraft:cell.badAircraft,
      date:entry!.date,
    },
  }));

  return {
    type:'FeatureCollection',
    metadata:{
      schemaVersion:1,
      layerId:'gps_interference',
      authority:GPS_INTERFERENCE_AUTHORITY,
      provider:'GPSJAM',
      dataDate:entry.date,
      generatedAt:new Date().toISOString(),
      sourceUrl:'https://gpsjam.org/',
      methodologyUrl:'https://gpsjam.org/faq',
      cadence:'DAILY',
      maxAgeSeconds:GPS_INTERFERENCE_MAX_AGE_SECONDS,
      interpretation:'Aircraft-reported navigation accuracy; degraded accuracy does not prove deliberate jamming.',
      thresholds:{LOW:'0-2%',MEDIUM:'>2-10%',HIGH:'>10%'},
      bbox:query.bbox,
      returned:features.length,
    },
    features,
  };
}

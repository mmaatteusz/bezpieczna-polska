import {z} from 'zod';
import type {SourceAdapter} from './source-adapter.js';

export const NEPTUN_API='https://neptun.in.ua/api/v1/threats';
export const NEPTUN_HOME='https://neptun.in.ua/';
export const NEPTUN_LIVE_VERSION='neptun-public-v1/1.0.2';
export const NEPTUN_PUBLIC_MIN_PRECISION_KM=10;

const timestamp=z.iso.datetime({offset:true});
const finite=z.number().finite();
const knownThreatTypes=['uav','fpv','recon','missile','ballistic','kab','mig31k','unknown'] as const;
const threatType=z.string().min(1).max(80).transform((value):typeof knownThreatTypes[number]=>
  (knownThreatTypes as readonly string[]).includes(value)?value as typeof knownThreatTypes[number]:'unknown'
);
const rawThreatSchema=z.object({
  id:z.string().min(1).max(120),
  // Upstream may add categories without notice. Unknown categories remain visible
  // as generic threats instead of taking the entire live snapshot down.
  type:threatType,
  title:z.string().min(1).max(300),
  region:z.string().max(250).nullish().transform(v=>v??null),
  district:z.string().max(250).nullish().transform(v=>v??null),
  locality:z.string().max(250).nullish().transform(v=>v??null),
  lat:z.number().min(-90).max(90).nullish().transform(v=>v??null),
  lon:z.number().min(-180).max(180).nullish().transform(v=>v??null),
  heading:finite.min(0).max(360).nullish().transform(v=>v??null),
  confidenceLevel:z.enum(['low','medium','high']).default('low'),
  sourceCount:z.number().int().min(0).max(1000).default(0),
  count:z.number().int().min(0).max(10000).nullish().transform(v=>v??null),
  updatedAt:timestamp,
  status:z.enum(['active','stale','resolved']),
  explanationShort:z.string().max(1000).nullish().transform(v=>v??null),
  velocity:z.object({
    bearingDeg:finite.min(0).max(360),
    speedKmh:finite.min(0).max(5000)
  }).nullish().transform(v=>v??null),
  confirmedAt:timestamp.nullish().transform(v=>v??null),
  uncertaintyKm:finite.min(0).max(500).nullish().transform(v=>v??null),
  positionQuality:z.string().max(80).nullish().transform(v=>v??null),
  advisory:z.boolean().default(false),
  areaOnly:z.boolean().default(false)
}).superRefine((t,ctx)=>{
  if((t.lat===null)!==(t.lon===null))ctx.addIssue({code:'custom',message:'NEPTUN coordinate pair required'});
  if(!t.areaOnly&&t.lat===null)ctx.addIssue({code:'custom',message:'NEPTUN point threat requires coordinates'});
});

const responseSchema=z.object({
  serverTime:timestamp,
  threats:z.array(rawThreatSchema).max(5000)
});

export type PublicNeptunThreat={
  id:string;
  type:'uav'|'fpv'|'recon'|'missile'|'ballistic'|'kab'|'mig31k'|'unknown';
  title:string;
  region:string|null;
  confidenceLevel:'low'|'medium'|'high';
  sourceCount:number;
  count:number|null;
  updatedAt:string;
  status:'active'|'stale';
  advisory:boolean;
  areaOnly:boolean;
  latitude:number|null;
  longitude:number|null;
  precisionKm:number|null;
  sourceUrl:string;
};

function publicThreatTitle(type:PublicNeptunThreat['type']){
  return ({
    uav:'BSP / dron',
    fpv:'FPV / dron',
    recon:'Obiekt rozpoznawczy',
    missile:'Rakieta',
    ballistic:'Zagrożenie balistyczne',
    kab:'Kierowana bomba lotnicza',
    mig31k:'MiG-31K',
    unknown:'Nieokreślone zagrożenie'
  } as const)[type];
}

function coarsePoint(latitude:number,longitude:number,precisionKm:number){
  const latStep=Math.max(0.1,precisionKm/111);
  const cos=Math.max(0.2,Math.abs(Math.cos(latitude*Math.PI/180)));
  const lonStep=Math.max(0.1,precisionKm/(111*cos));
  const lat=Math.max(-90,Math.min(90,Math.round(latitude/latStep)*latStep));
  const lon=Math.max(-180,Math.min(180,Math.round(longitude/lonStep)*lonStep));
  return {latitude:Number(lat.toFixed(4)),longitude:Number(lon.toFixed(4))};
}

export function parseNeptunLive(input:unknown,now=new Date()){
  const parsed=responseSchema.parse(input);
  if(Date.parse(parsed.serverTime)>now.getTime()+30000)throw new Error('NEPTUN_FUTURE_SNAPSHOT');
  const seen=new Set<string>();
  const threats:PublicNeptunThreat[]=[];
  for(const t of parsed.threats){
    if(!seen.add(t.id))throw new Error('NEPTUN_DUPLICATE_ID');
    if(Date.parse(t.updatedAt)>now.getTime()+30000)throw new Error('NEPTUN_FUTURE_THREAT');
    if(t.status==='resolved')continue;
    const precision=t.areaOnly||t.lat===null||t.lon===null
      ? null
      : Math.max(NEPTUN_PUBLIC_MIN_PRECISION_KM,Math.ceil(t.uncertaintyKm??NEPTUN_PUBLIC_MIN_PRECISION_KM));
    const point=precision===null?null:coarsePoint(t.lat!,t.lon!,precision);
    threats.push({
      id:t.id,
      type:t.type,
      title:publicThreatTitle(t.type),
      region:t.region,
      confidenceLevel:t.confidenceLevel,
      sourceCount:t.sourceCount,
      count:t.count,
      updatedAt:t.updatedAt,
      status:t.status,
      advisory:t.advisory,
      areaOnly:t.areaOnly,
      latitude:point?.latitude??null,
      longitude:point?.longitude??null,
      precisionKm:precision,
      sourceUrl:NEPTUN_HOME
    });
  }
  return {serverTime:parsed.serverTime,threats};
}

export const neptunLiveAdapter:SourceAdapter={
  id:'NEPTUN',
  version:NEPTUN_LIVE_VERSION,
  minSyncIntervalSeconds:5,
  async sync({now,fetchText}){
    const snapshot=parseNeptunLive(JSON.parse(await fetchText(NEPTUN_API)),now);
    return {
      events:[],
      neptunMetadata:snapshot,
      complete:false,
      coverage:'ACTIVE_WARNINGS',
      pagesFetched:1
    };
  }
};

import {z} from 'zod';
import {sourceHealth} from './domain.js';
import type {Store} from './store.js';

const date=z.iso.datetime({offset:true});
export const NEPTUN_SAFETY_DELAY_HOURS=24;
export const NEPTUN_MIN_PRECISION_KM=10;

const sourceSchema=z.object({
 id:z.string().min(1).max(80),
 name:z.string().min(1).max(200),
 url:z.url().refine(v=>{const u=new URL(v);return u.protocol==='https:'&&!u.username&&!u.password;}),
 tier:z.number().int().min(1).max(4),
 origin:z.enum(['OFFICIAL_PL','OFFICIAL_FOREIGN','AGGREGATOR','OSINT'])
});

export const neptunObservationSchema=z.object({
 id:z.string().min(1).max(100),
 observedAt:date,
 latitude:z.number().min(-90).max(90).nullable(),
 longitude:z.number().min(-180).max(180).nullable(),
 precisionKm:z.number().min(NEPTUN_MIN_PRECISION_KM).max(500).nullable(),
 locationText:z.string().max(500).nullable(),
 verification:z.enum(['CONFIRMED','PROBABLE','UNVERIFIED','REFUTED','DISPUTED']),
 source:sourceSchema,
 note:z.string().max(2000).nullable(),
 correction:z.string().max(1000).nullable()
}).superRefine((o,ctx)=>{
 const hasLat=o.latitude!==null,hasLon=o.longitude!==null,hasPrecision=o.precisionKm!==null;
 if(hasLat!==hasLon)ctx.addIssue({code:'custom',message:'NEPTUN coordinates must be paired'});
 if((hasLat||hasLon)!==hasPrecision)ctx.addIssue({code:'custom',message:'NEPTUN coordinates require coarse precision'});
});

export const neptunTrackSchema=z.object({
 id:z.string().regex(/^NEPTUN-[A-Za-z0-9._:-]{1,120}$/),
 title:z.string().min(1).max(300),
 description:z.string().max(5000),
 objectType:z.enum(['AIR_OBJECT','MARITIME_EVENT','GROUND_EVENT','CIVIL_EVENT','OTHER']),
 lifecycle:z.literal('ENDED'),
 verification:z.enum(['CONFIRMED','PROBABLE','UNVERIFIED','REFUTED','DISPUTED']),
 startedAt:date.nullable(),
 endedAt:date,
 directionText:z.string().max(500).nullable(),
 observations:z.array(neptunObservationSchema).min(1).max(100),
 revision:z.number().int().positive(),
 reviewed:z.boolean().default(false)
}).superRefine((t,ctx)=>{
 const ended=Date.parse(t.endedAt),started=t.startedAt?Date.parse(t.startedAt):null;
 if(started!==null&&started>ended)ctx.addIssue({code:'custom',message:'NEPTUN start after end'});
 const ids=new Set<string>();let previous=-Infinity;
 for(const o of t.observations){
  if(ids.has(o.id))ctx.addIssue({code:'custom',message:'NEPTUN duplicate observation'});
  ids.add(o.id);
  const at=Date.parse(o.observedAt);
  if(at<previous)ctx.addIssue({code:'custom',message:'NEPTUN observations must be chronological'});
  if(at>ended)ctx.addIssue({code:'custom',message:'NEPTUN observation after track end'});
  if(started!==null&&at<started)ctx.addIssue({code:'custom',message:'NEPTUN observation before track start'});
  previous=at;
 }
});
export type NeptunTrack=z.infer<typeof neptunTrackSchema>;

function coarsePoint(latitude:number,longitude:number,precisionKm:number){
 const latStep=Math.max(0.1,precisionKm/111);
 const cos=Math.max(0.2,Math.abs(Math.cos(latitude*Math.PI/180)));
 const lonStep=Math.max(0.1,precisionKm/(111*cos));
 const lat=Math.max(-90,Math.min(90,Math.round(latitude/latStep)*latStep));
 const lon=Math.max(-180,Math.min(180,Math.round(longitude/lonStep)*lonStep));
 return {latitude:Number(lat.toFixed(4)),longitude:Number(lon.toFixed(4))};
}
export function publicNeptunTrack(input:NeptunTrack){
 const t=neptunTrackSchema.parse(input);
 return {...t,observations:t.observations.map(o=>{
  if(o.latitude===null||o.longitude===null||o.precisionKm===null)return o;
  return {...o,...coarsePoint(o.latitude,o.longitude,o.precisionKm)};
 })};
}
export function neptunPublishable(track:NeptunTrack,now=new Date()){
 return track.lifecycle==='ENDED'&&Date.parse(track.endedAt)<=now.getTime()-NEPTUN_SAFETY_DELAY_HOURS*3600000;
}
export async function neptunSnapshot(store:Store,now=new Date()){
 const all=await store.neptunTracks();
 const tracks=all.filter(t=>neptunPublishable(t,now)).map(publicNeptunTrack);
 const features=tracks.flatMap(t=>{
  const coords=t.observations.filter(o=>o.latitude!==null&&o.longitude!==null).map(o=>[o.longitude!,o.latitude!] as [number,number]);
  if(coords.length<2)return [];
  return [{type:'Feature' as const,id:t.id,geometry:{type:'LineString' as const,coordinates:coords},properties:{trackId:t.id,title:t.title,objectType:t.objectType,verification:t.verification,endedAt:t.endedAt,directionText:t.directionText,observationCount:t.observations.length,historicalOnly:true}}];
 });
 const health=(await store.health()).find(h=>h.id==='NEPTUN')??null;
 return {
  schemaVersion:1,
  mode:'HISTORICAL_ONLY' as const,
  serverTime:now.toISOString(),
  safetyDelayHours:NEPTUN_SAFETY_DELAY_HOURS,
  minimumPublishedPrecisionKm:NEPTUN_MIN_PRECISION_KM,
  coverage:tracks.length?'CURATED_HISTORY':'NO_CONFIGURED_FEED',
  sourceHealth:health?sourceHealth([health],now)[0]:null,
  tracks,
  map:{type:'FeatureCollection' as const,features},
  disclaimer:'NEPTUN pokazuje wyłącznie zakończone, historyczne i zgrubne ślady. Nie publikuje aktywnych dokładnych pozycji.'
 };
}

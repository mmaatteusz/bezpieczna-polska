import {z} from 'zod';
import {REGIONS,sourceHealth} from './domain.js';
import {Store} from './store.js';
import {shelterSchema} from './shelter.js';
// Shared discovery contract: disabled providers never return fabricated data.
export const mapLayers=[
 {id:'radiation',sourceId:'PAA',authority:'OFFICIAL_PL',enabled:true,measurementsEnabled:false},
 {id:'shelters',sourceId:'SHELTERS',authority:'OFFICIAL_PL',enabled:true},
 ...['RCB','WCZK','RSO_WCZK','border','police_PSP'].map(id=>({id,sourceId:id,authority:'OFFICIAL_PL',enabled:false})),
 {id:'Ukraine_alerts',sourceId:'UA',authority:'OFFICIAL_FOREIGN',enabled:false,geometry:'ADMINISTRATIVE_POLYGONS_ONLY',integrationNote:'UkraineAlarm pozostaje ukryty do czasu skonfigurowania i zweryfikowania klucza API.'},
 {id:'NEPTUN',sourceId:'NEPTUN',authority:'OSINT',enabled:true,geometry:'COARSE_LIVE_POINTS_AND_HISTORICAL_LINES',mode:'LIVE_AND_HISTORY'},
];
const bounds=z.tuple([z.number().min(-180).max(180),z.number().min(-85).max(85),z.number().min(-180).max(180),z.number().min(-85).max(85)]).refine(b=>b[0]<b[2]&&b[1]<b[3]);
export const mapQuery=z.object({
 bbox:z.string().regex(/^-?\d+(?:\.\d+)?,-?\d+(?:\.\d+)?,-?\d+(?:\.\d+)?,-?\d+(?:\.\d+)?$/).transform(v=>v.split(',').map(Number)).pipe(bounds),
 zoom:z.coerce.number().min(0).max(22),
 regionId:z.string().refine(v=>v==='PL'||v in REGIONS).default('PL'),
 availability:z.enum(['ALL','24H','ON_REQUEST','LIMITED_HOURS','UNKNOWN']).default('ALL'),
});
export type MapQuery=z.infer<typeof mapQuery>;
export async function shelterViewport(store:Store,q:MapQuery){
 if(store.db.kind!=='postgres')throw new Error('POSTGIS_REQUIRED');
 return store.db.transaction(async db=>{
  const health=(await new Store(db).health()).find(h=>h.id==='SHELTERS')??null;
  const where=['ST_Intersects(geom,ST_MakeEnvelope(?,?,?,?,4326))'],params:unknown[]=[...q.bbox];
  if(q.regionId!=='PL'){where.push('region_id=?');params.push(q.regionId);}
  if(q.availability!=='ALL'){where.push("payload::jsonb->>'availability'=?");params.push(q.availability);}
  const clause=' WHERE '+where.join(' AND ');
  const total=Number((await db.all('SELECT COUNT(*) AS n FROM shelters'+clause,params))[0].n);
  let features:Record<string,unknown>[];
  if(total<=500){
   const rows=await db.all('SELECT payload FROM shelters'+clause+' ORDER BY id LIMIT 500',params);
   features=rows.map(r=>{const s=shelterSchema.parse(JSON.parse(r.payload as string));return {type:'Feature',id:s.id,geometry:{type:'Point',coordinates:[s.longitude,s.latitude]},properties:{...s,cluster:false}};});
  }else{
   // At most 33 x 33 cells. All points count; no truncated pagination.
   // Counts refer only to this viewport and filter.
   const dx=(q.bbox[2]-q.bbox[0])/32,dy=(q.bbox[3]-q.bbox[1])/32;
   const rows=await db.all(`WITH visible AS (SELECT ST_X(geom) AS x,ST_Y(geom) AS y FROM shelters${clause}), cells AS (SELECT x,y,floor((x-?)/?) AS gx,floor((y-?)/?) AS gy FROM visible) SELECT gx,gy,AVG(x) AS lon,AVG(y) AS lat,COUNT(*) AS n FROM cells GROUP BY gx,gy ORDER BY gx,gy`,[...params,q.bbox[0],dx,q.bbox[1],dy]);
   features=rows.map(r=>({type:'Feature',id:`cluster-${r.gx}-${r.gy}`,geometry:{type:'Point',coordinates:[Number(r.lon),Number(r.lat)]},properties:{cluster:true,point_count:Number(r.n),expansionZoom:Math.min(22,Math.floor(q.zoom)+2)}}));
  }
  return {type:'FeatureCollection',metadata:{schemaVersion:1,layerId:'shelters',authority:'OFFICIAL_PL',...q,total,returned:features.length,clustered:total>500,version:health?.sourceContentHash??null,dataDate:health?.dataDate??null,sourceUrl:'https://dane.gov.pl/pl/dataset/28058,punkty-schronienia-w-polsce',health:health?sourceHealth([health])[0]:null,serverTime:new Date().toISOString()},features};
 });
}

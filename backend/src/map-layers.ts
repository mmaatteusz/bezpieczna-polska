import {z} from 'zod';
import {REGIONS,sourceHealth} from './domain.js';
import {Store} from './store.js';
import {shelterSchema} from './shelter.js';
const uaConfigured=Boolean(process.env.UKRAINE_ALARM_API_KEY?.trim());
// Shared discovery contract: disabled providers never return fabricated data.
export const mapLayers=[
 {id:'radiation',sourceId:'PAA_MEASUREMENTS',authority:'OFFICIAL_PL',enabled:true,measurementsEnabled:true},
 {id:'shelters',sourceId:'SHELTERS',authority:'OFFICIAL_PL',enabled:true},
 {id:'gps_interference',sourceId:'GPSJAM',authority:'OSINT',enabled:true,geometry:'DAILY_H3_POLYGONS',mode:'DAILY_SNAPSHOT',sourceUrl:'https://gpsjam.org/',integrationNote:'Dobowa mapa obniżonej dokładności nawigacji raportowanej przez statki powietrzne. Nie dowodzi przyczyny ani celowego zagłuszania.'},
 ...['RCB','WCZK','RSO_WCZK','border','police_PSP'].map(id=>({id,sourceId:id,authority:'OFFICIAL_PL',enabled:false})),
 {id:'Ukraine_alerts',sourceId:'UA',authority:'OFFICIAL_FOREIGN',enabled:uaConfigured,geometry:'ADMINISTRATIVE_POLYGONS_ONLY',integrationNote:uaConfigured?'Oficjalne alarmy UkraineAlarm API v3; warstwa administracyjna Ukrainy.':'UkraineAlarm pozostaje ukryty do czasu skonfigurowania klucza API.'},
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

type ShelterClusterPlan=
 | {mode:'region';tier:'REGION';expansionZoom:number}
 | {mode:'grid';tier:'LOCAL'|'NEAR'|'DETAIL_OVERFLOW';cells:number;expansionZoom:number}
 | null;

export function shelterClusterPlan(zoom:number):ShelterClusterPlan{
 if(zoom<9)return {mode:'region',tier:'REGION',expansionZoom:9};
 if(zoom<12)return {mode:'grid',tier:'LOCAL',cells:6,expansionZoom:12};
 if(zoom<14)return {mode:'grid',tier:'NEAR',cells:12,expansionZoom:14};
 return null;
}

export async function shelterViewport(store:Store,q:MapQuery){
 if(store.db.kind!=='postgres')throw new Error('POSTGIS_REQUIRED');
 return store.db.transaction(async db=>{
  const health=(await new Store(db).health()).find(h=>h.id==='SHELTERS')??null;
  const where=['ST_Intersects(geom,ST_MakeEnvelope(?,?,?,?,4326))'],params:unknown[]=[...q.bbox];
  if(q.regionId!=='PL'){where.push('region_id=?');params.push(q.regionId);}
  if(q.availability!=='ALL'){where.push("payload::jsonb->>'availability'=?");params.push(q.availability);}
  const clause=' WHERE '+where.join(' AND ');
  const total=Number((await db.all('SELECT COUNT(*) AS n FROM shelters'+clause,params))[0].n);
  const requestedPlan=shelterClusterPlan(q.zoom);
  const plan:Exclude<ShelterClusterPlan,null>|null=requestedPlan??(
   total>1089?{mode:'grid',tier:'DETAIL_OVERFLOW',cells:18,expansionZoom:Math.min(22,Math.max(15,Math.floor(q.zoom)+1))}:null
  );
  let features:Record<string,unknown>[];
  if(plan===null){
   const rows=await db.all('SELECT payload FROM shelters'+clause+' ORDER BY id LIMIT 1089',params);
   features=rows.map(r=>{const s=shelterSchema.parse(JSON.parse(r.payload as string));return {type:'Feature',id:s.id,geometry:{type:'Point',coordinates:[s.longitude,s.latitude]},properties:{...s,cluster:false}};});
  }else if(plan.mode==='region'){
   // National/very wide views: one coarse cluster per voivodeship visible
   // in the current bbox. This keeps the country view readable.
   const rows=await db.all(`SELECT region_id AS region,AVG(ST_X(geom)) AS lon,AVG(ST_Y(geom)) AS lat,COUNT(*) AS n FROM shelters${clause} GROUP BY region_id ORDER BY region_id`,params);
   features=rows.map(r=>({type:'Feature',id:`cluster-region-${r.region}`,geometry:{type:'Point',coordinates:[Number(r.lon),Number(r.lat)]},properties:{cluster:true,clusterTier:plan.tier,regionId:String(r.region),point_count:Number(r.n),expansionZoom:plan.expansionZoom}}));
  }else{
   // Mid zoom levels use deliberately coarse viewport grids. The old 32x32
   // grid could produce ~1000 large circles and visually bury the base map.
   const cells=plan.cells;
   const dx=(q.bbox[2]-q.bbox[0])/cells,dy=(q.bbox[3]-q.bbox[1])/cells;
   const rows=await db.all(`WITH visible AS (SELECT ST_X(geom) AS x,ST_Y(geom) AS y FROM shelters${clause}), cells AS (SELECT x,y,LEAST(?-1,GREATEST(0,floor((x-?)/?))) AS gx,LEAST(?-1,GREATEST(0,floor((y-?)/?))) AS gy FROM visible) SELECT gx,gy,AVG(x) AS lon,AVG(y) AS lat,COUNT(*) AS n FROM cells GROUP BY gx,gy ORDER BY gx,gy`,[...params,cells,q.bbox[0],dx,cells,q.bbox[1],dy]);
   features=rows.map(r=>({type:'Feature',id:`cluster-${plan.tier}-${r.gx}-${r.gy}`,geometry:{type:'Point',coordinates:[Number(r.lon),Number(r.lat)]},properties:{cluster:true,clusterTier:plan.tier,point_count:Number(r.n),expansionZoom:plan.expansionZoom}}));
  }
  return {type:'FeatureCollection',metadata:{schemaVersion:1,layerId:'shelters',authority:'OFFICIAL_PL',...q,total,returned:features.length,clustered:plan!==null,clusterTier:plan?.tier??null,version:health?.sourceContentHash??null,dataDate:health?.dataDate??null,sourceUrl:'https://dane.gov.pl/pl/dataset/28058,punkty-schronienia-w-polsce',health:health?sourceHealth([health])[0]:null,serverTime:new Date().toISOString()},features};
 });
}

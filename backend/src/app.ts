import {aroundLocation,aroundQuerySchema} from './around.js';
import {radiationStatus} from './radiation.js';
import {mapLayers,mapQuery,shelterViewport} from './map-layers.js';
import {securityLevelStatus} from './security-level.js';
import Fastify from 'fastify';import rateLimit from '@fastify/rate-limit';import {timingSafeEqual} from 'node:crypto';import {z} from 'zod';
import {computeStatus,eventSchema,REGIONS,sourceHealth} from './domain.js';import {Store} from './store.js';import {initializeSources,ingest} from './adapters.js';
export async function buildApp(store:Store,adminToken?:string){
 const app=Fastify({logger:false,bodyLimit:128*1024});await app.register(rateLimit,{max:100,timeWindow:'1 minute'});
 app.addHook('onSend',async(_,r,p)=>{r.header('Cache-Control','no-store').header('X-Content-Type-Options','nosniff');return p;});
 app.setErrorHandler((e,_,r)=>{if(e instanceof z.ZodError)return r.code(400).send({error:'INVALID_REQUEST'});if(e instanceof Error&&['REVISION_CONFLICT','SHELTER_VERSION_CHANGED'].includes(e.message))return r.code(409).send({error:e.message});const status=typeof e==='object'&&e&&'statusCode'in e?Number(e.statusCode):500;return r.code(status>=400&&status<600?status:500).send({error:'REQUEST_FAILED'});});
 app.get('/healthz',async()=>({ok:true,version:'0.1.0-alpha.11'}));
 const regionQuery=z.object({regionId:z.string().refine(v=>v==='PL'||v in REGIONS).default('PL')});
 app.get('/status',async req=>{
  const {regionId}=regionQuery.parse(req.query),{events,health,incidents,radiationMeasurements}=await store.snapshot(),now=new Date();
  return {schemaVersion:1,evaluatedAt:now.toISOString(),radiation:radiationStatus(events,health,regionId,now,radiationMeasurements),...securityLevelStatus(events,health,regionId,now),poland:{...computeStatus(events,health,'PL',now,incidents),...securityLevelStatus(events,health,'PL',now)},region:{id:regionId,name:REGIONS[regionId]??'Cała Polska',...computeStatus(events,health,regionId,now,incidents),...securityLevelStatus(events,health,regionId,now)},sourceHealth:sourceHealth(health,now)};
 });
 app.get('/v1/map/layers',async()=>({schemaVersion:1,layers:mapLayers}));
 app.get('/v1/map/shelters',async(req,reply)=>{const q=mapQuery.parse(req.query);if(store.db.kind!=='postgres')return reply.code(503).send({error:'POSTGIS_REQUIRED'});return shelterViewport(store,q);});
 app.get('/v1/radiation',async req=>{const {regionId}=regionQuery.parse(req.query),s=await store.snapshot();return radiationStatus(s.events,s.health,regionId,new Date(),s.radiationMeasurements);});
 app.get('/v1/sources',async()=>({sourceHealth:sourceHealth(await store.health())}));
 app.get('/v1/around',async(req,reply)=>{
  if(store.db.kind!=='postgres')return reply.code(503).send({error:'POSTGIS_REQUIRED'});
  const raw=z.object({lat:z.string().optional(),lon:z.string().optional(),radiusKm:z.string().optional(),regionId:z.string().optional()}).parse(req.query);
  const q=aroundQuerySchema.parse({latitude:raw.lat,longitude:raw.lon,radiusKm:raw.radiusKm,regionId:raw.regionId});
  return aroundLocation(store,q,new Date());
 });
 app.get('/readyz',async(_,reply)=>{
  await store.db.all('SELECT 1 AS ok');
  const sources=sourceHealth(await store.health()).filter(s=>s.enabled);
  const ready=sources.length>0&&sources.every(s=>s.state==='HEALTHY');
  return reply.code(ready?200:503).send({ready,database:store.db.kind,sourceHealth:sources});
 });
 const shelterQuery=z.object({regionId:z.string().refine(v=>v==='PL'||v in REGIONS).default('PL'),q:z.string().trim().max(120).default(''),limit:z.coerce.number().int().min(1).max(500).default(50),offset:z.coerce.number().int().min(0).max(500000).default(0),version:z.string().regex(/^[a-f0-9]{64}$/).optional()});
 const sheltersResponse=async(query:z.infer<typeof shelterQuery>,bbox?:[number,number,number,number])=>{
  const result=await store.shelterPage({...query,bbox});
  return {schemaVersion:1,serverTime:new Date().toISOString(),...result,health:result.health?sourceHealth([result.health])[0]:null};
 };
 app.get('/v1/shelters',async req=>sheltersResponse(shelterQuery.parse(req.query)));
 app.get('/v1/shelters/nearest',async req=>{
  const q=z.object({lat:z.coerce.number().min(-90).max(90),lon:z.coerce.number().min(-180).max(180),limit:z.coerce.number().int().min(1).max(10).default(3)}).parse(req.query);
  const items=await store.nearestShelters(q.lat,q.lon,q.limit);
  const health=(await store.health()).find(h=>h.id==='SHELTERS');
  return {schemaVersion:1,serverTime:new Date().toISOString(),query:{latitude:q.lat,longitude:q.lon},items,health:health?sourceHealth([health])[0]:null};
 });
 app.get('/v1/layers/shelters.geojson',async(req,reply)=>{
  const raw=z.object({bbox:z.string().optional()}).parse(req.query).bbox;
  const bbox=raw===undefined?undefined:z.tuple([z.number().min(-180).max(180),z.number().min(-90).max(90),z.number().min(-180).max(180),z.number().min(-90).max(90)]).refine(b=>b[0]<=b[2]&&b[1]<=b[3]).parse(raw.split(',').map(Number));
  if(bbox&&store.db.kind!=='postgres')return reply.code(503).send({error:'POSTGIS_REQUIRED'});
  const result=await sheltersResponse(shelterQuery.parse(req.query),bbox),{items,...metadata}=result;
  return {type:'FeatureCollection',metadata,features:items.map(s=>({type:'Feature',id:s.id,geometry:{type:'Point',coordinates:[s.longitude,s.latitude]},properties:s}))};
 });
 app.get('/v1/snapshot',async req=>{
  const {regionId}=regionQuery.parse(req.query),{events,health,incidents,radiationMeasurements}=await store.snapshot(),now=new Date();
  const sources=sourceHealth(health,now);
  const shelterPage=await sheltersResponse(shelterQuery.parse({regionId}));
  return {schemaVersion:1,serverTime:now.toISOString(),releaseStage:'ALPHA',regionId,radiation:radiationStatus(events,health,regionId,now,radiationMeasurements),incidents:incidents.filter(i=>i.relatedEventIds.some(id=>events.some(e=>e.id===id&&(regionId==='PL'||e.regions.includes(regionId))))).map(i=>({...i,reports:events.filter(e=>i.relatedEventIds.includes(e.id))})),status:computeStatus(events,health,regionId,now,incidents),nationalStatus:computeStatus(events,health,'PL',now,incidents),events:events.filter(e=>!e.securityLevel&&(regionId==='PL'||!e.regions.length||e.regions.includes('PL')||e.regions.includes(regionId))),sources,sourceHealth:sources,shelters:shelterPage.items,shelterPage,...securityLevelStatus(events,health,regionId,now),nationalSecurityLevels:securityLevelStatus(events,health,'PL',now).securityLevels,ukraineAlerts:[],capabilities:{push:false,shelters:shelterPage.version!==null,ukraine:false,liveMap:store.db.kind==='postgres',rcb:true,rso:true,wczk:true,correlation:true,paa:true,paaMeasurements:false,cert:true,csirtGov:false,sg:true,police:true,pspIncidents:true,around:true,watchedLocations:true}};
 });
 app.get('/v1/layers/events.geojson',async(req,reply)=>{
  const {regionId}=regionQuery.parse(req.query);
  const {bbox:raw,source}=z.object({bbox:z.string().optional(),source:z.enum(['ALL','RCB','RSO','WCZK','PAA','SG','POLICE','PSP_INCIDENTS']).default('ALL')}).parse(req.query);
  const bbox=raw===undefined?undefined:z.tuple([z.number().min(-180).max(180),z.number().min(-90).max(90),z.number().min(-180).max(180),z.number().min(-90).max(90)]).refine(b=>b[0]<=b[2]&&b[1]<=b[3]).parse(raw.split(',').map(Number));
  if(bbox&&store.db.kind!=='postgres')return reply.code(503).send({error:'POSTGIS_REQUIRED'});
  const rows=(await store.spatialEvents(bbox)).filter(e=>!e.isDemo&&(source==='ALL'||e.sources.some(s=>source==='WCZK'?s.id.startsWith('WCZK-'):s.id===source))&&(regionId==='PL'||!e.regions.length||e.regions.includes('PL')||e.regions.includes(regionId)));
  return {type:'FeatureCollection',features:rows.map(e=>({type:'Feature',id:e.id,geometry:e.geometry,properties:{title:e.title,eventType:e.eventType,severity:e.severity,lifecycle:e.lifecycle,messageContext:e.messageContext,validTo:e.validTo,publicationDate:e.publicationDate,sourceUrl:e.sources[0].url,sourceIds:e.sources.map(s=>s.id),layerId:e.sources.some(s=>s.id==='PAA')?'radiation':e.sources.some(s=>s.id==='SG')?'border':e.sources.some(s=>s.id==='POLICE'||s.id==='PSP_INCIDENTS')?'service_incidents':e.sources.some(s=>s.id.startsWith('WCZK-'))?'WCZK':'events',areaPrecision:e.areaPrecision}}))};
 });
 app.get('/v1/incidents/:id/timeline',async req=>store.incidentTimeline(z.object({id:z.string().regex(/^INC-[a-f0-9]{24}$/)}).parse(req.params).id));
 app.get('/v1/incidents/:id/history',async req=>store.incidentHistory(z.object({id:z.string().regex(/^INC-[a-f0-9]{24}$/)}).parse(req.params).id));
 app.get('/v1/events/:id/timeline',async req=>store.timeline(z.object({id:z.string().max(150)}).parse(req.params).id));
 const auth=(actual:string|undefined)=>{const a=Buffer.from(actual??''),b=Buffer.from(`Bearer ${adminToken??''}`);return !!adminToken&&adminToken.length>=32&&a.length===b.length&&timingSafeEqual(a,b);};
 app.post('/admin/events',async(req,r)=>{if(!auth(req.headers.authorization))return r.code(401).send({error:'UNAUTHORIZED'});const b=z.object({event:eventSchema,expectedRevision:z.number().int().nonnegative(),reason:z.string().min(10).max(1000)}).parse(req.body);await store.put({...b.event,reviewed:true},'operator',b.reason,b.expectedRevision);return {ok:true};});
 let running=false;app.post('/admin/ingest',async(req,r)=>{if(!auth(req.headers.authorization))return r.code(401).send({error:'UNAUTHORIZED'});if(running)return r.code(409).send({error:'INGEST_RUNNING'});running=true;try{await ingest(store);return {ok:true};}finally{running=false;}});
 await initializeSources(store);return app;
}

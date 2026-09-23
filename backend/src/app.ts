import {ukraineSnapshot,isUa} from './ukraine.js';
import {neptunSnapshot,neptunTrackSchema} from './neptun.js';
import {bearerSecret,pushDeviceIdSchema,pushPreferencesSchema,pushRegisterSchema,pushUpdateSchema,type PushService} from './push.js';
import {aroundLocation,aroundQuerySchema} from './around.js';
import {radiationStatus} from './radiation.js';
import {mapLayers,mapQuery,shelterViewport} from './map-layers.js';
import {securityLevelStatus} from './security-level.js';
import Fastify from 'fastify';import rateLimit from '@fastify/rate-limit';import {timingSafeEqual} from 'node:crypto';import {z} from 'zod';
import {APP_VERSION,type AppEnv} from './config.js';
import {assertSchema} from './migrate.js';
import {computeStatus,eventSchema,REGIONS,sourceHealth} from './domain.js';import {Store} from './store.js';import {initializeSources,ingest} from './adapters.js';
export async function buildApp(store:Store,adminToken?:string,push?:PushService,config:{stage?:AppEnv;buildSha?:string;trustProxy?:boolean}={}){
 const production=config.stage==='production';
 const app=Fastify({logger:production?{redact:{paths:['req.headers.authorization','req.headers.cookie','*.token','*.secret'],censor:'[redacted]'}}:false,disableRequestLogging:true,trustProxy:config.trustProxy??false,bodyLimit:128*1024,requestTimeout:30000,connectionTimeout:10000,keepAliveTimeout:5000});
 await app.register(rateLimit,{max:600,timeWindow:'1 minute'});
 const metrics=new Map<string,{count:number;errors:number;totalMs:number;maxMs:number}>();
 app.addHook('onResponse',async(req,r)=>{
  const route=req.routeOptions.url??'unmatched',key=req.method+' '+route,ms=r.elapsedTime;
  const item=metrics.get(key)??{count:0,errors:0,totalMs:0,maxMs:0};item.count++;item.errors+=Number(r.statusCode>=500);item.totalMs+=ms;item.maxMs=Math.max(item.maxMs,ms);metrics.set(key,item);
  if(production)req.log.info({component:'api',requestId:req.id,route,status:r.statusCode,durationMs:Math.round(ms)},'request complete');
 });
 app.addHook('onSend',async(req,r,p)=>{r.header('Cache-Control','no-store').header('X-Content-Type-Options','nosniff').header('X-Frame-Options','DENY').header('Referrer-Policy','no-referrer').header('X-Request-ID',String(req.id));if(production)r.header('Strict-Transport-Security','max-age=31536000; includeSubDomains');return p;});
 app.setErrorHandler((e,req,r)=>{if(e instanceof z.ZodError)return r.code(400).send({error:'INVALID_REQUEST'});if(e instanceof Error&&['REVISION_CONFLICT','SHELTER_VERSION_CHANGED'].includes(e.message))return r.code(409).send({error:e.message});const status=typeof e==='object'&&e&&'statusCode'in e?Number(e.statusCode):500;if(status>=500)req.log.error({component:'api',requestId:req.id,errorCode:'REQUEST_FAILED'},'request failed');return r.code(status>=400&&status<600?status:500).send({error:'REQUEST_FAILED'});});
 const health=async()=>({ok:true,version:APP_VERSION,buildSha:config.buildSha??'unknown',environment:config.stage??'development'});
 app.get('/health',health);app.get('/healthz',health);
 const regionQuery=z.object({regionId:z.string().refine(v=>v==='PL'||v in REGIONS).default('PL')});
 app.get('/status',async req=>{
  const {regionId}=regionQuery.parse(req.query),{events,health,incidents,radiationMeasurements}=await store.snapshot(),now=new Date();
  return {schemaVersion:1,evaluatedAt:now.toISOString(),radiation:radiationStatus(events,health,regionId,now,radiationMeasurements),...securityLevelStatus(events,health,regionId,now),poland:{...computeStatus(events,health,'PL',now,incidents),...securityLevelStatus(events,health,'PL',now)},region:{id:regionId,name:REGIONS[regionId]??'Cała Polska',...computeStatus(events,health,regionId,now,incidents),...securityLevelStatus(events,health,regionId,now)},sourceHealth:sourceHealth(health,now)};
 });
 app.get('/v1/map/layers',async()=>({schemaVersion:1,layers:mapLayers}));
 app.get('/v1/map/shelters',async(req,reply)=>{const q=mapQuery.parse(req.query);if(store.db.kind!=='postgres')return reply.code(503).send({error:'POSTGIS_REQUIRED'});return shelterViewport(store,q);});
 app.get('/v1/radiation',async req=>{const {regionId}=regionQuery.parse(req.query),s=await store.snapshot();return radiationStatus(s.events,s.health,regionId,new Date(),s.radiationMeasurements);});
 app.get('/v1/ukraine',async()=>ukraineSnapshot(store));
 app.get('/v1/layers/ukraine.geojson',async()=>{const s=await ukraineSnapshot(store);return {...s.map,metadata:{coverage:s.coverage,sourceHealth:s.sourceHealth,validUntil:s.validUntil}};});
 app.get('/v1/neptun',async()=>neptunSnapshot(store));
 app.get('/v1/layers/neptun.geojson',async()=>{const s=await neptunSnapshot(store);return {...s.map,metadata:{mode:s.mode,coverage:s.coverage,safetyDelayHours:s.safetyDelayHours,minimumPublishedPrecisionKm:s.minimumPublishedPrecisionKm,sourceHealth:s.sourceHealth}};});
 app.get('/v1/neptun/:id/timeline',async req=>store.neptunTimeline(z.object({id:z.string().regex(/^NEPTUN-[A-Za-z0-9._:-]{1,120}$/)}).parse(req.params).id));
 app.get('/v1/sources',async()=>({sourceHealth:sourceHealth(await store.health())}));
 const pushUnavailable=(r:any)=>r.code(503).send({error:'PUSH_NOT_CONFIGURED'});
 const pushRoute={bodyLimit:16*1024,config:{rateLimit:{max:10,timeWindow:'1 minute'}}};
 app.post('/v1/push/devices',pushRoute,async(req,r)=>{
  if(!push)return pushUnavailable(r);
  return push.register(pushRegisterSchema.parse(req.body),bearerSecret(req.headers.authorization));
 });
 app.put('/v1/push/devices/:id',pushRoute,async(req,r)=>{
  if(!push)return pushUnavailable(r);
  const {id}=z.object({id:pushDeviceIdSchema}).parse(req.params);
  return push.update(id,pushUpdateSchema.parse(req.body),bearerSecret(req.headers.authorization));
 });
 app.put('/v1/push/devices/:id/preferences',pushRoute,async(req,r)=>{
  if(!push)return pushUnavailable(r);
  const {id}=z.object({id:pushDeviceIdSchema}).parse(req.params);
  return push.preferences(id,pushPreferencesSchema.parse(req.body),bearerSecret(req.headers.authorization));
 });
 app.get('/v1/push/devices/:id',async(req,r)=>{
  if(!push)return pushUnavailable(r);
  const {id}=z.object({id:pushDeviceIdSchema}).parse(req.params);
  return push.status(id,bearerSecret(req.headers.authorization));
 });
 app.delete('/v1/push/devices/:id',async(req,r)=>{
  if(!push)return pushUnavailable(r);
  const {id}=z.object({id:pushDeviceIdSchema}).parse(req.params);
  return push.unregister(id,bearerSecret(req.headers.authorization));
 });
 app.post('/v1/around',{config:{rateLimit:{max:120,timeWindow:'1 minute'}}},async(req,reply)=>{
  const q=aroundQuerySchema.parse(req.body);
  if(store.db.kind!=='postgres')return reply.code(503).send({error:'POSTGIS_REQUIRED'});
  return aroundLocation(store,q,new Date());
 });
 const ready=async(_:unknown,reply:any)=>{
  try{await store.db.all('SELECT 1 AS ok');if(production&&store.db.kind!=='postgres')throw new Error('POSTGIS_REQUIRED');
   if(production)await assertSchema(store.db);
   else if(store.db.kind==='postgres'&&!(await store.db.all("SELECT extname FROM pg_extension WHERE extname='postgis'")).length)throw new Error('POSTGIS_REQUIRED');
   return reply.send({ready:true,database:store.db.kind,postgis:store.db.kind==='postgres'});
  }catch{return reply.code(503).send({ready:false,error:'DATABASE_UNAVAILABLE'});}
 };
 app.get('/ready',ready);
 // Legacy readiness contract used by existing preview checks; production probes use /ready.
 app.get('/readyz',async(_,reply)=>{
  try{
   await store.db.all('SELECT 1 AS ok');
   const sources=sourceHealth(await store.health()).filter(s=>s.enabled);
   const synchronized=sources.length>0&&sources.every(s=>s.state==='HEALTHY');
   return reply.code(synchronized?200:503).send({ready:synchronized,database:store.db.kind,sourceHealth:sources});
  }catch{return reply.code(503).send({ready:false,error:'DATABASE_UNAVAILABLE'});}
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
  return {schemaVersion:1,serverTime:now.toISOString(),releaseStage:'ALPHA',regionId,radiation:radiationStatus(events,health,regionId,now,radiationMeasurements),incidents:incidents.filter(i=>i.relatedEventIds.some(id=>events.some(e=>e.id===id&&(regionId==='PL'||e.regions.includes(regionId))))).map(i=>({...i,reports:events.filter(e=>i.relatedEventIds.includes(e.id))})),status:computeStatus(events,health,regionId,now,incidents),nationalStatus:computeStatus(events,health,'PL',now,incidents),events:events.filter(e=>!isUa(e)&&!e.securityLevel&&(regionId==='PL'||!e.regions.length||e.regions.includes('PL')||e.regions.includes(regionId))),sources,sourceHealth:sources,shelters:shelterPage.items,shelterPage,...securityLevelStatus(events,health,regionId,now),nationalSecurityLevels:securityLevelStatus(events,health,'PL',now).securityLevels,ukraineAlerts:[],capabilities:{push:!!push&&push.providerReadyAny,pushProviders:{android:push?.providerReady('ANDROID')??false,ios:push?.providerReady('IOS')??false},shelters:shelterPage.version!==null,ukraine:true,neptun:true,liveMap:store.db.kind==='postgres',rcb:true,rso:true,wczk:true,imgwMeteo:true,imgwHydro:true,correlation:true,paa:true,paaMeasurements:false,cert:true,csirtGov:false,sg:true,police:true,pspIncidents:true,around:true,watchedLocations:true}};
 });
 app.get('/v1/layers/events.geojson',async(req,reply)=>{
  const {regionId}=regionQuery.parse(req.query);
  const {bbox:raw,source}=z.object({bbox:z.string().optional(),source:z.enum(['ALL','RCB','RSO','WCZK','IMGW_METEO','IMGW_HYDRO','PAA','SG','POLICE','PSP_INCIDENTS']).default('ALL')}).parse(req.query);
  const bbox=raw===undefined?undefined:z.tuple([z.number().min(-180).max(180),z.number().min(-90).max(90),z.number().min(-180).max(180),z.number().min(-90).max(90)]).refine(b=>b[0]<=b[2]&&b[1]<=b[3]).parse(raw.split(',').map(Number));
  if(bbox&&store.db.kind!=='postgres')return reply.code(503).send({error:'POSTGIS_REQUIRED'});
  const rows=(await store.spatialEvents(bbox)).filter(e=>!isUa(e)&&!e.isDemo&&(source==='ALL'||e.sources.some(s=>source==='WCZK'?s.id.startsWith('WCZK-'):s.id===source))&&(regionId==='PL'||!e.regions.length||e.regions.includes('PL')||e.regions.includes(regionId)));
  return {type:'FeatureCollection',features:rows.map(e=>({type:'Feature',id:e.id,geometry:e.geometry,properties:{title:e.title,eventType:e.eventType,severity:e.severity,lifecycle:e.lifecycle,messageContext:e.messageContext,validTo:e.validTo,publicationDate:e.publicationDate,sourceUrl:e.sources[0].url,sourceIds:e.sources.map(s=>s.id),layerId:e.sources.some(s=>s.id==='PAA')?'radiation':e.sources.some(s=>s.id==='SG')?'border':e.sources.some(s=>s.id==='POLICE'||s.id==='PSP_INCIDENTS')?'service_incidents':e.sources.some(s=>s.id.startsWith('WCZK-'))?'WCZK':'events',areaPrecision:e.areaPrecision}}))};
 });
 app.get('/v1/incidents/:id/timeline',async req=>store.incidentTimeline(z.object({id:z.string().regex(/^INC-[a-f0-9]{24}$/)}).parse(req.params).id));
 app.get('/v1/incidents/:id/history',async req=>store.incidentHistory(z.object({id:z.string().regex(/^INC-[a-f0-9]{24}$/)}).parse(req.params).id));
 app.get('/v1/events/:id/timeline',async req=>store.timeline(z.object({id:z.string().max(150)}).parse(req.params).id));
 const auth=(actual:string|undefined)=>{const a=Buffer.from(actual??''),b=Buffer.from(`Bearer ${adminToken??''}`);return !!adminToken&&adminToken.length>=32&&a.length===b.length&&timingSafeEqual(a,b);};
 const adminRoute={config:{rateLimit:{max:10,timeWindow:'1 minute'}}};
 app.get('/admin/metrics',adminRoute,async(req,r)=>{if(!auth(req.headers.authorization))return r.code(401).send({error:'UNAUTHORIZED'});return {version:APP_VERSION,requests:Object.fromEntries(metrics),sources:sourceHealth(await store.health()).map(s=>({id:s.id,state:s.state,lastSuccessfulSyncAt:s.lastSuccessfulSyncAt,errorCode:s.errorCode}))};});
 app.post('/admin/events',adminRoute,async(req,r)=>{if(!auth(req.headers.authorization))return r.code(401).send({error:'UNAUTHORIZED'});const b=z.object({event:eventSchema,expectedRevision:z.number().int().nonnegative(),reason:z.string().min(10).max(1000)}).parse(req.body);await store.put({...b.event,reviewed:true},'operator',b.reason,b.expectedRevision);return {ok:true};});
 app.post('/admin/neptun',adminRoute,async(req,r)=>{if(!auth(req.headers.authorization))return r.code(401).send({error:'UNAUTHORIZED'});const b=z.object({track:neptunTrackSchema,expectedRevision:z.number().int().nonnegative(),reason:z.string().min(10).max(1000)}).parse(req.body);await store.putNeptunTrack({...b.track,reviewed:true},'operator',b.reason,b.expectedRevision);return {ok:true};});
 let running=false;app.post('/admin/ingest',adminRoute,async(req,r)=>{if(!auth(req.headers.authorization))return r.code(401).send({error:'UNAUTHORIZED'});if(running)return r.code(409).send({error:'INGEST_RUNNING'});running=true;try{await ingest(store);return {ok:true};}finally{running=false;}});
 await initializeSources(store);return app;
}

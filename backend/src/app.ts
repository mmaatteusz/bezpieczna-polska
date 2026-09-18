import Fastify from 'fastify';import rateLimit from '@fastify/rate-limit';import {timingSafeEqual} from 'node:crypto';import {z} from 'zod';
import {computeStatus,eventSchema,REGIONS} from './domain.js';import {Store} from './store.js';import {initializeSources,ingest} from './adapters.js';
export async function buildApp(store:Store,adminToken?:string){
 const app=Fastify({logger:false,bodyLimit:128*1024});await app.register(rateLimit,{max:100,timeWindow:'1 minute'});
 app.addHook('onSend',async(_,r,p)=>{r.header('Cache-Control','no-store').header('X-Content-Type-Options','nosniff');return p;});
 app.setErrorHandler((e,_,r)=>{if(e instanceof z.ZodError)return r.code(400).send({error:'INVALID_REQUEST'});if(e instanceof Error&&e.message==='REVISION_CONFLICT')return r.code(409).send({error:'REVISION_CONFLICT'});const status=typeof e==='object'&&e&&'statusCode'in e?Number(e.statusCode):500;return r.code(status>=400&&status<600?status:500).send({error:'REQUEST_FAILED'});});
 app.get('/healthz',async()=>({ok:true,version:'0.1.0-alpha.2'}));
 app.get('/v1/snapshot',async req=>{const {regionId}=z.object({regionId:z.string().refine(v=>v==='PL'||v in REGIONS).default('PL')}).parse(req.query);const events=await store.events(),health=await store.health();return {schemaVersion:1,serverTime:new Date().toISOString(),releaseStage:'ALPHA',regionId,status:computeStatus(events,health,regionId),nationalStatus:computeStatus(events,health,'PL'),events:events.filter(e=>regionId==='PL'||!e.regions.length||e.regions.includes('PL')||e.regions.includes(regionId)),sources:health,shelters:[],securityLevels:[],ukraineAlerts:[],capabilities:{push:false,shelters:false,ukraine:false,liveMap:false}};});
 app.get('/v1/events/:id/timeline',async req=>store.timeline(z.object({id:z.string().max(150)}).parse(req.params).id));
 const auth=(actual:string|undefined)=>{const a=Buffer.from(actual??''),b=Buffer.from(`Bearer ${adminToken??''}`);return !!adminToken&&adminToken.length>=32&&a.length===b.length&&timingSafeEqual(a,b);};
 app.post('/admin/events',async(req,r)=>{if(!auth(req.headers.authorization))return r.code(401).send({error:'UNAUTHORIZED'});const b=z.object({event:eventSchema,expectedRevision:z.number().int().nonnegative(),reason:z.string().min(10).max(1000)}).parse(req.body);await store.put({...b.event,reviewed:true},'operator',b.reason,b.expectedRevision);return {ok:true};});
 let running=false;app.post('/admin/ingest',async(req,r)=>{if(!auth(req.headers.authorization))return r.code(401).send({error:'UNAUTHORIZED'});if(running)return r.code(409).send({error:'INGEST_RUNNING'});running=true;try{await ingest(store);return {ok:true};}finally{running=false;}});
 await initializeSources(store);return app;
}

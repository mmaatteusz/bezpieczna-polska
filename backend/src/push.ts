import {connect as connectHttp2} from 'node:http2';
import {createCipheriv,createDecipheriv,createHash,createSign,randomBytes,sign as cryptoSign,timingSafeEqual} from 'node:crypto';
import {z} from 'zod';
import {REGIONS,type Event} from './domain.js';
import type {Incident} from './correlation.js';

type Row=Record<string,unknown>;
export interface PushDb{
 kind:'postgres'|'sqlite';
 all(sql:string,params?:unknown[]):Promise<Row[]>;
 run(sql:string,params?:unknown[]):Promise<void>;
 transaction<T>(work:(db:PushDb)=>Promise<T>):Promise<T>;
}

export const pushPlatformSchema=z.enum(['ANDROID','IOS']);
export type PushPlatform=z.infer<typeof pushPlatformSchema>;
export const pushCategorySchema=z.enum(['CRITICAL_PL','REGION_PL','WATCHED_LOCATIONS','CYBER','BORDER','UKRAINE']);
export type PushCategory=z.infer<typeof pushCategorySchema>;

const regionIdSchema=z.string().refine(v=>v==='PL'||v in REGIONS,'Unknown region');
const watchedLocationSchema=z.object({
 id:z.string().min(1).max(80),
 label:z.string().trim().min(1).max(120),
 latitude:z.number().min(-90).max(90),
 longitude:z.number().min(-180).max(180),
 radiusKm:z.number().min(1).max(100),
 regionId:regionIdSchema.nullable().optional(),
}).strict();

export const pushPreferencesSchema=z.object({
 criticalPoland:z.boolean().default(true),
 regionAlerts:z.boolean().default(true),
 watchedLocations:z.boolean().default(true),
 cyber:z.boolean().default(true),
 border:z.boolean().default(true),
 ukraine:z.boolean().default(false),
 regionId:regionIdSchema.nullable().default(null),
 locations:z.array(watchedLocationSchema).max(20).default([]),
}).strict();
export type PushPreferences=z.infer<typeof pushPreferencesSchema>;

const installationIdSchema=z.string().regex(/^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i);
const authSecretSchema=z.string().regex(/^bp_push_[A-Za-z0-9_-]{43}$/);
const languageSchema=z.string().regex(/^[A-Za-z]{2,3}(?:-[A-Za-z0-9]{2,8})?$/).max(16).nullable().default(null);
const commonDeviceSchema=z.object({
 platform:pushPlatformSchema,
 token:z.string().min(20).max(4096),
 appVersion:z.string().trim().min(1).max(80),
 language:languageSchema,
 preferences:pushPreferencesSchema,
}).strict().superRefine((v,ctx)=>{
 if(v.platform==='IOS'&&!/^[A-Fa-f0-9]{64}$/.test(v.token))ctx.addIssue({code:'custom',path:['token'],message:'Invalid APNs token'});
 if(v.platform==='ANDROID'&&!/^[A-Za-z0-9_:\-]{20,4096}$/.test(v.token))ctx.addIssue({code:'custom',path:['token'],message:'Invalid FCM token'});
});
export const pushRegisterSchema=z.object({
 installationId:installationIdSchema,
 platform:pushPlatformSchema,
 token:z.string().min(20).max(4096),
 appVersion:z.string().trim().min(1).max(80),
 language:languageSchema,
 preferences:pushPreferencesSchema,
}).strict().superRefine((v,ctx)=>{
 if(v.platform==='IOS'&&!/^[A-Fa-f0-9]{64}$/.test(v.token))ctx.addIssue({code:'custom',path:['token'],message:'Invalid APNs token'});
 if(v.platform==='ANDROID'&&!/^[A-Za-z0-9_:\-]{20,4096}$/.test(v.token))ctx.addIssue({code:'custom',path:['token'],message:'Invalid FCM token'});
});
export const pushUpdateSchema=commonDeviceSchema;
export const pushDeviceIdSchema=installationIdSchema;
export const pushAuthSecretSchema=authSecretSchema;

export type PushEventChange={previous:Event|null;current:Event};

export type PushMessage={
 title:string;
 body:string;
 data:Record<string,string>;
 collapseKey:string;
};

export type PushSendResult={
 kind:'SUCCESS'|'RETRY'|'PERMANENT_FAILURE';
 code:string;
 invalidToken?:boolean;
};

export interface PushProvider{
 ready(platform:PushPlatform):boolean;
 send(platform:PushPlatform,token:string,message:PushMessage):Promise<PushSendResult>;
}

const sha=(value:string)=>createHash('sha256').update(value).digest('hex');
const b64url=(value:Buffer|string)=>Buffer.from(value).toString('base64url');
const safeError=(code:string)=>code.replace(/[^A-Z0-9_:\-.]/gi,'_').slice(0,120);

export function parsePushEncryptionKey(value:string|undefined):Buffer|null{
 if(!value)return null;
 let key:Buffer;
 if(/^[a-f0-9]{64}$/i.test(value))key=Buffer.from(value,'hex');
 else{
  try{key=Buffer.from(value,'base64');}catch{return null;}
 }
 return key.length===32?key:null;
}
function encryptToken(key:Buffer,token:string){
 const iv=randomBytes(12),cipher=createCipheriv('aes-256-gcm',key,iv),data=Buffer.concat([cipher.update(token,'utf8'),cipher.final()]),tag=cipher.getAuthTag();
 return ['v1',iv.toString('base64url'),data.toString('base64url'),tag.toString('base64url')].join('.');
}
function decryptToken(key:Buffer,value:string){
 const parts=value.split('.');
 if(parts.length!==4||parts[0]!=='v1')throw new Error('TOKEN_DECRYPT_FAILED');
 const iv=Buffer.from(parts[1],'base64url'),data=Buffer.from(parts[2],'base64url'),tag=Buffer.from(parts[3],'base64url');
 const cipher=createDecipheriv('aes-256-gcm',key,iv);cipher.setAuthTag(tag);
 return Buffer.concat([cipher.update(data),cipher.final()]).toString('utf8');
}
function secretHash(secret:string){return sha('manage:'+secret);}
function tokenHash(platform:PushPlatform,token:string){return sha(platform+':'+token);}
function secretOk(actual:string,expectedHash:string){
 const a=Buffer.from(secretHash(actual),'hex'),b=Buffer.from(expectedHash,'hex');
 return a.length===b.length&&timingSafeEqual(a,b);
}

export async function initPushStore(db:PushDb){
 await db.run(`CREATE TABLE IF NOT EXISTS push_devices(
  device_id TEXT PRIMARY KEY,
  platform TEXT NOT NULL,
  token_ciphertext TEXT NOT NULL,
  token_hash TEXT NOT NULL UNIQUE,
  manage_secret_hash TEXT NOT NULL,
  app_version TEXT NOT NULL,
  language TEXT,
  preferences TEXT NOT NULL,
  enabled INTEGER NOT NULL,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  last_seen_at TEXT NOT NULL,
  disabled_at TEXT,
  disabled_reason TEXT
 )`);
 await db.run('CREATE INDEX IF NOT EXISTS push_devices_enabled_idx ON push_devices(enabled,last_seen_at)');
 await db.run(`CREATE TABLE IF NOT EXISTS push_outbox(
  id TEXT PRIMARY KEY,
  dedupe_key TEXT NOT NULL UNIQUE,
  device_id TEXT NOT NULL,
  entity_id TEXT NOT NULL,
  event_id TEXT NOT NULL,
  event_revision INTEGER NOT NULL,
  category TEXT NOT NULL,
  notification_kind TEXT NOT NULL,
  payload TEXT NOT NULL,
  state TEXT NOT NULL,
  attempt_count INTEGER NOT NULL,
  next_attempt_at TEXT NOT NULL,
  last_attempt_at TEXT,
  last_error_code TEXT,
  created_at TEXT NOT NULL,
  delivered_at TEXT
 )`);
 await db.run('CREATE INDEX IF NOT EXISTS push_outbox_due_idx ON push_outbox(state,next_attempt_at,created_at)');
}

type StoredDevice={
 deviceId:string;
 platform:PushPlatform;
 preferences:PushPreferences;
 enabled:boolean;
};

function parseDevice(row:Row):StoredDevice{
 return {
  deviceId:String(row.device_id),
  platform:pushPlatformSchema.parse(row.platform),
  preferences:pushPreferencesSchema.parse(JSON.parse(String(row.preferences))),
  enabled:Number(row.enabled)===1,
 };
}

function relevantChange(previous:Event|null,current:Event){
 if(current.isDemo||current.messageContext!=='ACTUAL'||current.verification!=='CONFIRMED')return null;
 if(current.securityLevel)return null;
 const sourceIds=new Set(current.sources.map(s=>s.id));
 const isUa=current.countryCode==='UA'||!!current.ukraine||sourceIds.has('UA');
 const isCyber=current.eventType==='CYBER'||sourceIds.has('CERT')||sourceIds.has('CSIRT_GOV');
 const isBorder=current.eventType==='BORDER'||sourceIds.has('SG');
 const standaloneCategory=isCyber||isBorder;
 if(isUa){
  if(current.ukraine?.kind!=='OFFICIAL_ALERT'||!current.sources.some(s=>s.tier===1))return null;
 }else{
  if(!current.sources.some(s=>s.tier===1))return null;
  if(sourceIds.has('POLICE')||sourceIds.has('PSP_INCIDENTS'))return null;
  if(!standaloneCategory&&!current.officialWarning)return null;
  // Separate informational categories stay outside Status Polski, but still
  // need a meaningful threshold so an RSS refresh does not become notification spam.
  if(isCyber&&current.severity==='INFORMATIONAL')return null;
  if(isBorder&&current.severity==='INFORMATIONAL'&&!['ENDED','CANCELLED','EXPIRED'].includes(current.lifecycle))return null;
 }
 const ended=['ENDED','CANCELLED','EXPIRED'].includes(current.lifecycle);
 if(!previous){
  if(ended&&standaloneCategory)return {kind:'ENDED' as const,isUa};
  if(!standaloneCategory&&!['ACTIVE','SCHEDULED'].includes(current.lifecycle))return null;
  return {kind:'NEW' as const,isUa};
 }
 if(ended&&!['ENDED','CANCELLED','EXPIRED'].includes(previous.lifecycle))return {kind:'ENDED' as const,isUa};
 if(!standaloneCategory&&!['ACTIVE','SCHEDULED'].includes(current.lifecycle))return null;
 const rank:Record<Event['severity'],number>={INFORMATIONAL:0,NORMAL:1,HIGH:2,CRITICAL:3};
 if(rank[current.severity]>rank[previous.severity])return {kind:'ESCALATED' as const,isUa};
 if(previous.lifecycle!==current.lifecycle&&current.lifecycle==='ACTIVE')return {kind:'ACTIVATED' as const,isUa};
 const fields:(keyof Event)[]=['title','description','severity','validFrom','validTo','instructions','correction','regions','geographicScope'];
 if(fields.some(k=>JSON.stringify(previous[k])!==JSON.stringify(current[k])))return {kind:'CORRECTED' as const,isUa};
 return null;
}

function pointInRing(lon:number,lat:number,ring:[number,number][]){
 let inside=false;
 for(let i=0,j=ring.length-1;i<ring.length;j=i++){
  const [xi,yi]=ring[i],[xj,yj]=ring[j];
  const crosses=((yi>lat)!==(yj>lat))&&(lon<(xj-xi)*(lat-yi)/(yj-yi||Number.EPSILON)+xi);
  if(crosses)inside=!inside;
 }
 return inside;
}
function polygonContains(lon:number,lat:number,rings:[number,number][][]){
 if(!rings.length||!pointInRing(lon,lat,rings[0]))return false;
 return !rings.slice(1).some(ring=>pointInRing(lon,lat,ring));
}
function pointInGeometry(lon:number,lat:number,geometry:Event['geometry']){
 if(!geometry)return false;
 if(geometry.type==='Point')return geometry.coordinates[0]===lon&&geometry.coordinates[1]===lat;
 if(geometry.type==='Polygon')return polygonContains(lon,lat,geometry.coordinates);
 return geometry.coordinates.some(poly=>polygonContains(lon,lat,poly));
}
function distanceMeters(lat1:number,lon1:number,lat2:number,lon2:number){
 const rad=(v:number)=>v*Math.PI/180,dLat=rad(lat2-lat1),dLon=rad(lon2-lon1);
 const a=Math.sin(dLat/2)**2+Math.cos(rad(lat1))*Math.cos(rad(lat2))*Math.sin(dLon/2)**2;
 return 6371008.8*2*Math.atan2(Math.sqrt(a),Math.sqrt(1-a));
}
function locationMatches(e:Event,p:PushPreferences){
 return p.locations.some(l=>{
  if(e.geometry?.type==='Point'){
   const [lon,lat]=e.geometry.coordinates;
   return distanceMeters(l.latitude,l.longitude,lat,lon)<=l.radiusKm*1000;
  }
  if(e.geometry)return pointInGeometry(l.longitude,l.latitude,e.geometry);
  return !!l.regionId&&e.regions.includes(l.regionId);
 });
}
function selectCategory(e:Event,p:PushPreferences,isUa:boolean):PushCategory|null{
 if(isUa)return p.ukraine?'UKRAINE':null;
 const sourceIds=new Set(e.sources.map(s=>s.id));
 if((e.eventType==='CYBER'||sourceIds.has('CERT')||sourceIds.has('CSIRT_GOV'))&&p.cyber)return 'CYBER';
 if((e.eventType==='BORDER'||sourceIds.has('SG'))&&p.border)return 'BORDER';
 if(e.severity==='CRITICAL'&&p.criticalPoland)return 'CRITICAL_PL';
 if(p.regionAlerts&&p.regionId&&e.regions.includes(p.regionId))return 'REGION_PL';
 if(p.watchedLocations&&locationMatches(e,p))return 'WATCHED_LOCATIONS';
 return null;
}
function messageFor(e:Event,kind:string,category:PushCategory,entityId:string):PushMessage{
 const prefix=kind==='ENDED'?'Zakończenie':kind==='CORRECTED'?'Korekta':kind==='ESCALATED'?'Eskalacja':kind==='ACTIVATED'?'Aktywny alert':'Nowy alert';
 const body=(e.correction?.trim()||e.description.trim()||e.title).replace(/\s+/g,' ').slice(0,300);
 return {
  title:(prefix+': '+e.title).slice(0,160),
  body,
  collapseKey:entityId.slice(0,80),
  data:{schemaVersion:'1',eventId:e.id,category,kind},
 };
}

export async function queuePushChanges(db:PushDb,changes:PushEventChange[],events:Event[],incidents:Incident[],now=new Date()){
 if(!changes.length)return 0;
 const deviceRows=await db.all('SELECT device_id,platform,preferences,enabled FROM push_devices WHERE enabled=1');
 if(!deviceRows.length)return 0;
 const devices=deviceRows.map(parseDevice),incidentsByEvent=new Map<string,Incident>();
 for(const i of incidents)for(const id of i.relatedEventIds)incidentsByEvent.set(id,i);
 const currentById=new Map(events.map(e=>[e.id,e])),dedupe=new Set<string>();
 let inserted=0;
 for(const change of changes){
  const current=currentById.get(change.current.id)??change.current,incident=incidentsByEvent.get(current.id);
  if(incident&&incident.primaryEventId!==current.id)continue;
  const decision=relevantChange(change.previous,current);if(!decision)continue;
  const entityId=incident?.id??current.id;
  for(const device of devices){
   const category=selectCategory(current,device.preferences,decision.isUa);if(!category)continue;
   const key=sha([device.deviceId,entityId,current.revision,decision.kind,category].join('|'));
   if(dedupe.has(key))continue;dedupe.add(key);
   const payload=messageFor(current,decision.kind,category,entityId),id='PUSH-'+key.slice(0,40);
   try{
    await db.run('INSERT INTO push_outbox(id,dedupe_key,device_id,entity_id,event_id,event_revision,category,notification_kind,payload,state,attempt_count,next_attempt_at,last_attempt_at,last_error_code,created_at,delivered_at) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)',[
     id,key,device.deviceId,entityId,current.id,current.revision,category,decision.kind,JSON.stringify(payload),'PENDING',0,now.toISOString(),null,null,now.toISOString(),null
    ]);inserted++;
   }catch(err){
    if(!(err instanceof Error)||!/unique|duplicate/i.test(err.message))throw err;
   }
  }
 }
 return inserted;
}

export class PushService{
 constructor(readonly db:PushDb,private readonly encryptionKey:Buffer,readonly provider:PushProvider){
  if(encryptionKey.length!==32)throw new Error('PUSH_ENCRYPTION_KEY_INVALID');
 }
 get enabled(){return true;}
 get providerReadyAny(){return this.provider.ready('ANDROID')||this.provider.ready('IOS');}
 providerReady(platform:PushPlatform){return this.provider.ready(platform);}
 private async deviceRow(id:string){
  const rows=await this.db.all('SELECT * FROM push_devices WHERE device_id=?',[id]);return rows[0]??null;
 }
 private authorize(row:Row|null,secret:string){
  if(!row||!authSecretSchema.safeParse(secret).success||!secretOk(secret,String(row.manage_secret_hash))){
   const e=new Error('PUSH_UNAUTHORIZED') as Error&{statusCode:number};e.statusCode=401;throw e;
  }
 }
 async register(input:unknown,secret:string,now=new Date()){
  const value=pushRegisterSchema.parse(input),parsedSecret=authSecretSchema.parse(secret),hash=tokenHash(value.platform,value.token);
  await this.db.transaction(async db=>{
   const rows=await db.all('SELECT * FROM push_devices WHERE device_id=?',[value.installationId]),existing=rows[0]??null;
   if(existing)this.authorize(existing,parsedSecret);
   const sameToken=(await db.all('SELECT device_id FROM push_devices WHERE token_hash=?',[hash])).find(r=>String(r.device_id)!==value.installationId);
   if(sameToken)await this.scrubDevice(db,String(sameToken.device_id),'TOKEN_REASSIGNED',now);
   const cipher=encryptToken(this.encryptionKey,value.token),prefs=JSON.stringify(value.preferences);
   if(existing){
    await db.run('UPDATE push_devices SET platform=?,token_ciphertext=?,token_hash=?,app_version=?,language=?,preferences=?,enabled=1,updated_at=?,last_seen_at=?,disabled_at=NULL,disabled_reason=NULL WHERE device_id=?',[
     value.platform,cipher,hash,value.appVersion,value.language,prefs,now.toISOString(),now.toISOString(),value.installationId
    ]);
   }else{
    await db.run('INSERT INTO push_devices(device_id,platform,token_ciphertext,token_hash,manage_secret_hash,app_version,language,preferences,enabled,created_at,updated_at,last_seen_at,disabled_at,disabled_reason) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?)',[
     value.installationId,value.platform,cipher,hash,secretHash(parsedSecret),value.appVersion,value.language,prefs,1,now.toISOString(),now.toISOString(),now.toISOString(),null,null
    ]);
   }
  });
  return {registered:true,deviceId:value.installationId,platform:value.platform,providerReady:this.provider.ready(value.platform),lastSeenAt:now.toISOString()};
 }
 async update(id:string,input:unknown,secret:string,now=new Date()){
  pushDeviceIdSchema.parse(id);const value=pushUpdateSchema.parse(input),parsedSecret=authSecretSchema.parse(secret);
  await this.db.transaction(async db=>{
   const row=(await db.all('SELECT * FROM push_devices WHERE device_id=?',[id]))[0]??null;this.authorize(row,parsedSecret);
   const hash=tokenHash(value.platform,value.token),sameToken=(await db.all('SELECT device_id FROM push_devices WHERE token_hash=?',[hash])).find(r=>String(r.device_id)!==id);
   if(sameToken)await this.scrubDevice(db,String(sameToken.device_id),'TOKEN_REASSIGNED',now);
   await db.run('UPDATE push_devices SET platform=?,token_ciphertext=?,token_hash=?,app_version=?,language=?,preferences=?,enabled=1,updated_at=?,last_seen_at=?,disabled_at=NULL,disabled_reason=NULL WHERE device_id=?',[
    value.platform,encryptToken(this.encryptionKey,value.token),hash,value.appVersion,value.language,JSON.stringify(value.preferences),now.toISOString(),now.toISOString(),id
   ]);
  });
  return {registered:true,deviceId:id,platform:value.platform,providerReady:this.provider.ready(value.platform),lastSeenAt:now.toISOString()};
 }
 async preferences(id:string,input:unknown,secret:string,now=new Date()){
  pushDeviceIdSchema.parse(id);const prefs=pushPreferencesSchema.parse(input),row=await this.deviceRow(id);this.authorize(row,authSecretSchema.parse(secret));
  if(Number(row!.enabled)!==1){const e=new Error('PUSH_DEVICE_DISABLED') as Error&{statusCode:number};e.statusCode=409;throw e;}
  await this.db.run('UPDATE push_devices SET preferences=?,updated_at=?,last_seen_at=? WHERE device_id=?',[JSON.stringify(prefs),now.toISOString(),now.toISOString(),id]);
  return {ok:true,preferences:prefs};
 }
 async status(id:string,secret:string,now=new Date()){
  pushDeviceIdSchema.parse(id);const row=await this.deviceRow(id);this.authorize(row,authSecretSchema.parse(secret));
  await this.db.run('UPDATE push_devices SET last_seen_at=? WHERE device_id=?',[now.toISOString(),id]);
  const pending=Number((await this.db.all("SELECT COUNT(*) AS n FROM push_outbox WHERE device_id=? AND state IN ('PENDING','RETRY','SENDING')",[id]))[0]?.n??0);
  const platform=pushPlatformSchema.parse(row!.platform);
  return {registered:Number(row!.enabled)===1,deviceId:id,platform,providerReady:this.provider.ready(platform),lastSeenAt:now.toISOString(),preferences:pushPreferencesSchema.parse(JSON.parse(String(row!.preferences))),pending};
 }
 async unregister(id:string,secret:string,now=new Date()){
  pushDeviceIdSchema.parse(id);const row=await this.deviceRow(id);this.authorize(row,authSecretSchema.parse(secret));
  await this.scrubDevice(this.db,id,'USER_UNREGISTERED',now);
  return {ok:true};
 }
 private async scrubDevice(db:PushDb,id:string,reason:string,now:Date){
  await db.run('UPDATE push_devices SET enabled=0,token_ciphertext=?,token_hash=?,updated_at=?,last_seen_at=?,disabled_at=?,disabled_reason=? WHERE device_id=?',[
   'revoked','revoked:'+id,now.toISOString(),now.toISOString(),now.toISOString(),reason,id
  ]);
  await db.run("UPDATE push_outbox SET state='PERMANENT_FAILURE',last_error_code=?,next_attempt_at=? WHERE device_id=? AND state IN ('PENDING','RETRY','SENDING')",[
   safeError(reason),now.toISOString(),id
  ]);
 }
 private async claimDue(now:Date,limit:number){
  const stale=new Date(now.getTime()-5*60000).toISOString();
  return this.db.transaction(async db=>{
   await db.run("UPDATE push_outbox SET state='RETRY',next_attempt_at=?,last_error_code='LEASE_RECOVERED' WHERE state='SENDING' AND last_attempt_at IS NOT NULL AND last_attempt_at<?",[now.toISOString(),stale]);
   const suffix=db.kind==='postgres'?' FOR UPDATE OF o SKIP LOCKED':'';
   const rows=await db.all(`SELECT o.*,d.platform,d.token_ciphertext,d.enabled FROM push_outbox o LEFT JOIN push_devices d ON d.device_id=o.device_id WHERE o.state IN ('PENDING','RETRY') AND o.next_attempt_at<=? ORDER BY o.created_at,o.id LIMIT ?${suffix}`,[now.toISOString(),limit]);
   for(const r of rows)await db.run("UPDATE push_outbox SET state='SENDING',attempt_count=attempt_count+1,last_attempt_at=? WHERE id=? AND state IN ('PENDING','RETRY')",[now.toISOString(),String(r.id)]);
   return rows;
  });
 }
 async dispatchDue(now=new Date(),limit=50){
  const rows=await this.claimDue(now,Math.max(1,Math.min(limit,200)));let processed=0;
  for(const row of rows){
   const id=String(row.id),attempt=Number(row.attempt_count??0)+1,deviceId=String(row.device_id),platform=pushPlatformSchema.safeParse(row.platform);
   if(Number(row.enabled)!==1||!platform.success){
    await this.db.run("UPDATE push_outbox SET state='PERMANENT_FAILURE',last_error_code=?,next_attempt_at=? WHERE id=?",['DEVICE_DISABLED',now.toISOString(),id]);processed++;continue;
   }
   if(!this.provider.ready(platform.data)){
    const next=new Date(now.getTime()+5*60000).toISOString();
    await this.db.run("UPDATE push_outbox SET state='RETRY',attempt_count=CASE WHEN attempt_count>0 THEN attempt_count-1 ELSE 0 END,next_attempt_at=?,last_error_code='PROVIDER_NOT_READY' WHERE id=?",[next,id]);
    processed++;continue;
   }
   let token:string;
   try{token=decryptToken(this.encryptionKey,String(row.token_ciphertext));}
   catch{
    await this.db.run("UPDATE push_outbox SET state='PERMANENT_FAILURE',last_error_code='TOKEN_DECRYPT_FAILED' WHERE id=?",[id]);
    await this.scrubDevice(this.db,deviceId,'TOKEN_DECRYPT_FAILED',now);processed++;continue;
   }
   let message:PushMessage;
   try{message=JSON.parse(String(row.payload)) as PushMessage;}
   catch{
    await this.db.run("UPDATE push_outbox SET state='PERMANENT_FAILURE',last_error_code='PAYLOAD_INVALID' WHERE id=?",[id]);processed++;continue;
   }
   let result:PushSendResult;
   try{result=await this.provider.send(platform.data,token,message);}
   catch{result={kind:'RETRY',code:'PROVIDER_EXCEPTION'};}
   const code=safeError(result.code);
   if(result.kind==='SUCCESS'){
    await this.db.run("UPDATE push_outbox SET state='DELIVERED',delivered_at=?,last_error_code=NULL WHERE id=?",[now.toISOString(),id]);
   }else if(result.kind==='PERMANENT_FAILURE'){
    await this.db.run("UPDATE push_outbox SET state='PERMANENT_FAILURE',last_error_code=? WHERE id=?",[code,id]);
    if(result.invalidToken)await this.scrubDevice(this.db,deviceId,'TOKEN_INVALID',now);
   }else if(attempt>=5){
    await this.db.run("UPDATE push_outbox SET state='PERMANENT_FAILURE',last_error_code='RETRY_EXHAUSTED' WHERE id=?",[id]);
   }else{
    const delay=Math.min(3600,30*2**(attempt-1)),next=new Date(now.getTime()+delay*1000).toISOString();
    await this.db.run("UPDATE push_outbox SET state='RETRY',next_attempt_at=?,last_error_code=? WHERE id=?",[next,code,id]);
   }
   processed++;
  }
  return processed;
 }
}

type FcmCredentials={project_id:string;client_email:string;private_key:string};
export class FcmProvider{
 private cached:{token:string;expiresAt:number}|null=null;
 constructor(private readonly credentials:FcmCredentials|null){}
 ready(){return !!this.credentials;}
 private async accessToken(){
  if(this.cached&&Date.now()<this.cached.expiresAt-60000)return this.cached.token;
  const c=this.credentials;if(!c)throw new Error('FCM_NOT_CONFIGURED');
  const now=Math.floor(Date.now()/1000),header=b64url(JSON.stringify({alg:'RS256',typ:'JWT'})),claims=b64url(JSON.stringify({iss:c.client_email,scope:'https://www.googleapis.com/auth/firebase.messaging',aud:'https://oauth2.googleapis.com/token',iat:now,exp:now+3600})),unsigned=header+'.'+claims;
  const signer=createSign('RSA-SHA256');signer.update(unsigned);signer.end();const assertion=unsigned+'.'+signer.sign(c.private_key).toString('base64url');
  const response=await fetch('https://oauth2.googleapis.com/token',{method:'POST',headers:{'content-type':'application/x-www-form-urlencoded'},body:new URLSearchParams({grant_type:'urn:ietf:params:oauth:grant-type:jwt-bearer',assertion})});
  const body=await response.json() as {access_token?:string;expires_in?:number};
  if(!response.ok||!body.access_token)throw new Error('FCM_OAUTH_FAILED');
  this.cached={token:body.access_token,expiresAt:Date.now()+(body.expires_in??3600)*1000};return body.access_token;
 }
 async send(token:string,message:PushMessage):Promise<PushSendResult>{
  const c=this.credentials;if(!c)return {kind:'RETRY',code:'FCM_NOT_CONFIGURED'};
  try{
   const access=await this.accessToken(),response=await fetch(`https://fcm.googleapis.com/v1/projects/${encodeURIComponent(c.project_id)}/messages:send`,{
    method:'POST',headers:{authorization:'Bearer '+access,'content-type':'application/json'},
    body:JSON.stringify({message:{token,notification:{title:message.title,body:message.body},data:message.data,android:{priority:'high',collapse_key:message.collapseKey}}})
   }),text=await response.text();
   if(response.ok)return {kind:'SUCCESS',code:'FCM_OK'};
   if(response.status===400||response.status===404){
    if(/UNREGISTERED|registration-token-not-registered|INVALID_ARGUMENT/i.test(text))return {kind:'PERMANENT_FAILURE',code:'FCM_INVALID_TOKEN',invalidToken:true};
   }
   if(response.status===429||response.status>=500)return {kind:'RETRY',code:'FCM_TRANSIENT_'+response.status};
   return {kind:'RETRY',code:'FCM_PROVIDER_'+response.status};
  }catch{return {kind:'RETRY',code:'FCM_TRANSPORT'};}
 }
}

export class ApnsProvider{
 private cached:{token:string;expiresAt:number}|null=null;
 constructor(private readonly config:{keyId:string;teamId:string;bundleId:string;privateKey:string;sandbox:boolean}|null){}
 ready(){return !!this.config;}
 private jwt(){
  if(this.cached&&Date.now()<this.cached.expiresAt)return this.cached.token;
  const c=this.config;if(!c)throw new Error('APNS_NOT_CONFIGURED');
  const now=Math.floor(Date.now()/1000),unsigned=b64url(JSON.stringify({alg:'ES256',kid:c.keyId}))+'.'+b64url(JSON.stringify({iss:c.teamId,iat:now}));
  const signature=cryptoSign('sha256',Buffer.from(unsigned),{key:c.privateKey,dsaEncoding:'ieee-p1363'}).toString('base64url');
  this.cached={token:unsigned+'.'+signature,expiresAt:Date.now()+50*60000};return this.cached.token;
 }
 async send(token:string,message:PushMessage):Promise<PushSendResult>{
  const c=this.config;if(!c)return {kind:'RETRY',code:'APNS_NOT_CONFIGURED'};
  const origin=c.sandbox?'https://api.sandbox.push.apple.com':'https://api.push.apple.com';
  try{
   const result=await new Promise<{status:number;body:string}>((resolve,reject)=>{
    const client=connectHttp2(origin),req=client.request({
     ':method':'POST',':path':'/3/device/'+token,
     authorization:'bearer '+this.jwt(),'apns-topic':c.bundleId,'apns-push-type':'alert','apns-priority':'10','apns-collapse-id':message.collapseKey.slice(0,64),
     'content-type':'application/json',
    });
    let status=0,body='';
    client.on('error',reject);req.on('error',reject);
    req.on('response',headers=>{status=Number(headers[':status']??0);});
    req.setEncoding('utf8');req.on('data',chunk=>body+=chunk);req.on('end',()=>{client.close();resolve({status,body});});
    req.end(JSON.stringify({aps:{alert:{title:message.title,body:message.body},sound:'default'},...message.data}));
   });
   if(result.status===200)return {kind:'SUCCESS',code:'APNS_OK'};
   const reason=(()=>{try{return String((JSON.parse(result.body) as {reason?:string}).reason??'');}catch{return '';}})();
   if(result.status===410||['BadDeviceToken','Unregistered','DeviceTokenNotForTopic'].includes(reason))return {kind:'PERMANENT_FAILURE',code:'APNS_INVALID_TOKEN',invalidToken:true};
   if(result.status===429||result.status>=500)return {kind:'RETRY',code:'APNS_TRANSIENT_'+result.status};
   return {kind:'RETRY',code:'APNS_PROVIDER_'+result.status};
  }catch{return {kind:'RETRY',code:'APNS_TRANSPORT'};}
 }
}

export class CompositePushProvider implements PushProvider{
 constructor(readonly fcm:FcmProvider,readonly apns:ApnsProvider){}
 ready(platform:PushPlatform){return platform==='ANDROID'?this.fcm.ready():this.apns.ready();}
 send(platform:PushPlatform,token:string,message:PushMessage){return platform==='ANDROID'?this.fcm.send(token,message):this.apns.send(token,message);}
}

function fcmFromEnv(env:NodeJS.ProcessEnv):FcmCredentials|null{
 const raw=env.FCM_SERVICE_ACCOUNT_JSON;if(!raw)return null;
 try{
  const parsed=JSON.parse(raw) as Partial<FcmCredentials>;
  if(!parsed.project_id||!parsed.client_email||!parsed.private_key)return null;
  return {project_id:parsed.project_id,client_email:parsed.client_email,private_key:parsed.private_key.replace(/\\n/g,'\n')};
 }catch{return null;}
}
function apnsFromEnv(env:NodeJS.ProcessEnv){
 const {APNS_KEY_ID:keyId,APNS_TEAM_ID:teamId,APNS_BUNDLE_ID:bundleId,APNS_PRIVATE_KEY_P8:privateKey}=env;
 if(!keyId||!teamId||!bundleId||!privateKey)return null;
 return {keyId,teamId,bundleId,privateKey:privateKey.replace(/\\n/g,'\n'),sandbox:env.APNS_ENV==='sandbox'};
}
export function createPushServiceFromEnv(db:PushDb,env:NodeJS.ProcessEnv=process.env){
 const key=parsePushEncryptionKey(env.PUSH_TOKEN_ENCRYPTION_KEY);if(!key)return null;
 return new PushService(db,key,new CompositePushProvider(new FcmProvider(fcmFromEnv(env)),new ApnsProvider(apnsFromEnv(env))));
}

export function bearerSecret(header:string|undefined){
 if(!header?.startsWith('Bearer '))return '';
 return header.slice(7);
}

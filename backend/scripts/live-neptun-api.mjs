import {writeFile} from 'node:fs/promises';

const out=process.argv[2]??'../output/neptun-api-live.json';
const base=process.env.PREVIEW_API_BASE_URL;
if(!base)throw new Error('PREVIEW_API_BASE_URL_MISSING');
const baseUrl=new URL(base);
if(baseUrl.protocol!=='https:'||baseUrl.username||baseUrl.password)throw new Error('PREVIEW_API_BASE_URL_INVALID');
const url=new URL('/v1/neptun',baseUrl);
const response=await fetch(url,{redirect:'error',signal:AbortSignal.timeout(15000),headers:{'User-Agent':'BezpiecznaPolska-preview/0.1 (deployed NEPTUN contract check)','Accept':'application/json'}});
if(!response.ok)throw new Error('NEPTUN_API_HTTP_'+response.status);
const bytes=Buffer.from(await response.arrayBuffer());
if(bytes.length===0||bytes.length>8*1024*1024)throw new Error('NEPTUN_API_BODY_SIZE');
const data=JSON.parse(bytes.toString('utf8'));
const fail=code=>{throw new Error('NEPTUN_API_'+code);};
if(data?.schemaVersion!==2||data?.mode!=='LIVE_AND_HISTORY')fail('SCHEMA');
if(typeof data.serverTime!=='string'||!Number.isFinite(Date.parse(data.serverTime)))fail('SERVER_TIME');
if(typeof data.safetyDelayHours!=='number'||data.safetyDelayHours<24)fail('SAFETY_DELAY');
if(typeof data.minimumPublishedPrecisionKm!=='number'||data.minimumPublishedPrecisionKm<10)fail('PRECISION_POLICY');
if(!data.live||typeof data.live!=='object'||!Array.isArray(data.live.threats)||!data.live.map||!Array.isArray(data.live.map.features))fail('LIVE_SHAPE');
if(!['LIVE','STALE','DOWN','NOT_CONFIGURED','UNAVAILABLE'].includes(data.live.state))fail('LIVE_STATE');
for(const key of ['lastSuccessfulSyncAt','sourceServerTime','validUntil']){
 const value=data.live[key];
 if(value!==null&&value!==undefined&&(typeof value!=='string'||!Number.isFinite(Date.parse(value))))fail('LIVE_TIMESTAMP_'+key.toUpperCase());
}
const allowedTypes=new Set(['uav','fpv','recon','missile','ballistic','kab','mig31k','unknown']);
const forbidden=['heading','velocity','confirmedAt','positionQuality','explanationShort','locality','district','trail','lifecycle','displayConfidence','presumptiveCourse','destination','sea','regionKey'];
const ids=new Set();
for(const threat of data.live.threats){
 if(!threat||typeof threat!=='object'||typeof threat.id!=='string'||ids.has(threat.id))fail('THREAT_ID');
 ids.add(threat.id);
 if(!allowedTypes.has(threat.type))fail('THREAT_TYPE');
 for(const key of forbidden)if(Object.prototype.hasOwnProperty.call(threat,key))fail('PUBLIC_MOTION_FIELD_'+key.toUpperCase());
 const values=[threat.latitude,threat.longitude,threat.precisionKm];
 const allNull=values.every(v=>v===null);
 const allNumeric=values.every(v=>typeof v==='number'&&Number.isFinite(v));
 if(!allNull&&!allNumeric)fail('COORDINATE_PAIR');
 if(allNumeric&&(Math.abs(threat.latitude)>90||Math.abs(threat.longitude)>180||threat.precisionKm<data.minimumPublishedPrecisionKm))fail('COORDINATE_PRECISION');
 if(threat.areaOnly===true&&!allNull)fail('AREA_ONLY_COORDINATES');
 if(typeof threat.updatedAt!=='string'||!Number.isFinite(Date.parse(threat.updatedAt)))fail('THREAT_TIME');
}
for(const feature of data.live.map.features){
 const props=feature?.properties;
 if(feature?.geometry?.type!=='Point'||!Array.isArray(feature.geometry.coordinates)||feature.geometry.coordinates.length!==2||!props||props.live!==true||props.coarse!==true||!ids.has(props.threatId))fail('LIVE_MAP');
 for(const key of forbidden)if(Object.prototype.hasOwnProperty.call(props,key))fail('MAP_MOTION_FIELD_'+key.toUpperCase());
}
if(!Array.isArray(data.tracks)||!data.map||!Array.isArray(data.map.features))fail('HISTORY_SHAPE');
const cutoff=Date.parse(data.serverTime)-data.safetyDelayHours*3600_000;
for(const track of data.tracks){
 if(track?.lifecycle!=='ENDED'||typeof track.endedAt!=='string'||!Number.isFinite(Date.parse(track.endedAt))||Date.parse(track.endedAt)>cutoff)fail('HISTORY_SAFETY_DELAY');
}
const result={
 checkedAt:new Date().toISOString(),
 endpoint:url.origin+'/v1/neptun',
 schemaVersion:data.schemaVersion,
 liveState:data.live.state,
 lastSuccessfulSyncAt:data.live.lastSuccessfulSyncAt??null,
 sourceServerTime:data.live.sourceServerTime??null,
 validUntil:data.live.validUntil??null,
 threatCount:data.live.threats.length,
 types:[...new Set(data.live.threats.map(t=>t.type))].sort(),
 historicalTrackCount:data.tracks.length,
 contract:'deployed-mobile-compatible-sanitized-neptun'
};
await writeFile(out,JSON.stringify(result,null,2)+'\n');
console.log(JSON.stringify(result));

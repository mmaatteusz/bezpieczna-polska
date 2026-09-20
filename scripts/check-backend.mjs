// Release gate: a build must never silently ship with an empty/fake backend URL.
const value=process.env.API_BASE_URL;
if(!value)throw new Error('API_BASE_URL must be supplied by the build configuration');
const url=new URL(value);
if(url.protocol!=='https:'||url.username||url.password||url.search||url.hash||url.hostname==='localhost'||url.hostname.endsWith('.example'))throw new Error('API_BASE_URL must be a deployed HTTPS backend');
const root=url.href.replace(/\/$/,'');
for(const path of ['/readyz','/status?regionId=04','/v1/snapshot?regionId=04','/v1/shelters?regionId=04&limit=1']){
 const response=await fetch(root+path,{signal:AbortSignal.timeout(20000),redirect:'error'});
 if(!response.ok)throw new Error(`Backend gate failed: ${path} HTTP ${response.status}`);
 const data=await response.json();
 if(path==='/readyz'&&(!data.ready||data.database!=='postgres'))throw new Error('PostGIS backend is not ready');
 if(path.startsWith('/status')&&(!data.poland||data.region?.id!=='04'||!data.sourceHealth?.some(s=>s.id==='RCB'&&s.state==='HEALTHY'&&s.lastSuccessfulSyncAt)))throw new Error('RCB is not synchronized');
 if(path.startsWith('/v1/shelters')&&(data.schemaVersion!==1||data.regionId!=='04'||data.health?.state!=='HEALTHY'||!data.health?.lastSuccessfulSyncAt||!data.version||!Array.isArray(data.items)||data.total<1))throw new Error('PSP shelter catalog is not synchronized');
 if(path.startsWith('/v1/snapshot')&&(data.schemaVersion!==1||data.regionId!=='04'||data.events?.some(e=>e.isDemo)))throw new Error('Invalid mobile contract');
}
console.log('Backend ready: PostGIS, synchronized RCB/PSP and mobile API verified');

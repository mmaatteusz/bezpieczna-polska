const sleep=(ms)=>new Promise(resolve=>setTimeout(resolve,ms));
const base=(process.env.SMOKE_BASE_URL||'').replace(/\/+$/,'');
const expectedVersion=process.env.EXPECTED_VERSION||'0.1.0-alpha.20';
const expectedBuildSha=process.env.EXPECTED_BUILD_SHA||'';
if(!/^https:\/\/[^/]+$/.test(base))throw new Error('SMOKE_BASE_URL must be an HTTPS origin');

async function json(path,options){
  const response=await fetch(base+path,options);
  const text=await response.text();
  let body;
  try{body=JSON.parse(text)}catch{throw new Error(path+' invalid JSON status='+response.status+' body='+text.slice(0,200));}
  if(!response.ok)throw new Error(path+' status='+response.status+' body='+text.slice(0,240));
  console.log('PROBE_OK',path,response.status);
  return body;
}
function assert(value,message){if(!value)throw new Error(message);}

function validateNeptun(data){
  assert(data.schemaVersion===2&&data.mode==='LIVE_AND_HISTORY','NEPTUN schema/mode invalid');
  assert(data.minimumPublishedPrecisionKm>=10,'NEPTUN minimum precision invalid');
  assert(data.live?.sourceName==='NEPTUN','NEPTUN source name invalid');
  assert(String(data.live?.sourceUrl||'').includes('neptun.in.ua'),'NEPTUN source URL invalid');
  assert(String(data.live?.attribution||'').includes('NEPTUN'),'NEPTUN attribution invalid');
  assert(data.live?.state==='LIVE','NEPTUN not LIVE: '+data.live?.state);
  assert(!!data.live?.lastSuccessfulSyncAt,'NEPTUN missing lastSuccessfulSyncAt');
  for(const threat of data.live?.threats||[]){
    if(threat.latitude!==null&&threat.latitude!==undefined){
      assert(Number(threat.precisionKm)>=10,'NEPTUN precision below 10 km');
    }
  }
  const raw=JSON.stringify(data.live?.threats||[]);
  for(const key of ['heading','velocity','prediction','predictedTrajectory','confirmedAt']){
    assert(!new RegExp('"'+key+'"\\s*:','i').test(raw),'forbidden NEPTUN field: '+key);
  }
}

(async()=>{
  let reachable=false;
  for(let attempt=0;attempt<30;attempt++){
    try{
      const response=await fetch(base+'/health');
      if(response.ok){reachable=true;break;}
    }catch{}
    await sleep(1000);
  }
  assert(reachable,'smoke API did not become reachable');

  const health=await json('/health');
  assert(health.version===expectedVersion,'wrong version '+health.version);
  if(expectedBuildSha)assert(health.buildSha===expectedBuildSha,'wrong buildSha '+health.buildSha);

  const ready=await json('/ready');
  assert(ready.database==='postgres'&&ready.postgis===true,'PostGIS not ready');

  const sources=await json('/v1/sources');
  assert(Array.isArray(sources.sourceHealth),'sources contract invalid');

  const layers=await json('/v1/map/layers');
  const neptunLayer=layers.layers?.find(layer=>layer.id==='NEPTUN');
  assert(neptunLayer?.mode==='LIVE_AND_HISTORY'&&neptunLayer?.geometry==='COARSE_LIVE_POINTS_AND_HISTORICAL_LINES','NEPTUN layer catalog stale');

  const snapshot=await json('/v1/snapshot?regionId=04');
  assert(snapshot.schemaVersion===1&&snapshot.regionId==='04','snapshot contract invalid');
  assert(snapshot.capabilities?.liveMap===true&&snapshot.capabilities?.neptun===true,'snapshot capabilities invalid');

  await json('/status?regionId=04');
  await json('/v1/radiation?regionId=04');
  await json('/v1/ukraine');

  const shelters=await json('/v1/shelters?regionId=04&q=&offset=0&limit=5');
  assert(shelters.schemaVersion===1&&shelters.regionId==='04','shelters contract invalid');

  const mapShelters=await json('/v1/map/shelters?bbox=17.7,52.9,18.3,53.3&zoom=10.5&regionId=04&availability=ALL');
  assert(mapShelters.type==='FeatureCollection'&&mapShelters.metadata?.schemaVersion===1,'map shelters contract invalid');

  const events=await json('/v1/layers/events.geojson?regionId=04');
  assert(events.type==='FeatureCollection','events GeoJSON invalid');

  const nearest=await json('/v1/shelters/nearest',{
    method:'POST',
    headers:{'content-type':'application/json'},
    body:JSON.stringify({latitude:53.1235,longitude:18.0084,limit:3})
  });
  assert(nearest.schemaVersion===1&&Array.isArray(nearest.items)&&nearest.items.length<=3,'nearest shelters invalid');

  const around=await json('/v1/around',{
    method:'POST',
    headers:{'content-type':'application/json'},
    body:JSON.stringify({latitude:53.1235,longitude:18.0084,radiusKm:20,regionId:'04'})
  });
  assert(around.schemaVersion===1&&Array.isArray(around.nearbyEvents)&&around.nearestShelters,'around invalid');

  const first=await json('/v1/neptun');
  console.log('PROBE_NEPTUN_STATE',JSON.stringify({
    state:first.live?.state,
    lastSuccessfulSyncAt:first.live?.lastSuccessfulSyncAt,
    sourceServerTime:first.live?.sourceServerTime,
    itemCount:first.sourceHealth?.itemCount,
    adapterVersion:first.sourceHealth?.adapterVersion
  }));
  validateNeptun(first);

  const neptunGeo=await json('/v1/layers/neptun.geojson');
  assert(neptunGeo.type==='FeatureCollection','NEPTUN GeoJSON invalid');
  assert(neptunGeo.metadata?.mode==='LIVE_AND_HISTORY'&&neptunGeo.metadata?.liveState==='LIVE','NEPTUN GeoJSON metadata invalid');

  let second=first;
  const firstSuccess=Date.parse(first.live.lastSuccessfulSyncAt);
  for(let attempt=0;attempt<10;attempt++){
    await sleep(2000);
    second=await json('/v1/neptun');
    validateNeptun(second);
    if(Date.parse(second.live.lastSuccessfulSyncAt)>firstSuccess)break;
  }
  assert(Date.parse(second.live.lastSuccessfulSyncAt)>firstSuccess,'NEPTUN worker did not advance within 20 seconds');

  console.log('PROBE_NEPTUN_REFRESH',first.live.lastSuccessfulSyncAt,'->',second.live.lastSuccessfulSyncAt,'threats',second.live.threats.length);
  const nonHealthy=sources.sourceHealth.filter(source=>source.state!=='HEALTHY').map(source=>({id:source.id,state:source.state,errorCode:source.errorCode}));
  console.log('PROBE_NON_HEALTHY_SOURCES',JSON.stringify(nonHealthy));
  console.log('PROBE_ALL_OK');
})().catch(error=>{
  console.error('PROBE_FAILED',error?.stack||error);
  process.exit(1);
});

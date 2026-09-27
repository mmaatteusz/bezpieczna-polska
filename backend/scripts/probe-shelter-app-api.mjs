const candidates=[
  '/api/health',
  '/api/shelters/count',
  '/api/shelters?limit=1',
  '/api/shelters/search?limit=1',
  '/api/shelters/nearby?lat=52.2297&lon=21.0122&limit=1',
  '/api/shelters/bbox?minLat=52.22&maxLat=52.24&minLon=21.00&maxLon=21.03',
  '/api/shelters/stats',
  '/api/points/count',
  '/api/shelter-points?limit=1',
  '/api/nearby-shelters?lat=52.2297&lon=21.0122&limit=1',
];
for(const path of candidates){
 try{
  const response=await fetch(new URL(path,'https://gdziesieukryc.pl/'),{
   redirect:'manual',
   signal:AbortSignal.timeout(15000),
   headers:{'User-Agent':'BezpiecznaPolska-contract-probe/1.0','Accept':'application/json,text/plain,*/*'}
  });
  const body=await response.text();
  console.log('APP_API_PROBE',JSON.stringify({
   path,status:response.status,location:response.headers.get('location'),
   contentType:response.headers.get('content-type'),
   bodyPrefix:body.replace(/\s+/g,' ').slice(0,1200)
  }));
 }catch(error){
  console.log('APP_API_PROBE',JSON.stringify({path,error:error instanceof Error?error.message:String(error)}));
 }
}

const base='https://gdziesieukryc.pl/';
const htmlResponse=await fetch(base,{signal:AbortSignal.timeout(20000),headers:{'User-Agent':'Mozilla/5.0 (compatible; BezpiecznaPolska-contract-probe/1.0)','Accept':'text/html'}});
const html=await htmlResponse.text();
console.log('APP_HTML',JSON.stringify({status:htmlResponse.status,bytes:html.length}));
const urls=new Set();
for(const match of html.matchAll(/(?:src|href)=["']([^"'?#]+\.(?:js|mjs))[^"']*["']/gi)){
 try{urls.add(new URL(match[1],base).href);}catch{}
}
console.log('APP_ASSETS',JSON.stringify([...urls]));
for(const url of [...urls].slice(0,20)){
 try{
  const response=await fetch(url,{signal:AbortSignal.timeout(30000),headers:{'User-Agent':'Mozilla/5.0 (compatible; BezpiecznaPolska-contract-probe/1.0)','Accept':'application/javascript,text/javascript,*/*'}});
  const text=await response.text();
  const endpoints=[...new Set([
    ...[...text.matchAll(/["'`](\/api\/[A-Za-z0-9_?=&.%\-/{}:[\]]{1,180})["'`]/g)].map(m=>m[1]),
    ...[...text.matchAll(/https?:\/\/gdziesieukryc\.pl\/api\/[A-Za-z0-9_?=&.%\-/{}:[\]]{1,180}/g)].map(m=>m[0]),
  ])].filter(v=>/shel|schron|point|near|map|count|location|bbox|gmin|powiat|woj/i.test(v));
  const hints=[...new Set([...text.matchAll(/.{0,80}(?:shelter|schron|punkt(?:y|ów)?|useProgressiveShelters).{0,160}/gi)].map(m=>m[0].replace(/\s+/g,' ')))].slice(0,30);
  if(endpoints.length||hints.length)console.log('APP_JS',JSON.stringify({url,status:response.status,bytes:text.length,endpoints,hints}));
 }catch(error){console.log('APP_JS_ERROR',JSON.stringify({url,error:error instanceof Error?error.message:String(error)}));}
}

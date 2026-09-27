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

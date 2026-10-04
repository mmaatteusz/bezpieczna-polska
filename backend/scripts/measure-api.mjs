// Read-only baseline, sequential and deliberately small: no load test of production.
const base=new URL(process.argv[2]??'http://127.0.0.1:8080');
const region=process.argv[3]??'04';
if(!/^(PL|\d{2})$/.test(region))throw new Error('Invalid region');
const results=[];
for(const path of ['/health',`/v1/snapshot?regionId=${region}`,`/v1/snapshot?regionId=${region}&mode=compact`]){
 const samples=[];
 for(let i=0;i<10;i++){
  const start=performance.now();
  const response=await fetch(new URL(path,base),{signal:AbortSignal.timeout(30000)});
  const body=Buffer.from(await response.arrayBuffer());
  samples.push({ms:performance.now()-start,bytes:body.length,status:response.status});
 }
 const times=samples.map(s=>s.ms).sort((a,b)=>a-b);
 results.push({path,samples:10,p50Ms:times[4],p95Ms:times[9],minBytes:Math.min(...samples.map(s=>s.bytes)),maxBytes:Math.max(...samples.map(s=>s.bytes)),statuses:[...new Set(samples.map(s=>s.status))]});
}
console.log(JSON.stringify({measuredAt:new Date().toISOString(),base:base.origin,decodedBodyBytes:true,results},null,2));

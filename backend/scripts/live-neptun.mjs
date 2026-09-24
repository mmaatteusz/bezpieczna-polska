import {writeFile} from 'node:fs/promises';
import {NEPTUN_API,parseNeptunLive} from '../dist/neptun-live-adapter.js';

const out=process.argv[2]??'../output/neptun-live.json';
const response=await fetch(NEPTUN_API,{redirect:'error',signal:AbortSignal.timeout(15000),headers:{'User-Agent':'BezpiecznaPolska-preview/0.1 (NEPTUN contract check)','Accept':'application/json'}});
if(!response.ok)throw new Error('NEPTUN_HTTP_'+response.status);
const bytes=Buffer.from(await response.arrayBuffer());
if(bytes.length===0||bytes.length>4*1024*1024)throw new Error('NEPTUN_BODY_SIZE');
const raw=JSON.parse(bytes.toString('utf8'));
const parsed=parseNeptunLive(raw,new Date());
const result={
  checkedAt:new Date().toISOString(),
  source:NEPTUN_API,
  serverTime:parsed.serverTime,
  threatCount:parsed.threats.length,
  types:[...new Set(parsed.threats.map(t=>t.type))].sort(),
  contract:'sanitized-live-no-heading-no-velocity'
};
await writeFile(out,JSON.stringify(result,null,2)+'\n');
console.log(JSON.stringify(result));

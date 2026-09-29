import {writeFile} from 'node:fs/promises';

const baselineOrigin=process.env.BASELINE_API_BASE_URL??'';
const candidateOrigin=process.env.CANDIDATE_API_BASE_URL??'';
const expectedCandidateSha=(process.env.CANDIDATE_EXPECTED_BUILD_SHA??'').trim();
const rounds=Number(process.env.OBSERVATION_ROUNDS??3);
const intervalSeconds=Number(process.env.OBSERVATION_INTERVAL_SECONDS??60);
const output=process.argv[2]??'oracle-runtime-comparison.json';

const sourceIds=[
  'RCB','RSO','WCZK-18','LEVELS','SHELTERS','IMGW_METEO','IMGW_HYDRO',
  'PAA','PAA_MEASUREMENTS','CERT','SG','POLICE','PSP_INCIDENTS','UA','NEPTUN'
];

function origin(value,name){
  let url;
  try{url=new URL(value);}catch{throw new Error(name+'_INVALID_URL');}
  if(url.protocol!=='https:'||url.username||url.password||url.search||url.hash||
     (url.pathname!==''&&url.pathname!=='/'))throw new Error(name+'_MUST_BE_HTTPS_ORIGIN');
  return url.href.replace(/\/$/,'');
}
const baseline=origin(baselineOrigin,'BASELINE_API_BASE_URL');
const candidate=origin(candidateOrigin,'CANDIDATE_API_BASE_URL');

if(expectedCandidateSha&&!/^[a-f0-9]{40}$/.test(expectedCandidateSha))
  throw new Error('CANDIDATE_EXPECTED_BUILD_SHA_INVALID');
if(!Number.isInteger(rounds)||rounds<1||rounds>10)throw new Error('OBSERVATION_ROUNDS_INVALID');
if(!Number.isInteger(intervalSeconds)||intervalSeconds<0||intervalSeconds>300)
  throw new Error('OBSERVATION_INTERVAL_SECONDS_INVALID');

const sleep=ms=>new Promise(resolve=>setTimeout(resolve,ms));

async function json(base,path){
  const response=await fetch(base+path,{
    redirect:'error',
    signal:AbortSignal.timeout(15000),
    headers:{'User-Agent':'BezpiecznaPolska-oracle-runtime-compare/1.0','Accept':'application/json'}
  });
  const text=await response.text();
  let body;
  try{body=JSON.parse(text);}catch{throw new Error(base+' '+path+' INVALID_JSON HTTP_'+response.status);}
  if(!response.ok)throw new Error(base+' '+path+' HTTP_'+response.status);
  return body;
}

function state(source){return source?.healthStatus??source?.state??'MISSING';}
function successAt(source){return source?.lastSuccessfulSyncAt??source?.lastSuccess??null;}
function compactSource(source,id){
  if(!source)return {id,state:'MISSING',errorCode:'MISSING',responseTimeMs:null,lastSuccessfulSyncAt:null,itemCount:null};
  return {
    id,
    state:state(source),
    errorCode:source.errorCode??null,
    responseTimeMs:Number.isFinite(Number(source.responseTime))?Number(source.responseTime):null,
    lastSuccessfulSyncAt:successAt(source),
    itemCount:Number.isFinite(Number(source.itemCount))?Number(source.itemCount):null,
  };
}
function indexSources(payload){
  const rows=Array.isArray(payload?.sourceHealth)?payload.sourceHealth:
    Array.isArray(payload)?payload:[];
  return new Map(rows.map(row=>[row.id,row]));
}

async function observe(base,label){
  const startedAt=new Date().toISOString();
  const [health,ready,sources]=await Promise.all([
    json(base,'/health'),
    json(base,'/ready'),
    json(base,'/v1/sources'),
  ]);
  if(health.environment!=='production')
    throw new Error(label+'_ENVIRONMENT_NOT_PRODUCTION');
  if(ready.ready!==true||ready.database!=='postgres'||ready.postgis!==true)
    throw new Error(label+'_POSTGIS_NOT_READY');
  return {
    label,
    origin:base,
    observedAt:startedAt,
    health:{
      version:health.version??null,
      buildSha:health.buildSha??null,
      environment:health.environment??null,
    },
    ready:{
      ready:ready.ready??null,
      database:ready.database??null,
      postgis:ready.postgis??null,
    },
    sources:(()=>{
      const map=indexSources(sources);
      return Object.fromEntries(sourceIds.map(id=>[id,compactSource(map.get(id),id)]));
    })(),
  };
}

function compareRound(baselineRow,candidateRow){
  const sources={};
  let improvements=0,regressions=0,candidateHealthy=0,baselineHealthy=0;
  for(const id of sourceIds){
    const a=baselineRow.sources[id],b=candidateRow.sources[id];
    if(a.state==='HEALTHY')baselineHealthy++;
    if(b.state==='HEALTHY')candidateHealthy++;
    const improved=a.state!=='HEALTHY'&&b.state==='HEALTHY';
    const regressed=a.state==='HEALTHY'&&b.state!=='HEALTHY';
    if(improved)improvements++;
    if(regressed)regressions++;
    sources[id]={
      baseline:a,
      candidate:b,
      improved,
      regressed,
      responseTimeDeltaMs:
        a.responseTimeMs!==null&&b.responseTimeMs!==null?b.responseTimeMs-a.responseTimeMs:null,
    };
  }
  return {baselineHealthy,candidateHealthy,improvements,regressions,sources};
}

const observations=[];
for(let round=1;round<=rounds;round++){
  const [a,b]=await Promise.all([
    observe(baseline,'baseline'),
    observe(candidate,'candidate'),
  ]);
  if(expectedCandidateSha&&b.health.buildSha!==expectedCandidateSha)
    throw new Error('CANDIDATE_BUILD_SHA_MISMATCH expected='+expectedCandidateSha+' actual='+(b.health.buildSha??'null'));

  const comparison=compareRound(a,b);
  observations.push({round,baseline:a,candidate:b,comparison});

  console.log('COMPARE_ROUND',round,
    'baselineHealthy='+comparison.baselineHealthy,
    'candidateHealthy='+comparison.candidateHealthy,
    'improvements='+comparison.improvements,
    'regressions='+comparison.regressions);
  for(const id of sourceIds){
    const row=comparison.sources[id];
    console.log('COMPARE_SOURCE',id,
      'baseline='+row.baseline.state+(row.baseline.errorCode?'('+row.baseline.errorCode+')':''),
      'candidate='+row.candidate.state+(row.candidate.errorCode?'('+row.candidate.errorCode+')':''),
      'baselineMs='+(row.baseline.responseTimeMs??'n/a'),
      'candidateMs='+(row.candidate.responseTimeMs??'n/a'));
  }

  if(round<rounds&&intervalSeconds>0)await sleep(intervalSeconds*1000);
}

const last=observations.at(-1);
const report={
  generatedAt:new Date().toISOString(),
  baselineOrigin:baseline,
  candidateOrigin:candidate,
  expectedCandidateSha:expectedCandidateSha||null,
  rounds,
  intervalSeconds,
  sourceIds,
  observations,
  summary:{
    finalBaselineHealthy:last.comparison.baselineHealthy,
    finalCandidateHealthy:last.comparison.candidateHealthy,
    finalImprovements:last.comparison.improvements,
    finalRegressions:last.comparison.regressions,
    candidateBuildSha:last.candidate.health.buildSha,
    candidateVersion:last.candidate.health.version,
  },
};

await writeFile(output,JSON.stringify(report,null,2)+'\n','utf8');
console.log('COMPARE_REPORT',output);
console.log('COMPARE_PASS');

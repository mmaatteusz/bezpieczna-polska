import {openDb,Store} from './store.js';
import {initializeSources} from './adapters.js';
import {prepareOperatorShelterSnapshot,SHELTER_RESOURCE} from './shelter-adapter.js';
import {decodeShelterSnapshot,validateBootstrapBaseUrl} from './shelter-bootstrap.js';

const baseValue=process.env.SHELTER_BOOTSTRAP_PARTS_BASE_URL?.trim();
if(!baseValue){
 console.log('SHELTER_BOOTSTRAP_SKIPPED');
 process.exit(0);
}

const count=Number(process.env.SHELTER_BOOTSTRAP_PART_COUNT??0);
const expectedGzipSha=process.env.SHELTER_BOOTSTRAP_GZIP_SHA256?.trim()??'';
const expectedCsvSha=process.env.SHELTER_BOOTSTRAP_CSV_SHA256?.trim()??'';
if(!Number.isInteger(count)||count<1||count>100)throw new Error('SHELTER_BOOTSTRAP_INVALID_PART_COUNT');
const base=validateBootstrapBaseUrl(baseValue);

async function fetchText(url:URL|string){
 const response=await fetch(url,{redirect:'error',signal:AbortSignal.timeout(30000),headers:{'User-Agent':'BezpiecznaPolska-shelter-bootstrap/1.0','Accept':'text/plain,application/json,*/*'}});
 if(!response.ok)throw new Error('SHELTER_BOOTSTRAP_HTTP_'+response.status);
 return response.text();
}

const started=Date.now(),parts:string[]=[];
for(let i=0;i<count;i++){
 const name=`part-${String(i).padStart(2,'0')}.b64`;
 parts.push(await fetchText(new URL(name,base)));
}
const csv=decodeShelterSnapshot(parts,expectedGzipSha,expectedCsvSha);
const resourceText=await fetchText(SHELTER_RESOURCE);
const prepared=prepareOperatorShelterSnapshot(csv,resourceText,new Date());

const db=openDb(process.env.DATABASE_URL,process.env.SQLITE_PATH);
try{
 const store=new Store(db);
 await store.init();
 await initializeSources(store);
 const previous=(await store.health()).find(h=>h.id==='SHELTERS');
 if(!previous)throw new Error('SHELTER_SOURCE_NOT_INITIALIZED');
 if(previous.sourceUpdatedAt&&Date.parse(prepared.metadata.sourceUpdatedAt)<Date.parse(previous.sourceUpdatedAt))throw new Error('SHELTER_SNAPSHOT_OLDER_THAN_LAST_GOOD');
 const importedAt=new Date().toISOString();
 await store.applyShelterSync(prepared.shelters,{
  ...previous,
  ...prepared.metadata,
  enabled:true,
  state:'HEALTHY',
  lastAttempt:importedAt,
  lastSuccess:importedAt,
  lastItemTime:prepared.metadata.sourceUpdatedAt,
  failureCount:0,
  responseTime:Date.now()-started,
  complete:true,
  coverage:'FACILITY_CATALOG',
  pagesFetched:1,
  itemCount:prepared.shelters.length,
  errorCode:null,
  adapterVersion:'operator-official-csv-bootstrap/1.0.0'
 });
 const health=(await store.health()).find(h=>h.id==='SHELTERS');
 const page=await store.shelterPage({regionId:'PL',q:'',limit:1,offset:0});
 if(!health||page.total!==prepared.shelters.length)throw new Error('SHELTER_BOOTSTRAP_VERIFY_FAILED');
 console.log('SHELTER_BOOTSTRAP_OK',JSON.stringify({
  itemCount:prepared.shelters.length,
  dataDate:prepared.metadata.dataDate,
  sourceUpdatedAt:prepared.metadata.sourceUpdatedAt,
  sourceContentHash:prepared.metadata.sourceContentHash,
  provenance:prepared.metadata.fallbackSelected
 }));
}finally{
 await db.close();
}

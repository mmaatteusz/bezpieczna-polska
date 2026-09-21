import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync,mkdtempSync,rmSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {parsePaaArticle,parsePaaIndex,paaAdapter,PAA_INDEX} from '../src/paa-adapter.js';
import {radiationMeasurementSchema,radiationStatus,type RadiationMeasurement} from '../src/radiation.js';
import {computeStatus,sourceHealth,type Health} from '../src/domain.js';
import {Store,openDb} from '../src/store.js';
import {initializeSources,ingest} from '../src/adapters.js';
import {buildApp} from '../src/app.js';
const now=new Date('2026-09-21T12:00:00Z'),url='https://www.gov.pl/web/paa/test-fixture';
const article=(title:string,body:string)=>`<main><article><h2>${title}</h2><p class="event-date">21.09.2026</p><div class="editor-content"><p>${body}</p></div></article></main>`;
const warning=()=>parsePaaArticle(article('Komunikat PAA — zagrożenie radiacyjne','Na terenie całej Polski występuje zagrożenie radiacyjne.'),url,now)!;
const health=(id='PAA'):Health=>({checkedEventIds:[warning().id],id,name:id,url:PAA_INDEX,state:'HEALTHY',lastSuccess:now.toISOString(),lastFailure:null,lastItemTime:null,lastAttempt:now.toISOString(),failureCount:0,responseTime:1,maxAgeSeconds:900,complete:false,enabled:true});
const measurement:RadiationMeasurement={stationId:'TEST-ONLY',name:'Syntetyczna stacja testowa',latitude:53.12,longitude:18.01,measuredAt:now.toISOString(),value:100,unit:'nSv/h',sourceUpdatedAt:now.toISOString(),regionId:'04'};
const fixture=readFileSync('test/fixtures/paa/information.html','utf8');
test('PAA official indexes and fail-closed structure',()=>{
 for(const file of ['index.html','index-2.html','index-3.html'])assert.equal(parsePaaIndex(readFileSync('test/fixtures/paa/'+file,'utf8')).urls.length,10);
 assert.throws(()=>parsePaaIndex('<main>new format</main>'),/CONTRACT/);
 assert.throws(()=>parsePaaIndex(readFileSync('test/fixtures/paa/index.html','utf8').replace('/web/paa/delegacja-paa','https://evil.example/web/paa/delegacja-paa')),/URL_DENIED/);
});
test('Real PAA reassuring message: no alarm or invented geometry/timestamps',()=>{
 const e=parsePaaArticle(fixture,'https://www.gov.pl/web/paa/sytuacja-radiacyjna-w-normie--nie-ma-zagrozenia',now)!;
 assert.equal(e.eventType,'RADIATION');assert.equal(e.officialWarning,false);assert.equal(e.radiationAssessment?.state,'INFORMATION');assert.equal(e.publishedAt,null);assert.equal(e.publicationDate,'2026-05-08');assert.equal(e.geometry,null);assert.equal(e.latitude,null);
 assert.equal(computeStatus([e],[health()],'PL',now).hazardLevel,'UNKNOWN');
});
test('Explicit PAA warning, ended message and coverage',()=>{
 const e=warning();assert.equal(e.officialWarning,true);assert.equal(e.lifecycle,'ACTIVE');assert.deepEqual(e.regions,['PL']);
 assert.equal(computeStatus([e],[health()],'PL',now).hazardLevel,'CAUTION');assert.equal(radiationStatus([e],[health()],'04',now).communicationState,'ACTIVE');
 const ended=parsePaaArticle(article('Alarm radiacyjny odwołany','Komunikat dotyczący sytuacji radiacyjnej i zakończenia działań.'),url,now)!;
 assert.equal(ended.lifecycle,'ENDED');assert.equal(computeStatus([ended],[health()],'PL',now).hazardLevel,'UNKNOWN');
});
test('Negations, conditional, quoted, foreign warnings and measurements are not alarms',()=>{
 for(const text of ['Na terenie całej Polski nie występuje zagrożenie radiacyjne.','Jeżeli na terenie całej Polski występuje zagrożenie radiacyjne, należy stosować komunikaty.','„Na terenie całej Polski występuje zagrożenie radiacyjne.” — fałszywy wpis.','Na terytorium Ukrainy występuje zagrożenie radiacyjne.','Wartość pomiaru wzrosła ze 100 do 120 nSv/h.']){
  const e=parsePaaArticle(article('Komunikat PAA — sytuacja radiacyjna',text),url,now)!;assert.equal(e.officialWarning,false);assert.equal(computeStatus([e],[health()],'PL',now).hazardLevel,'UNKNOWN');
 }
});
test('STALE and DOWN preserve uncertainty and affect coverage',()=>{
 for(const h of [{...health(),state:'BROKEN' as const},{...health(),lastSuccess:'2026-09-20T12:00:00Z'}]){
  const status=computeStatus([warning()],[h],'PL',now);assert.equal(status.hazardLevel,'UNKNOWN');assert.equal(status.coverageState,'UNAVAILABLE');assert.ok(status.reasonCodes.includes('LAST_KNOWN_WARNING'));assert.equal(radiationStatus([warning()],[h],'PL',now).communicationState,'UNAVAILABLE');
 }
 assert.equal(sourceHealth([health()],new Date(now.getTime()+900000))[0].state,'STALE');
});
test('Normal/large readings never create Events; fresh, stale, missing data',()=>{
 for(const value of [0,100,101,100000]){const data=radiationStatus([],[health(),health('PAA_MEASUREMENTS')],'04',now,[{...measurement,value}]);assert.equal(data.measurementState,'FRESH');assert.equal(data.messages.length,0);assert.equal(data.measuredValuesAffectHazard,false);assert.equal(computeStatus([],[health(),health('PAA_MEASUREMENTS')],'PL',now).hazardLevel,'UNKNOWN');}
 assert.equal(radiationStatus([],[health('PAA_MEASUREMENTS')],'04',now).measurementState,'NO_DATA');assert.equal(radiationStatus([],[],'04',now).measurementState,'NOT_CONFIGURED');assert.equal(radiationStatus([],[health('PAA_MEASUREMENTS')],'04',new Date(now.getTime()+900000),[measurement]).measurementState,'STALE');
});
test('Reject missing units, bad values, invalid/out-of-envelope geometry',()=>{
 for(const bad of [{unit:undefined},{value:NaN},{value:Infinity},{value:-1},{unit:'mSv'},{latitude:90},{longitude:2.35},{latitude:null}])assert.equal(radiationMeasurementSchema.safeParse({...measurement,...bad}).success,false);
 assert.ok(radiationMeasurementSchema.safeParse({...measurement,latitude:null,longitude:null}).success);
});
test('Unsupported article/dates/validity rejected',()=>{
 assert.throws(()=>parsePaaArticle('<article>changed</article>',url,now),/CONTRACT/);assert.throws(()=>parsePaaArticle(article('Komunikat PAA','Sytuacja radiacyjna w kraju.</p><p>Obowiązuje od: jutro'),url,now),/VALIDITY/);assert.throws(()=>parsePaaArticle(fixture,'https://evil.example/web/paa/x',now),/URL_DENIED/);
});
test('Failed endpoint/format keep LKG; resync/restart without duplicates',async()=>{
 const dir=mkdtempSync(join(tmpdir(),'paa-')),path=join(dir,'test.db');let store=new Store(openDb(undefined,path));
 const adapter={id:'PAA',version:'test-only',async sync(){return {events:[warning()],complete:false,coverage:'RECENT_PUBLICATIONS' as const,pagesFetched:1};}};
 try{
  await store.init();await ingest(store,[adapter]);await ingest(store,[adapter]);assert.equal((await store.timeline(warning().id)).length,1);
  for(const code of ['SOURCE_HTTP_503','SOURCE_SYNC_FAILED','PAA_ARTICLE_CONTRACT_CHANGED']){await ingest(store,[{...adapter,async sync(){throw new Error(code);}}]);const h=(await store.health()).find(h=>h.id==='PAA')!;assert.equal(h.state,'BROKEN');assert.equal(h.errorCode,code);assert.ok(h.lastAttempt);assert.ok(h.lastSuccess);assert.equal((await store.events()).length,1);}
  await store.db.close();store=new Store(openDb(undefined,path));await store.init();await initializeSources(store);assert.equal((await store.events()).length,1);assert.equal((await store.health()).find(h=>h.id==='PAA')!.state,'BROKEN');
  await ingest(store,[adapter]);assert.equal((await store.timeline(warning().id)).length,1);
  const app=await buildApp(store);try{const snap=(await app.inject('/v1/snapshot?regionId=04')).json();assert.equal(snap.radiation.messages.length,1);assert.equal(snap.capabilities.paaMeasurements,false);assert.equal((await app.inject('/v1/layers/events.geojson?source=PAA')).json().features.length,0);}finally{await app.close();}
 }finally{await store.db.close();rmSync(dir,{recursive:true,force:true});}
});
test('Measurement atomic LKG, idempotence, restart; no Event writes',async()=>{
 const dir=mkdtempSync(join(tmpdir(),'paa-m-')),path=join(dir,'db');let s=new Store(openDb(undefined,path));
 try{await s.init();await s.applyRadiationSync([measurement],health('PAA_MEASUREMENTS'));await s.applyRadiationSync([measurement],health('PAA_MEASUREMENTS'));await assert.rejects(s.applyRadiationSync([{...measurement,value:-1}],health('PAA_MEASUREMENTS')));await assert.rejects(s.applyRadiationSync([],health('PAA_MEASUREMENTS')));await assert.rejects(s.applyRadiationSync([{...measurement,measuredAt:'2026-01-01T00:00:00Z'}],health('PAA_MEASUREMENTS')));assert.equal((await s.radiationMeasurements())[0].value,100);assert.equal((await s.events()).length,0);await s.db.close();s=new Store(openDb(undefined,path));await s.init();assert.equal((await s.radiationMeasurements()).length,1);}finally{await s.db.close();rmSync(dir,{recursive:true,force:true});}
});
test('Bounded archive rechecks known messages; HTTP failure aborts',async()=>{
 const index='<main><article><h2>Aktualności</h2><div class="art-prev"><ul><li><span class="date">21.09.2026</span><div class="title"><a href="/web/paa/news">News</a></div></li></ul></div></article></main>',seen:string[]=[];
 const result=await paaAdapter.sync({now,previousEvents:[warning()],fetchText:async u=>{seen.push(u);return u===PAA_INDEX?index:u===url?article('Alarm radiacyjny zakończony','Zakończono zdarzenie radiacyjne, działania dobiegły końca.'):article('Spotkanie przedstawicieli PAA','Spotkanie poświęcone współpracy i sprawom organizacyjnym.');}});
 assert.ok(seen.includes(url));assert.equal(result.events[0].lifecycle,'ENDED');assert.equal(result.complete,false);await assert.rejects(paaAdapter.sync({now,fetchText:async()=>{throw new Error('SOURCE_HTTP_503');}}),/503/);
});

test('Real multiple-body editorial page is not an incident',()=>{
 assert.equal(parsePaaArticle(readFileSync('test/fixtures/paa/editorial-multiple-blocks.html','utf8'),'https://www.gov.pl/web/paa/miedzynarodowi-eksperci-w-paa--przygotowania-do-misji-irrs-follow-up',now),null);
});
test('Stable revision still has fresh checkedEventIds after a new synchronization',async()=>{
 const store=new Store(openDb(undefined,':memory:'));await store.init();
 try{
  const adapter={id:'PAA',version:'test-only',async sync(){return {events:[warning()],complete:false,coverage:'RECENT_PUBLICATIONS' as const,pagesFetched:1};}};
  await ingest(store,[adapter]);await ingest(store,[adapter]);const h=(await store.health()).find(h=>h.id==='PAA')!;
  assert.ok(h.checkedEventIds?.includes(warning().id));
  assert.equal(computeStatus(await store.events(),[h],'PL',new Date()).hazardLevel,'CAUTION');
  assert.equal((await store.timeline(warning().id)).length,1);
 }finally{await store.db.close();}
});
test('PAA PostGIS source/event transaction survives connection restart',{skip:!process.env.TEST_DATABASE_URL},async()=>{
 const id='PAA-postgis-'+Date.now();let store=new Store(openDb(process.env.TEST_DATABASE_URL));
 const e={...warning(),id};
 try{
  await store.init();await store.applySync([e],{...health(),checkedEventIds:[id]});await store.db.close();
  store=new Store(openDb(process.env.TEST_DATABASE_URL));await store.init();
  assert.equal((await store.get(id))?.eventType,'RADIATION');await store.applySync([e],{...health(),checkedEventIds:[id]});assert.equal((await store.timeline(id)).length,1);
 }finally{await store.db.run('DELETE FROM event_revisions WHERE event_id=?',[id]);await store.db.close();}
});

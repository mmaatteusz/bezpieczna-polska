import test from 'node:test';
import assert from 'node:assert/strict';
import {parseSgIndex,parseSgArticle,sgAdapter,SG_INDEX} from '../src/sg-adapter.js';
import {computeStatus,type Health} from '../src/domain.js';
import {Store,openDb} from '../src/store.js';
import {ingest,initializeSources} from '../src/adapters.js';

const now=new Date('2026-09-21T12:00:00Z');
const opUrl='https://www.strazgraniczna.pl/pl/aktualnosci/20001,Utrudnienia-na-przejsciu-granicznym-w-Hrebennem.html';
const falseUrl='https://www.strazgraniczna.pl/pl/aktualnosci/20002,Auto-odzyskane-na-przejsciu-granicznym-w-Budomierzu.html';
const endedUrl='https://www.strazgraniczna.pl/pl/aktualnosci/20003,Przywrocono-ruch-na-przejsciu-granicznym.html';

const page=(links:string[])=>'<div id="content"><div class="naglowek"><h2>Aktualności</h2></div>'+links.map(u=>'<a href="'+new URL(u).pathname+'">x</a>').join('')+'</div>';
const article=(title:string,lead:string,body:string,date='21.09.2026')=>
 '<div class="head"><h2>'+title+'</h2><section class="metryka"><div class="data icon-info">'+date+'</div></section><h3>'+lead+'</h3></div><article class="txt"><p>'+body+'</p></article>';

const operational=article(
 'Utrudnienia na przejściu granicznym w Hrebennem',
 'Na drogowym przejściu granicznym w Hrebennem w woj. lubelskim występują utrudnienia w ruchu.',
 'Czasowo ograniczono liczbę pasów odpraw. Podróżnym sugerujemy skorzystanie z sąsiednich przejść granicznych.'
);
const falsePositive=article(
 'Auto odzyskane na przejściu granicznym w Budomierzu',
 'Funkcjonariusze SG odzyskali pojazd.',
 'Do kontroli na przejściu granicznym zgłosił się kierowca. Samochód figurował jako skradziony.'
);
const ended=article(
 'Przywrócono ruch na przejściu granicznym w Hrebennem',
 'Ruch graniczny został przywrócony.',
 'Odprawy graniczne odbywają się normalnie.'
);

test('SG index accepts only official Aktualności article links and fails closed',()=>{
 const urls=parseSgIndex(page([opUrl,falseUrl]));
 assert.deepEqual(urls,[opUrl,falseUrl]);
 assert.throws(()=>parseSgIndex('<div id="content"><div class="naglowek"><h2>Aktualności</h2></div></div>'),/EMPTY/);
 assert.throws(()=>parseSgIndex(page([opUrl,opUrl.replace('Utrudnienia','Inny-slug')])),/DUPLICATE/);
});

test('Operational border notice becomes BORDER Event without invented geometry or danger status',()=>{
 const e=parseSgArticle(operational,opUrl,now)!;
 assert.ok(e);
 assert.equal(e.id,'SG-20001');
 assert.equal(e.eventType,'BORDER');
 assert.equal(e.verification,'CONFIRMED');
 assert.equal(e.officialWarning,false);
 assert.equal(e.lifecycle,'UNKNOWN');
 assert.equal(e.severity,'NORMAL');
 assert.deepEqual(e.regions,['06']);
 assert.equal(e.geometry,null);
 assert.equal(e.latitude,null);
 assert.equal(e.longitude,null);
 assert.equal(e.publicationDate,'2026-09-21');
 assert.equal(e.publishedAt,null);
 assert.match(e.locationText!,/Hrebennem/);
 assert.ok(e.instructions.some(i=>/Podróżnym/i.test(i)));
});

test('Routine law-enforcement story at a border crossing is not an operational alert',()=>{
 assert.equal(parseSgArticle(falsePositive,falseUrl,now),null);
});

test('Restored border traffic is retained as an ended informational notice',()=>{
 const e=parseSgArticle(ended,endedUrl,now)!;
 assert.equal(e.lifecycle,'ENDED');
 assert.equal(e.severity,'INFORMATIONAL');
 assert.equal(e.officialWarning,false);
});

test('SG article parser rejects changed contract, future dates and denied URLs',()=>{
 assert.throws(()=>parseSgArticle('<article class="txt">x</article>',opUrl,now),/CONTRACT/);
 assert.throws(()=>parseSgArticle(operational.replace('21.09.2026','31.02.2026'),opUrl,now),/DATE/);
 assert.throws(()=>parseSgArticle(operational,'https://evil.example/pl/aktualnosci/20001,x.html',now),/URL_DENIED/);
});

test('SG adapter scans a bounded recent window and allows an honest empty result',async()=>{
 const calls:string[]=[];
 const data=new Map<string,string>([
  [SG_INDEX,page([opUrl,falseUrl])],
  [SG_INDEX+'?page=1',page([falseUrl])],
  [opUrl,operational],
  [falseUrl,falsePositive],
 ]);
 const batch=await sgAdapter.sync({now,fetchText:async u=>{calls.push(u);const v=data.get(u);if(v===undefined)throw new Error('UNEXPECTED_URL');return v;}});
 assert.equal(batch.pagesFetched,2);
 assert.equal(batch.complete,false);
 assert.equal(batch.coverage,'RECENT_PUBLICATIONS');
 assert.deepEqual(batch.events.map(e=>e.id),['SG-20001']);
 assert.ok(calls.length<=4);

 const empty=await sgAdapter.sync({now,fetchText:async u=>u===SG_INDEX||u===SG_INDEX+'?page=1'?page([falseUrl]):falsePositive});
 assert.deepEqual(empty.events,[]);
});

test('SG source failure keeps last-known-good event and health',async()=>{
 const store=new Store(openDb(undefined,':memory:'));
 await store.init();
 try{
  await initializeSources(store);
  const good={...sgAdapter,sync:async()=>({events:[parseSgArticle(operational,opUrl,now)!],complete:false,coverage:'RECENT_PUBLICATIONS' as const,pagesFetched:2})};
  await ingest(store,[good],async()=>{throw new Error('UNUSED');});
  const first=(await store.health()).find(h=>h.id==='SG')!;
  assert.equal(first.state,'HEALTHY');
  assert.equal((await store.events()).filter(e=>e.sources.some(s=>s.id==='SG')).length,1);

  await ingest(store,[{...good,sync:async()=>{throw new Error('SG_INDEX_CONTRACT_CHANGED');}}],async()=>{throw new Error('UNUSED');});
  const broken=(await store.health()).find(h=>h.id==='SG')!;
  assert.equal(broken.state,'BROKEN');
  assert.equal(broken.lastSuccess,first.lastSuccess);
  assert.equal(broken.errorCode,'SG_INDEX_CONTRACT_CHANGED');
  assert.equal((await store.events()).filter(e=>e.sources.some(s=>s.id==='SG')).length,1);
 }finally{await store.db.close();}
});

test('Broken SG feed does not redefine main physical-safety coverage',()=>{
 const rcb:Health={id:'RCB',name:'RCB',url:'https://www.gov.pl/web/rcb/komunikaty',state:'HEALTHY',lastSuccess:now.toISOString(),lastFailure:null,lastItemTime:null,failureCount:0,responseTime:1,maxAgeSeconds:900,complete:true,enabled:true,lastAttempt:now.toISOString(),coverage:'ACTIVE_WARNINGS'};
 const sg:Health={...rcb,id:'SG',name:'Straż Graniczna',url:SG_INDEX,state:'BROKEN',complete:false,lastFailure:now.toISOString(),errorCode:'SOURCE_HTTP_503'};
 const status=computeStatus([], [rcb,sg], 'PL', now);
 assert.equal(status.coverageState,'COMPLETE_FOR_CONFIGURED_SCOPE');
 assert.equal(status.hazardLevel,'NO_ACTIVE_WARNINGS');
});

test('SG Event survives PostGIS restart and resync',{skip:!process.env.TEST_DATABASE_URL},async()=>{
 const event=parseSgArticle(operational,opUrl,now)!;
 let store=new Store(openDb(process.env.TEST_DATABASE_URL));
 try{
  await store.init();
  const existing=(await store.health()).find(h=>h.id==='SG');
  const health:Health={id:'SG',name:'Straż Graniczna',url:SG_INDEX,state:'HEALTHY',lastSuccess:now.toISOString(),lastFailure:null,lastItemTime:null,failureCount:0,responseTime:1,maxAgeSeconds:3600,complete:false,enabled:true,lastAttempt:now.toISOString(),coverage:'RECENT_PUBLICATIONS',itemCount:1,adapterVersion:sgAdapter.version};
  await store.applySync([event],existing?{...existing,...health}:health);
  await store.db.close();
  store=new Store(openDb(process.env.TEST_DATABASE_URL));await store.init();
  assert.equal((await store.get(event.id))?.eventType,'BORDER');
  await store.applySync([event],health);
  assert.equal((await store.timeline(event.id)).length,1);
 }finally{
  await store.db.run('DELETE FROM event_revisions WHERE event_id=?',[event.id]);
  await store.db.close();
 }
});

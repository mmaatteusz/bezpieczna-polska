import test from 'node:test';
import assert from 'node:assert/strict';
import {classifyServiceIncident,parsePoliceRss,policeAdapter,parsePspArticle,parsePspIndex,pspIncidentsAdapter,POLICE_RSS,PSP_INCIDENTS_INDEX} from '../src/service-incidents-adapter.js';
import {computeStatus,eventSchema,sourceHealth,type Event,type Health} from '../src/domain.js';
import {canCorrelate,correlate} from '../src/correlation.js';
import {Store,openDb} from '../src/store.js';
import {ingest,initializeSources} from '../src/adapters.js';

const now=new Date('2026-09-21T12:00:00Z');
const policeUrl='https://policja.pl/pol/aktualnosci/20001,Duzy-pozar-magazynu.html';
const pspUrl='https://www.gov.pl/web/kgpsp/sokolniki-suche---wypadek-kolejowy';
const rss=(title:string,description:string,url=policeUrl,pub='Mon, 21 Sep 2026 10:00:00 +0200')=>`<?xml version="1.0"?><rss version="2.0"><channel><title>Policja</title><item><title><![CDATA[${title}]]></title><description><![CDATA[${description}]]></description><link>${url}</link><pubDate>${pub}</pubDate></item></channel></rss>`;
const pspArticle=(title:string,body:string,date='21.09.2026')=>`<main><article><h2>${title}</h2><div class="event-date">${date}</div><div class="editor-content"><p>${body}</p></div></article></main>`;
const pspIndex=(url=pspUrl)=>`<main><article><h2>Aktualności</h2><div class="art-prev"><div class="event"><span class="date">21.09.2026</span></div><div class="title"><a href="${new URL(url).pathname}">Zdarzenie</a></div></div></article></main>`;

test('large industrial fire is imported',async()=>{
 const batch=await policeAdapter.sync({now,fetchText:async u=>{assert.equal(u,POLICE_RSS);return rss('Duży pożar magazynu w mieście','Płonie magazyn. Ewakuowano 40 osób, na miejscu działa wiele zastępów.');}});
 assert.equal(batch.events.length,1);assert.equal(batch.events[0].eventType,'FIRE');assert.equal(batch.events[0].officialWarning,false);
 assert.equal(batch.events[0].geometry,null);assert.equal(batch.events[0].latitude,null);assert.equal(batch.events[0].longitude,null);
});

test('explosion is imported',()=>{
 assert.deepEqual(classifyServiceIncident('Wybuch w hali produkcyjnej','Po eksplozji ewakuowano pracowników zakładu.'),{eventType:'EXPLOSION',severity:'HIGH'});
});

test('building disaster and mass evacuation are imported as rescue',()=>{
 assert.equal(classifyServiceIncident('Katastrofa budowlana','Zawalił się budynek. Poszkodowanych zostało 18 osób, trwa akcja ratownicza.')?.eventType,'RESCUE');
});

test('HAZMAT is imported',()=>{
 assert.equal(classifyServiceIncident('Wyciek amoniaku w zakładzie','Wyznaczono strefę zagrożenia i ewakuowano pracowników.')?.eventType,'HAZMAT');
});

for(const [name,title,description] of [
 ['routine police news','Policjanci zatrzymali złodzieja','Mężczyzna odpowie za kradzież w sklepie.'],
 ['arrest','Zatrzymany sprawca oszustw','Podejrzany został tymczasowo aresztowany.'],
 ['recovered car','Odzyskali skradzione auto','Policjanci odzyskali samochód podczas kontroli.'],
 ['smuggling','Udaremnili przemyt','Zabezpieczono nielegalny towar bez wpływu na ruch.'],
 ['historical fire','Rocznica pożaru sprzed 20 lat','Wspominamy duży pożar magazynu i działania służb.'],
 ['education','Szkolenie z pożarów magazynów','Strażacy ćwiczyli działania ratownicze i ewakuację.'],
] as const)test(name+' is rejected',()=>assert.equal(classifyServiceIncident(title,description),null));

test('irrelevant PSP article without publication date is rejected without breaking sync',()=>{
 const html='<main><article><h2>VIII Mistrzostwa Polski Strażaków</h2><div class="editor-content"><p>Relacja z zawodów sportowych i wręczenia pucharów strażakom.</p></div></article></main>';
 assert.equal(parsePspArticle(html,'https://www.gov.pl/web/kgpsp/viii-mistrzostwa-polski-strazakow',now),null);
});

test('PSP event preserves date-only publication and source locality without invented point/time',()=>{
 const e=parsePspArticle(pspArticle('Sokolniki Suche - wypadek kolejowy','Pociągiem podróżowało ponad 100 osób. 8 osób zabrano do szpitala. Na miejscu pracowało blisko 30 zastępów i specjalistyczne grupy ratownictwa.'),pspUrl,now)!;
 assert.ok(e);assert.equal(e.eventType,'RESCUE');assert.equal(e.publicationDate,'2026-09-21');assert.equal(e.publishedAt,null);
 assert.equal(e.locationText,'Sokolniki Suche');assert.equal(e.geometry,null);assert.equal(e.latitude,null);assert.equal(e.longitude,null);
});

test('PSP index fails closed on contract change',()=>{
 assert.deepEqual(parsePspIndex(pspIndex()).urls,[pspUrl]);
 assert.throws(()=>parsePspIndex('<main><article><h2>Aktualności</h2></article></main>'),/CONTRACT_CHANGED/);
});

test('Police RSS fails closed on contract change and does not invent time when missing',()=>{
 assert.throws(()=>parsePoliceRss('<rss><channel></channel></rss>',now),/CONTRACT_CHANGED/);
 const item=parsePoliceRss(rss('Duży pożar magazynu','Ewakuowano budynek i działa wiele zastępów.',policeUrl,''),now)[0];
 assert.equal(item.publishedAt,null);assert.equal(item.publicationDate,null);
});

test('article correction appends revision and resync without change is idempotent',async()=>{
 const db=openDb(undefined,':memory:'),store=new Store(db);await store.init();
 try{
  const base=parsePspArticle(pspArticle('Sokolniki Suche - wypadek kolejowy','Pociągiem podróżowało ponad 100 osób. 8 osób zabrano do szpitala. Na miejscu pracowało blisko 30 zastępów i specjalistyczne grupy ratownictwa.'),pspUrl,now)!;
  const health:Health={id:'PSP_INCIDENTS',name:'PSP',url:PSP_INCIDENTS_INDEX,state:'HEALTHY',lastSuccess:now.toISOString(),lastFailure:null,lastItemTime:null,failureCount:0,responseTime:1,maxAgeSeconds:3600,complete:false,enabled:true,lastAttempt:now.toISOString(),coverage:'RECENT_PUBLICATIONS',itemCount:1,adapterVersion:pspIncidentsAdapter.version};
  await store.applySync([base],health);await store.applySync([base],health);assert.equal((await store.timeline(base.id)).length,1);
  const corrected=parsePspArticle(pspArticle('Sokolniki Suche - wypadek kolejowy','Aktualizacja. Pociągiem podróżowało ponad 100 osób. 9 osób zabrano do szpitala. Na miejscu pracowało blisko 30 zastępów i specjalistyczne grupy ratownictwa.'),pspUrl,now)!;
  await store.applySync([corrected],health);assert.equal((await store.timeline(base.id)).length,2);assert.equal((await store.get(base.id))!.revision,2);
 }finally{await db.close();}
});

test('service source STALE and DOWN mean source coverage loss, not regional danger or false green input',()=>{
 const police:Health={id:'POLICE',name:'Policja',url:'https://policja.pl/pol/aktualnosci',state:'HEALTHY',lastSuccess:'2026-09-21T08:00:00Z',lastFailure:null,lastItemTime:null,failureCount:0,responseTime:1,maxAgeSeconds:3600,complete:false,enabled:true,lastAttempt:now.toISOString(),coverage:'RECENT_PUBLICATIONS'};
 assert.equal(sourceHealth([police],now)[0].state,'STALE');
 const broken={...police,state:'BROKEN' as const,lastSuccess:now.toISOString(),lastFailure:now.toISOString()};
 assert.equal(sourceHealth([broken],now)[0].state,'BROKEN');
 const status=computeStatus([], [broken], '14', now);
 assert.equal(status.hazardLevel,'UNKNOWN');
});

test('changed Police source contract keeps last-known-good event and marks source broken',async()=>{
 const store=new Store(openDb(undefined,':memory:'));await store.init();
 try{
  await initializeSources(store);
  const good={...policeAdapter,minSyncIntervalSeconds:0,sync:async()=>({events:[eventSchema.parse({id:'POLICE-fixture',title:'Duży pożar magazynu',description:'Ewakuowano 40 osób.',eventType:'FIRE',severity:'HIGH',verification:'CONFIRMED',lifecycle:'UNKNOWN',messageContext:'ACTUAL',regions:['14'],geographicScope:'REGIONAL',publishedAt:null,publicationDate:'2026-09-21',retrievedAt:now.toISOString(),validFrom:null,validTo:null,sources:[{id:'POLICE',name:'Policja',url:policeUrl,tier:1}],instructions:[],officialWarning:false,reviewed:false,revision:1,correction:null,latitude:null,longitude:null,geometry:null,locationText:'Warszawa',areaPrecision:'EXACT',adapterVersion:policeAdapter.version,sourceContentHash:'a'.repeat(64),isDemo:false})],complete:false,coverage:'RECENT_PUBLICATIONS' as const,pagesFetched:1})};
  await ingest(store,[good],async()=>{throw new Error('UNUSED');});
  const first=(await store.health()).find(h=>h.id==='POLICE')!;assert.equal(first.state,'HEALTHY');
  await ingest(store,[{...good,sync:async()=>{throw new Error('POLICE_RSS_CONTRACT_CHANGED');}}],async()=>{throw new Error('UNUSED');});
  const after=(await store.health()).find(h=>h.id==='POLICE')!;assert.equal(after.state,'BROKEN');assert.equal(after.lastSuccess,first.lastSuccess);
  assert.equal((await store.get('POLICE-fixture'))?.eventType,'FIRE');
 }finally{await store.db.close();}
});

function report(source:string,patch:Partial<Event>={}):Event{return eventSchema.parse({
 id:source+'-'+Math.random(),title:'Duży pożar magazynu w Bydgoszczy',description:'Duży pożar magazynu w Bydgoszczy. Ewakuowano pracowników i zamknięto teren.',
 eventType:'FIRE',severity:'HIGH',verification:'CONFIRMED',lifecycle:'UNKNOWN',messageContext:'ACTUAL',regions:['04'],geographicScope:'REGIONAL',
 publishedAt:'2026-09-21T09:00:00Z',publicationDate:'2026-09-21',retrievedAt:now.toISOString(),validFrom:null,validTo:null,
 sources:[{id:source,name:source,url:'https://www.gov.pl/',tier:1}],instructions:[],officialWarning:source==='RCB',reviewed:false,revision:1,correction:null,
 latitude:null,longitude:null,geometry:null,locationText:'Bydgoszcz',areaPrecision:'EXACT',isDemo:false,...patch
});}

test('Police/PSP reports can correlate with RCB/RSO/WCZK without verification promotion',()=>{
 const events=[report('RCB'),report('POLICE'),report('PSP_INCIDENTS'),report('RSO'),report('WCZK-04')];
 const groups=correlate(events);assert.equal(groups.length,1);assert.equal(groups[0].sourceCount,5);
 assert.ok(events.every(e=>e.verification==='CONFIRMED'));
});
test('different service incidents in different places never correlate',()=>{
 assert.equal(canCorrelate(report('POLICE'),report('PSP_INCIDENTS',{locationText:'Toruń',description:'Duży pożar magazynu w Toruniu. Ewakuowano pracowników i zamknięto teren.'})),false);
});
test('complete-link still blocks transitive false-positive merge',()=>{
 const a=report('RCB'),b=report('POLICE'),c=report('PSP_INCIDENTS',{locationText:'Toruń',description:'Duży pożar magazynu w Toruniu. Ewakuowano pracowników i zamknięto teren.'});
 assert.equal(correlate([a,b,c]).length,2);
});
test('large service incident alone cannot raise regional status',()=>{
 const e=report('PSP_INCIDENTS',{officialWarning:false,lifecycle:'ACTIVE'});
 const h:Health={id:'PSP_INCIDENTS',name:'PSP',url:PSP_INCIDENTS_INDEX,state:'HEALTHY',lastSuccess:now.toISOString(),lastFailure:null,lastItemTime:null,failureCount:0,responseTime:1,maxAgeSeconds:3600,complete:false,enabled:true,lastAttempt:now.toISOString(),coverage:'RECENT_PUBLICATIONS'};
 assert.notEqual(computeStatus([e],[h],'04',now).hazardLevel,'ACTIVE_DANGER');
});

test('PSP adapter bounded sync rejects educational posts and imports operational incident',async()=>{
 const data=new Map<string,string>([
  [PSP_INCIDENTS_INDEX,pspIndex()],
  [pspUrl,pspArticle('Sokolniki Suche - wypadek kolejowy','Pociągiem podróżowało ponad 100 osób. 8 osób zabrano do szpitala. Na miejscu pracowało blisko 30 zastępów i specjalistyczne grupy ratownictwa.')],
 ]);
 const batch=await pspIncidentsAdapter.sync({now,fetchText:async u=>{const v=data.get(u);if(v===undefined)throw new Error('UNEXPECTED_URL '+u);return v;}});
 assert.equal(batch.events.length,1);assert.equal(batch.complete,false);assert.equal(batch.coverage,'RECENT_PUBLICATIONS');
});

test('service event survives PostGIS restart and resync',{skip:!process.env.TEST_DATABASE_URL},async()=>{
 const event=report('PSP_INCIDENTS',{id:'PSP_INCIDENTS-postgis-'+Date.now(),officialWarning:false});
 let store=new Store(openDb(process.env.TEST_DATABASE_URL));
 const health:Health={id:'PSP_INCIDENTS',name:'PSP',url:PSP_INCIDENTS_INDEX,state:'HEALTHY',lastSuccess:now.toISOString(),lastFailure:null,lastItemTime:null,failureCount:0,responseTime:1,maxAgeSeconds:3600,complete:false,enabled:true,lastAttempt:now.toISOString(),coverage:'RECENT_PUBLICATIONS'};
 try{
  await store.init();await store.applySync([event],health);await store.db.close();
  store=new Store(openDb(process.env.TEST_DATABASE_URL));await store.init();assert.equal((await store.get(event.id))?.eventType,'FIRE');
  await store.applySync([event],health);assert.equal((await store.timeline(event.id)).length,1);
 }finally{await store.db.run('DELETE FROM event_revisions WHERE event_id=?',[event.id]);await store.db.close();}
});

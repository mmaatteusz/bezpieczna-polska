import {test} from 'node:test';
import assert from 'node:assert/strict';
import {mkdtempSync,rmSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {correlate,canCorrelate} from '../src/correlation.js';
import {eventSchema,computeStatus,sourceHealth,type Event,type Health} from '../src/domain.js';
import {Store,openDb} from '../src/store.js';
import {buildApp} from '../src/app.js';

const now=new Date('2026-09-21T12:00:00Z');
// Explicit synthetic fixtures only. Never loaded by production adapters.
export function report(source:string,patch:Partial<Event>={}):Event{return eventSchema.parse({id:source+'-fixture',title:'Powódź w Bydgoszczy',description:'Powódź w Bydgoszczy. Zalane ulice w centrum miasta, unikaj przechodzenia przez wezbraną wodę.',eventType:'WEATHER',severity:'HIGH',verification:'CONFIRMED',lifecycle:'ACTIVE',messageContext:'ACTUAL',regions:['04'],geographicScope:'REGIONAL',publishedAt:'2026-09-21T09:00:00Z',retrievedAt:now.toISOString(),validFrom:'2026-09-21T09:00:00Z',validTo:'2026-09-21T23:00:00Z',sources:[{id:source,name:source,url:'https://www.gov.pl/',tier:1}],instructions:[],officialWarning:true,reviewed:false,revision:1,correction:null,latitude:null,longitude:null,locationText:'Bydgoszcz',...patch});}
const health:Health={id:'WCZK-04',name:'WCZK',url:'https://www.gov.pl/',regionId:'04',state:'HEALTHY',lastSuccess:now.toISOString(),lastFailure:null,lastItemTime:null,failureCount:0,responseTime:1,maxAgeSeconds:900,complete:true};

test('RCB and RSO: one incident, preserve both events',()=>{const events=[report('RCB'),report('RSO')],copy=JSON.stringify(events),groups=correlate(events);assert.equal(groups.length,1);assert.equal(groups[0].sourceCount,2);assert.equal(groups[0].relatedEventIds.length,2);assert.equal(JSON.stringify(events),copy);});
test('RCB RSO WCZK: RSO and WCZK are one publisher family',()=>{const events=[report('RCB'),report('RSO'),report('WCZK-04')];assert.equal(correlate(events).length,1);assert.equal(correlate(events)[0].sourceCount,2);assert.deepEqual(correlate(events)[0].sourceIds,['RCB','RSO','WCZK-04']);assert.deepEqual(correlate([...events].reverse()),correlate(events));});
test('RSO plus direct WCZK mirror is one independent source',()=>{const group=correlate([report('RSO'),report('WCZK-04')])[0];assert.equal(group.sourceCount,1);assert.equal(group.confirmedSourceCount,1);});
test('similar warnings in different provinces never join',()=>assert.equal(correlate([report('RCB'),report('RSO',{regions:['06']})]).length,2));
test('different hazards in the same city never join',()=>assert.equal(correlate([report('RCB'),report('RSO',{title:'Pożar magazynu w Bydgoszczy',description:'Pożar magazynu w Bydgoszczy. Omijaj okolice magazynu i nie otwieraj okien.',eventType:'FIRE'})]).length,2));
test('same hazard city and time but different streets/numbers remain separate',()=>assert.equal(canCorrelate(report('RCB',{description:'Powódź Bydgoszcz ulica Gdańska 10 zalane budynki i piwnice'}),report('RSO',{description:'Powódź Bydgoszcz ulica Gdańska 20 zalane budynki i piwnice'})),false));
test('unknown geography, time, disjoint validity, exercises and same-source copies do not join',()=>{for(const patch of [{regions:[]},{regions:['PL']},{validFrom:null,publishedAt:null},{validFrom:'2026-09-22T09:00:00Z',validTo:'2026-09-22T23:00:00Z'},{messageContext:'EXERCISE'}] as Partial<Event>[]){assert.equal(canCorrelate(report('RCB'),report('RSO',patch)),false);}assert.equal(canCorrelate(report('RCB'),report('RCB',{id:'another'})),false);});
test('ambiguous candidates do not merge and complete-link prevents transitive joining',()=>{const a=report('RCB'),b=report('RCB',{id:'RCB-second'}),c=report('RSO');const result=correlate([a,b,c]);assert.equal(result.length,3);});
test('three sources never triple status; unverified RSO is not promoted',()=>{const events=[report('RCB'),report('RSO',{verification:'UNVERIFIED'}),report('WCZK-04')];const s=computeStatus(events,[health],'04',now);assert.equal(s.hazardLevel,'CAUTION');assert.equal(s.incidentCount,1);assert.equal(s.supportingEventIds.length,1);assert.equal(s.supportingIncidents[0].sourceCount,2);assert.equal(s.supportingIncidents[0].confirmedSourceCount,2);assert.equal(events[1].verification,'UNVERIFIED');});
test('WCZK informational bulletin cannot make danger RED',()=>assert.notEqual(computeStatus([report('WCZK-04',{severity:'INFORMATIONAL'})],[health],'04',now).hazardLevel,'ACTIVE_DANGER'));
for(const [name,h] of [['STALE',{...health,lastSuccess:'2020-01-01T00:00:00Z'}],['DOWN',{...health,state:'BROKEN' as const}],['NOT_CONFIGURED',{...health,state:'NOT_CONFIGURED' as const,enabled:false}]] as const){test(`${name} means missing coverage, not safety`,()=>{const s=computeStatus([],[h],'04',now);assert.equal(s.coverageState,'UNAVAILABLE');assert.equal(s.hazardLevel,'UNKNOWN');if(name==='STALE')assert.equal(sourceHealth([h],now)[0].state,'STALE');});}
test('other WCZK province does not degrade this region coverage',()=>assert.equal(computeStatus([],[health,{...health,id:'WCZK-06',regionId:'06',state:'BROKEN'}],'04',now).coverageState,'COMPLETE_FOR_CONFIGURED_SCOPE'));

test('extension, area correction, ending and retraction retain group and append-only history across restart',async()=>{
 const dir=mkdtempSync(join(tmpdir(),'bp-correlate-')),path=join(dir,'test.db');let db=openDb(undefined,path),s=new Store(db);
 try{
  await s.init();const a=report('RCB'),b=report('RSO'),c=report('WCZK-04');await s.applySync([a,b,c],health);
  const before=(await s.snapshot()).incidents[0],id=before.id;
  await s.applySync([a,b,c],health);assert.equal((await s.incidentHistory(id)).length,1,'resync is idempotent');
  await s.applySync([{...c,validTo:'2026-09-22T23:00:00Z'}],health);
  assert.equal((await s.incidents())[0].id,id);assert.equal((await s.timeline(c.id)).length,2);
  await s.applySync([{...c,regions:['06'],locationText:'Lublin',correction:'Sprostowanie obszaru komunikatu'}],health);
  assert.equal((await s.incidents())[0].hasConflictingReports,true);
  await s.applySync([{...c,lifecycle:'ENDED'}],health);
  const still=await s.snapshot();assert.equal(computeStatus(still.events,[health],'04',now,still.incidents).hazardLevel,'CAUTION','one publisher cannot cancel other warnings');
  await s.applySync([{...c,lifecycle:'CANCELLED',verification:'REFUTED',correction:'Oficjalne sprostowanie'}],health);
  const history=await s.incidentHistory(id);assert.equal(history.length,5);assert.equal((await s.timeline(c.id)).length,5);
  await db.close();db=openDb(undefined,path);s=new Store(db);await s.init();
  assert.equal((await s.incidents())[0].id,id);assert.equal((await s.incidentHistory(id)).length,5);
  const app=await buildApp(s);try{const snapshot=(await app.inject('/v1/snapshot?regionId=04')).json();assert.equal(snapshot.incidents[0].sourceCount,2);assert.equal(snapshot.incidents[0].reports.length,3);assert.equal(snapshot.events.length,3);const timeline=(await app.inject(`/v1/incidents/${id}/timeline`)).json();assert.equal(timeline.length,7);assert.ok(timeline.some((r:any)=>r.changes.some((ch:any)=>ch.field==='validTo')));}finally{await app.close();}
 }finally{await db.close();rmSync(dir,{recursive:true,force:true});}
});

test('PostGIS persists correlation and rollback leaves event and group unchanged',{skip:!process.env.TEST_DATABASE_URL},async()=>{
 const db=openDb(process.env.TEST_DATABASE_URL),s=new Store(db),suffix=Date.now().toString();const a=report('RCB',{id:'correlation-RCB-'+suffix}),b=report('RSO',{id:'correlation-RSO-'+suffix});
 try{await s.init();await s.applySync([a,b],health);const id=(await s.incidents()).find(i=>i.relatedEventIds.includes(a.id))!.id;assert.equal((await new Store(db).incidents()).find(i=>i.id===id)!.sourceCount,2);
  await assert.rejects(s.applySync([{...a,validTo:'2026-09-23T00:00:00Z'},{...b,geometry:{type:'Polygon',coordinates:[[[0,0],[1,1],[0,1],[1,0],[0,0]]]}}],health));assert.equal((await s.get(a.id))!.revision,1);assert.equal((await s.incidentHistory(id)).length,1);
  await db.run('DELETE FROM incident_revisions WHERE incident_id=?',[id]);
 }finally{for(const id of [a.id,b.id])await db.run('DELETE FROM event_revisions WHERE event_id=?',[id]);await db.close();}
});

test('near-identical boilerplate without exact local area cannot merge different places',()=>{const text='Powódź. '+ 'Pozostań w domu, zachowaj ostrożność, zabezpiecz mienie i unikaj podróży. '.repeat(20);assert.equal(canCorrelate(report('RCB',{title:'Powódź Bydgoszcz',description:text,locationText:null}),report('RSO',{title:'Powódź Toruń',description:text,locationText:null})),false);});
test('similar content requires exact matching local area and rejects conflicting geometry',()=>{const a=report('RCB',{areaPrecision:'EXACT'}),b=report('RSO',{areaPrecision:'EXACT',description:a.description+' Uważaj.'});assert.equal(canCorrelate(a,b),true);assert.equal(canCorrelate({...a,geometry:{type:'Point',coordinates:[18,53]}},{...b,geometry:{type:'Point',coordinates:[19,53]}}),false);});
test('exact city and high similarity cannot hide different streets or a negation',()=>{
 const common='Powódź w Bydgoszczy. Zalane budynki i piwnice, zachowaj ostrożność, zabezpiecz mienie i unikaj podróży. ';
 for(const [left,right] of [['Ulica Gdańska','Ulica Dworcowa'],['Most jest przejezdny','Most nie jest przejezdny']]){
  assert.equal(canCorrelate(report('RCB',{areaPrecision:'EXACT',description:common+left}),report('RSO',{areaPrecision:'EXACT',description:common+right})),false);
 }
});

import {createHash} from 'node:crypto';
import type {Event} from './domain.js';

export const CORRELATION_VERSION='1.0.0';
export type Incident={eventRevisions:Record<string,number>;id:string;relatedEventIds:string[];primaryEventId:string;sourceIds:string[];sourceCount:number;confirmedSourceCount:number;hasConflictingReports:boolean;revision:number;rulesetVersion:string};
export const normalize=(s:string)=>s.normalize('NFD').replace(/\p{M}/gu,'').replace(/ł/g,'l').replace(/Ł/g,'L').toLowerCase().replace(/[^a-z0-9]+/g,' ').trim();
const physicalEligible=(e:Event)=>!e.isDemo&&!e.securityLevel&&e.sources.some(s=>s.id==='RCB'||s.id==='RSO'||s.id==='POLICE'||s.id==='PSP_INCIDENTS'||/^WCZK-\d{2}$/.test(s.id));
const cyberEligible=(e:Event)=>!e.isDemo&&!e.securityLevel&&e.eventType==='CYBER'&&e.sources.some(s=>s.id==='CERT'||s.id==='CSIRT_GOV');
const eligible=(e:Event)=>physicalEligible(e)||cyberEligible(e);
const families:(readonly [string,RegExp])[]=[['flood',/powodz|podtop|wezbran/],['wind',/siln\w* wiatr|wichur/],['storm',/burz/],['drought',/susza|suszy/],['fire',/pozar/],['explosion',/wybuch|eksplozj/],['hazmat',/hazmat|chemiczn|amoniak|chlor|skazeni/],['rescue',/ratownicz|katastrof|zawali|wypadek kolejow/],['public_safety',/strzelanin|napastnik|bombow/],['outage',/awari\w* (prad|energet)|przerw\w* w dostaw\w* (prad|energ)/],['water',/wod\w* (do spozycia|niezdatn)|zanieczyszcz\w* wod/]];
function kind(e:Event){
 const t=normalize(e.title+' '+e.description),matches=families.filter(([,re])=>re.test(t));
 if(matches.length>1)return null; // compound alerts are not reduced to one hazard
 if(matches.length===1)return matches[0][0];
 return ['FIRE','EXPLOSION','HAZMAT','RESCUE','PUBLIC_SAFETY','OUTAGE','EVACUATION'].includes(e.eventType)?e.eventType:null;
}
const regionKey=(e:Event)=>[...new Set(e.regions)].sort().join(',');
function interval(e:Event):[number,number]|null{
 const start=e.validFrom??e.publishedAt,end=e.validTo;
 if(start){
  const a=Date.parse(start),b=end?Date.parse(end):a+6*3600000;
  return Number.isFinite(a)&&Number.isFinite(b)&&b>=a?[a,b]:null;
 }
 // Keep publicationDate date-only on the Event. A whole-day window is used
 // only as coarse correlation evidence and never exposed as a source timestamp.
 if(e.publicationDate){
  const a=Date.parse(e.publicationDate+'T00:00:00Z');
  return Number.isFinite(a)?[a,a+86400000]:null;
 }
 return null;
}
function tokens(e:Event){return new Set(normalize(e.title+' '+e.description).split(' ').filter(w=>w.length>2&&!['alert','rcb','rso','wczk','ostrzezenie','uwaga','komunikat','wojewodztwo'].includes(w)));}
function similarity(a:Set<string>,b:Set<string>){const common=[...a].filter(t=>b.has(t)).length;return common/(a.size+b.size-common||1);}
function numbers(e:Event){return (normalize(e.title+' '+e.description).match(/\b\d+\b/g)??[]).sort().join(',');}
// Only publisher labels and a standalone attention word may differ. A high
// token score must never hide a changed street, object, or negation.
function incidentContent(e:Event){return normalize(e.title+' '+e.description).split(' ').filter(w=>!['rcb','rso','wczk','cert','csirt','gov','alert','komunikat','uwaga','uwazaj'].includes(w)).join(' ');}
function cves(e:Event){return new Set((e.title+' '+e.description).toUpperCase().match(/CVE-\d{4}-\d{4,7}/g)??[]);}
function canCorrelateCyber(a:Event,b:Event){
 if(!cyberEligible(a)||!cyberEligible(b)||!a.publishedAt||!b.publishedAt)return false;
 if(Math.abs(Date.parse(a.publishedAt)-Date.parse(b.publishedAt))>72*3600000)return false;
 const ac=cves(a),bc=cves(b),shared=[...ac].filter(x=>bc.has(x));
 if(ac.size||bc.size)return shared.length>0;
 if(numbers(a)!==numbers(b))return false;
 const at=normalize(a.title),bt=normalize(b.title);
 if(at===bt)return true;
 const ta=tokens(a),tb=tokens(b);
 return Math.min(ta.size,tb.size)>=6&&similarity(ta,tb)>=0.9;
}

/** Complete-link matching, no fuzzy geography, no transitive A-B-C merge. */
export function canCorrelate(a:Event,b:Event):boolean{
 if(!eligible(a)||!eligible(b)||a.id===b.id)return false;
 if(a.sources.some(s=>b.sources.some(t=>s.id===t.id)))return false;
 if(['EXERCISE','TEST'].includes(a.messageContext)||['EXERCISE','TEST'].includes(b.messageContext))return false;
 if(cyberEligible(a)||cyberEligible(b))return canCorrelateCyber(a,b);
 if(!a.regions.length||a.regions.includes('PL')||regionKey(a)!==regionKey(b))return false;
 const ak=kind(a),bk=kind(b);if(!ak||ak!==bk)return false;
 if(a.eventType!=='OTHER'&&b.eventType!=='OTHER'&&a.eventType!==b.eventType)return false;
 const ai=interval(a),bi=interval(b);if(!ai||!bi||Math.max(ai[0],bi[0])>=Math.min(ai[1],bi[1]))return false;
 if(Math.abs(ai[0]-bi[0])>12*3600000)return false;
 const al=normalize(a.locationText??''),bl=normalize(b.locationText??'');
 if(al&&bl&&al!==bl)return false;
 const coarseA=!a.validFrom&&!a.publishedAt&&!!a.publicationDate,coarseB=!b.validFrom&&!b.publishedAt&&!!b.publicationDate;
 if((coarseA||coarseB)&&(!al||!bl||al!==bl))return false;
 // A common city is not enough: different numbers/streets/incident details veto.
 if(numbers(a)!==numbers(b))return false;
 if(a.geometry&&b.geometry&&JSON.stringify(a.geometry)!==JSON.stringify(b.geometry))return false;
 const exactArea=al&&bl&&a.areaPrecision==='EXACT'&&b.areaPrecision==='EXACT';
 if(exactArea&&incidentContent(a)!==incidentContent(b))return false;
 if(!exactArea&&normalize(a.title+' '+a.description)!==normalize(b.title+' '+b.description))return false;
 const score=similarity(tokens(a),tokens(b));
 return score>=(exactArea?0.78:1)&&Math.min(tokens(a).size,tokens(b).size)>=5;
}
const severity:Record<Event['severity'],number>={CRITICAL:4,HIGH:3,NORMAL:2,INFORMATIONAL:1};
export function choosePrimary(events:Event[],now=new Date()):Event{
 const rank=(e:Event)=>[e.lifecycle==='ACTIVE'&&(!e.validTo||Date.parse(e.validTo)>+now)?1:0,e.verification==='CONFIRMED'?1:0,severity[e.severity]];
 return [...events].sort((a,b)=>{const ar=rank(a),br=rank(b);return br[0]-ar[0]||br[1]-ar[1]||br[2]-ar[2]||a.id.localeCompare(b.id);})[0];
}
export function describeIncident(id:string,events:Event[],revision=1):Incident{
 const sourceIds=[...new Set(events.flatMap(e=>e.sources.map(s=>s.id)))].sort();
 return {eventRevisions:Object.fromEntries(events.map(e=>[e.id,e.revision]).sort(([a],[b])=>String(a).localeCompare(String(b)))),id,relatedEventIds:events.map(e=>e.id).sort(),primaryEventId:choosePrimary(events,new Date(0)).id,sourceIds,sourceCount:sourceIds.length,confirmedSourceCount:new Set(events.filter(e=>e.verification==='CONFIRMED').flatMap(e=>e.sources.map(s=>s.id))).size,hasConflictingReports:new Set(events.map(e=>e.lifecycle)).size>1||new Set(events.map(regionKey)).size>1||new Set(events.map(e=>e.validTo)).size>1||new Set(events.map(e=>normalize(e.locationText??''))).size>1||events.some(e=>['REFUTED','DISPUTED'].includes(e.verification)),revision,rulesetVersion:CORRELATION_VERSION};
}
/** Existing memberships are durable. Later corrections remain visible in the same history.
 * New events join only one unambiguous group and must match EVERY current member.
 * Existing groups are never silently coalesced. Same ordered input gives same output. */
export function correlate(events:Event[],previous:Incident[]=[]):Incident[]{
 const byId=new Map(events.filter(eligible).map(e=>[e.id,e]));
 const groups=previous.map(p=>({id:p.id,revision:p.revision,events:p.relatedEventIds.flatMap(id=>byId.has(id)?[byId.get(id)!]:[])})).filter(g=>g.events.length);
 const assigned=new Set(groups.flatMap(g=>g.events.map(e=>e.id)));
 for(const e of [...byId.values()].sort((a,b)=>a.id.localeCompare(b.id))){
  if(assigned.has(e.id))continue;
  const candidates=groups.filter(g=>g.events.every(member=>canCorrelate(e,member)));
  if(candidates.length===1)candidates[0].events.push(e);
  else groups.push({id:'INC-'+createHash('sha256').update(e.id).digest('hex').slice(0,24),revision:1,events:[e]});
 }
 return groups.map(g=>describeIncident(g.id,g.events,g.revision)).sort((a,b)=>a.id.localeCompare(b.id));
}

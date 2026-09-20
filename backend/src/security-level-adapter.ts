import * as cheerio from 'cheerio';
import {createHash} from 'node:crypto';
import {DateTime} from 'luxon';
import {eventSchema,type Event} from './domain.js';
import {securityLevelSchema,type SecurityLevel} from './security-level.js';
import type {SourceAdapter} from './source-adapter.js';
export const LEVELS_INDEX='https://www.gov.pl/web/rcb/komunikaty';
const VERSION='security-levels-html/1.0.0';
const clean=(v:string)=>v.replace(/\s+/g,' ').trim();
const months=['stycznia','lutego','marca','kwietnia','maja','czerwca','lipca','sierpnia','września','października','listopada','grudnia'];
const stems:Record<string,string>={'02':'dolnośląsk','04':'kujawsko-pomorsk','06':'lubelsk','08':'lubusk','10':'łódzk','12':'małopolsk','14':'mazowieck','16':'opolsk','18':'podkarpack','20':'podlask','22':'pomorsk','24':'śląsk','26':'świętokrzysk','28':'warmińsko-mazursk','30':'wielkopolsk','32':'zachodniopomorsk'};
function safeUrl(href:string,base=LEVELS_INDEX){const u=new URL(href,base);if(u.origin!=='https://www.gov.pl'||!u.pathname.startsWith('/web/rcb/')||u.username||u.password)throw new Error('LEVELS_URL_DENIED');u.hash='';return u.href;}
export function parseLevelsIndex(html:string,url=LEVELS_INDEX){
 const $=cheerio.load(html),rows=$('article .art-prev > ul > li');
 if(clean($('article h2').first().text())!=='Komunikaty'||!rows.length)throw new Error('LEVELS_INDEX_CONTRACT_CHANGED');
 const links:{url:string;date:string}[]=[];const dates:string[]=[];
 rows.each((_,row)=>{const r=$(row),date=DateTime.fromFormat(clean(r.find('.date').text()),'dd.MM.yyyy',{zone:'Europe/Warsaw'});if(!date.isValid)throw new Error('LEVELS_INDEX_DATE_INVALID');dates.push(date.toISODate()!);
 const a=r.find('.title a');if(a.length!==1)throw new Error('LEVELS_INDEX_CONTRACT_CHANGED');
 if(/stopni\p{L}*\s+alarmow|(?:ALFA|BRAVO|CHARLIE|DELTA)/iu.test(a.text()))links.push({url:safeUrl(a.attr('href')!,url),date:date.toISODate()!});});
 const href=$('#js-pagination-page-next').attr('href');let next:string|null=null;
 if(href){next=safeUrl(href,url);const u=new URL(next);if(u.pathname!=='/web/rcb/komunikaty'||!/^\d+$/.test(u.searchParams.get('page')??''))throw new Error('LEVELS_PAGINATION_CHANGED');}
 return {links,oldest:dates.sort()[0],next};
}
function validity(text:string,kind:'od'|'do'){
 const pattern=new RegExp(`${kind} (?:dnia )?(\\d{1,2}) (${months.join('|')}) (\\d{4}) (?:r\\.|roku),? ${kind} godz\\. (\\d{2})[.:](\\d{2})`,'iu');
 const m=text.match(pattern);if(!m)throw new Error('LEVELS_VALIDITY_UNPARSED');
 const d=DateTime.fromObject({year:+m[3],month:months.indexOf(m[2].toLowerCase())+1,day:+m[1],hour:+m[4],minute:+m[5]},{zone:'Europe/Warsaw'});
 if(!d.isValid||d.getPossibleOffsets().length!==1)throw new Error('LEVELS_VALIDITY_INVALID');
 return (kind==='do'?d.endOf('minute'):d).toUTC().toISO()!;
}
export function parseLevelsArticle(html:string,url:string,now=new Date()):Event[]{
 const canonical=safeUrl(url),$=cheerio.load(html),article=$('article#main-content'),body=article.find('.editor-content');
 const title=clean(article.find('h2').first().text()),date=DateTime.fromFormat(clean(article.find('.event-date').text()),'dd.MM.yyyy',{zone:'Europe/Warsaw'});
 if(article.length!==1||body.length!==1||!date.isValid||! /stopni\p{L}*\s+alarmow/iu.test(title)||! /Prezes Rady Ministrów/.test(body.text()))throw new Error('LEVELS_ARTICLE_CONTRACT_CHANGED');
 if(date.toMillis()>+now+86400000)throw new Error('LEVELS_PUBLICATION_FUTURE');
 // An unfamiliar cancellation/correction must never silently leave an old decision "fresh".
 if(/odwoł|uchyl|zmian/iu.test(title+' '+body.text()))throw new Error('LEVELS_DECISION_REQUIRES_REVIEW');
 const rows=body.find('li').filter((_,el)=>/stopni|stopień|\bnr\s*\d/iu.test($(el).text()));
 if(!rows.length||rows.length>50)throw new Error('LEVELS_DECISIONS_MISSING');
 const dedup=new Map<string,Event>();
 rows.each((_,el)=>{
  const text=clean($(el).text()),order=text.match(/^nr\s+(\d+)\s+z dnia\s+\d{1,2}\s+\p{L}+\s+(\d{4})/iu);
  const tokens=[...text.matchAll(/\(stopień\s+(ALFA|BRAVO|CHARLIE|DELTA)(?:[-– ](CRP))?\)/gu)];
  if(!order||tokens.length!==1)throw new Error('LEVELS_DECISION_UNPARSED');
  const token=tokens[0],type=token[2]?'CRP':'PHYSICAL',level=token[1] as SecurityLevel['level'];
  const area=text.slice(token.index!+token[0].length).split(/,?\s*obowiązuje\s+od/iu)[0].trim();
  let scope:SecurityLevel['scope'],regions:string[];
  if(/poza granicami Rzeczypospolitej Polskiej/.test(area)&&/infrastruktur/.test(area)){scope='EXTRATERRITORIAL_INFRASTRUCTURE';regions=[];}
  else if(/linii kolejowych|infrastruktur/.test(area)){scope='INFRASTRUCTURE';regions=/województw/.test(area)?Object.entries(stems).filter(([,s])=>new RegExp(`(?<![\\p{L}-])${s}\\p{L}*`,'iu').test(area)).map(([id])=>id):['PL'];}
  else if(/^na całym terytorium Rzeczypospolitej Polskiej\s*,?$/.test(area)){scope='NATIONAL';regions=['PL'];}
  else if(/województw/.test(area)){scope='REGIONAL';regions=Object.entries(stems).filter(([,s])=>new RegExp(`(?<![\\p{L}-])${s}\\p{L}*`,'iu').test(area)).map(([id])=>id);}
  else throw new Error('LEVELS_SCOPE_UNPARSED');
  if(scope!=='EXTRATERRITORIAL_INFRASTRUCTURE'&&!regions.length)throw new Error('LEVELS_REGION_UNPARSED');
  const rawSourceId=`PRM/${order[2]}/${order[1]}`,id=`LEVELS-PRM-${order[2]}-${order[1]}`;
  const validFrom=validity(text,'od'),validTo=validity(text,'do');
  const securityLevel=securityLevelSchema.parse({id,level,type,scope,area:area.replace(/,$/,''),description:text,regions,geometry:null,validFrom,validTo,issuedBy:'Prezes Rady Ministrów',sourceUrl:canonical,publishedAt:date.toISODate(),updatedAt:null,rawSourceId,isActive:Date.parse(validFrom)<=+now&&Date.parse(validTo)>=+now});
  const event=eventSchema.parse({id,title:level+(type==='CRP'?'-CRP':'')+' — '+securityLevel.area,description:text,eventType:type==='CRP'?'CYBER':'OTHER',severity:'INFORMATIONAL',verification:'CONFIRMED',lifecycle:'SCHEDULED',messageContext:'ACTUAL',regions,geographicScope:scope==='NATIONAL'?'NATIONAL':scope==='REGIONAL'?'REGIONAL':'UNKNOWN',publishedAt:null,publicationDate:date.toISODate(),retrievedAt:now.toISOString(),validFrom,validTo,sources:[{id:'LEVELS',name:'Stopnie alarmowe RP — RCB',url:canonical,tier:1}],instructions:[],officialWarning:false,reviewed:false,revision:1,correction:null,latitude:null,longitude:null,geometry:null,adapterVersion:VERSION,sourceContentHash:createHash('sha256').update(html).digest('hex'),securityLevel:{...securityLevel,isActive:false}});
  // Activity is evaluated at response time; clock passage never creates revisions.
  const previous=dedup.get(id);if(previous&&JSON.stringify(previous)!==JSON.stringify(event))throw new Error('LEVELS_CONFLICTING_DECISION');dedup.set(id,event);
 });
 return [...dedup.values()];
}
export const securityLevelsAdapter:SourceAdapter={id:'LEVELS',version:VERSION,minSyncIntervalSeconds:3600,
 async sync({now,fetchText}){
  const seen=new Set<string>(),urls=new Set<string>(),events=new Map<string,Event>();let next:string|null=LEVELS_INDEX;
  const cutoff=DateTime.fromJSDate(now).minus({days:120}).toISODate()!;
  // Bounded publication discovery; retained earlier decisions remain in the store.
  // This is explicitly not a complete government active-decision registry.
  while(next){
   if(seen.has(next)||seen.size>=40)throw new Error('LEVELS_DISCOVERY_LIMIT');seen.add(next);
   const page=parseLevelsIndex(await fetchText(next),next);
   for(const link of page.links){if(link.date<cutoff||urls.has(link.url))continue;urls.add(link.url);
    for(const e of parseLevelsArticle(await fetchText(link.url),link.url,now)){
     const old=events.get(e.id);
     if(!old||e.publicationDate!>old.publicationDate!)events.set(e.id,e);
     else if(e.publicationDate===old.publicationDate&&JSON.stringify(e.securityLevel)!==JSON.stringify(old.securityLevel))throw new Error('LEVELS_CONFLICTING_DECISION');
    }
   }
   next=page.oldest<cutoff?null:page.next;
  }
  if(!events.size)throw new Error('LEVELS_NO_DATA');
  return {events:[...events.values()],complete:false,coverage:'RECENT_PUBLICATIONS',pagesFetched:seen.size+urls.size};
 }
};

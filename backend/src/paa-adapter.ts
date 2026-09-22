import * as cheerio from 'cheerio';
import {createHash} from 'node:crypto';
import {DateTime} from 'luxon';
import {eventSchema,REGIONS,type Event} from './domain.js';
import type {SourceAdapter} from './source-adapter.js';
export const PAA_INDEX='https://www.gov.pl/web/paa/aktualnosci2';
export const PAA_MONITORING='https://monitoring.paa.gov.pl/maps-portal/';
export const PAA_VERSION='paa-html/1.0.0';
const clean=(s:string)=>s.replace(/\s+/g,' ').trim();
function sourceUrl(href:string,base=PAA_INDEX){
 const u=new URL(href,base);
 if(u.protocol!=='https:'||u.hostname!=='www.gov.pl'||u.port||u.username||u.password||!u.pathname.startsWith('/web/paa/'))throw new Error('PAA_URL_DENIED');
 u.hash='';return u;
}
export function parsePaaIndex(html:string,url=PAA_INDEX){
 const $=cheerio.load(html),article=$('main article'),rows=article.find('.art-prev > ul > li');
 if(article.length!==1||clean(article.find('h2').first().text())!=='Aktualności'||!rows.length||rows.length>50)throw new Error('PAA_INDEX_CONTRACT_CHANGED');
 const urls:string[]=[];
 rows.each((_,row)=>{
  const link=$(row).find('.title a[href]'),date=clean($(row).find('.date').text());
  if(link.length!==1||!DateTime.fromFormat(date,'dd.MM.yyyy').isValid||!clean(link.text()))throw new Error('PAA_INDEX_CONTRACT_CHANGED');
  // Read every article, not just headlines containing a keyword.
  const u=sourceUrl(link.attr('href')!,url);u.search='';urls.push(u.href);
 });
 const href=article.find('#js-pagination-page-next').attr('href');let next:string|null=null;
 if(href){const u=sourceUrl(href,url);if(u.pathname!==new URL(PAA_INDEX).pathname||!/^\d+$/.test(u.searchParams.get('page')??'')||u.searchParams.get('size')!=='10'||[...u.searchParams.keys()].some(k=>!['page','size'].includes(k)))throw new Error('PAA_PAGINATION_CONTRACT_CHANGED');next=u.href;}
 return {urls:[...new Set(urls)],next};
}
export function parsePaaArticle(html:string,url:string,now=new Date()):Event|null{
 const canonical=sourceUrl(url);canonical.search='';
 const $=cheerio.load(html),article=$('main article'),body=article.find('.editor-content');
 body.find('script,style').remove();
 const title=clean(article.find('h2').first().text()),intro=clean(article.find('p.intro').text());
 const paragraphs=body.find('p,li').map((_,n)=>clean($(n).text())).get().filter(Boolean);
 const description=[intro,...paragraphs].filter(Boolean).join('\n\n');
 const day=DateTime.fromFormat(clean(article.find('.event-date').text()),'dd.MM.yyyy',{zone:'Europe/Warsaw'});
 if(article.length!==1||(body.length<1||body.length>10)||!title||description.length<20||!day.isValid||day.startOf('day').toMillis()>now.getTime()+86400000)throw new Error('PAA_ARTICLE_CONTRACT_CHANGED');
 // Editorial news, reports and training are not incident messages. Unknown
 // incident wording stays UNDETERMINED; it is never interpreted as all-clear.
 const lead=title+' '+intro;
 if(!/(?:radiacyjn|radiologiczn|promieniotwórcz|skażeni)/iu.test(lead+' '+description))return null;
 if(!/(?:komunikat|ostrzeżenie|alarm|sytuacja radiacyjna|zagrożeni\p{L}* radiacyjn|zdarzeni\p{L}* radiacyjn|skażeni\p{L}* promieniotwórcz)/iu.test(lead))return null;
 if(/konferenc|szkoleni|ćwiczen|ćwicz|podcast|raport roczny|kwartaln|wytyczn|list intencyjny/iu.test(title))return null;
 const context=/ćwicz|exercise/iu.test(lead)?'EXERCISE':/test systemu/iu.test(lead)?'TEST':'ACTUAL';
 // Only standalone, explicit PAA assertions. Do not infer from measurements,
 // quotations, negated statements, hypothetical scenarios or foreign incidents.
 const statements=[intro,...paragraphs];
 const warning=statements.find(p=>/^(?:Państwowa Agencja Atomistyki (?:informuje|ostrzega), że |PAA (?:informuje|ostrzega), że )?(?:na terenie całej Polski|na terytorium Polski|w całej Polsce|na terenie województwa [\p{L}-]+) (?:obowiązuje alarm radiacyjny|występuje zagrożenie radiacyjne)\.$/iu.test(p));
 const ended=/^(?:Komunikat PAA[ :–—-]+)?(?:Alarm radiacyjny (?:odwołany|zakończony)|Zagrożenie radiacyjne (?:ustało|zakończone))[.!]?$/iu.test(title);
 const informational=/sytuacja radiacyjna w normie|nie ma zagrożenia|brak zagrożenia radiacyjnego/iu.test(title);
 const assessment=ended?'ENDED':warning&&context==='ACTUAL'?'WARNING':informational?'INFORMATION':'UNDETERMINED';
 const location=warning??(informational?intro:null);
 const national=!!location&&/(?:na terenie całej Polski|na terytorium Polski|w całej Polsce|w Polsce)/iu.test(location);
 const region=warning?.match(/województwa ([\p{L}-]+)/iu)?.[1];
 const regions=national?['PL']:region?Object.keys(REGIONS).filter(k=>REGIONS[k].toLocaleLowerCase('pl')===region.toLocaleLowerCase('pl')):[];
 // A date without a time stays publicationDate; never fabricate midnight.
 const publishedRaw=article.find('time[datetime]').first().attr('datetime');
 const publishedAt=publishedRaw&&/^\d{4}-\d{2}-\d{2}T.*(?:Z|[+-]\d{2}:\d{2})$/.test(publishedRaw)?publishedRaw:null;
 const validity=(label:string)=>{
  const p=statements.find(p=>p.startsWith(label+': '));if(!p)return null;
  const raw=p.slice(label.length+2).trim();
  if(!/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:Z|[+-]\d{2}:\d{2})$/.test(raw))throw new Error('PAA_VALIDITY_UNSUPPORTED');
  return raw;
 };
 const validFrom=validity('Obowiązuje od'),validTo=validity('Obowiązuje do');
 return eventSchema.parse({id:'PAA-'+createHash('sha256').update(canonical.href).digest('hex').slice(0,24),title,description,eventType:'RADIATION',severity:assessment==='WARNING'?'HIGH':'INFORMATIONAL',verification:'CONFIRMED',lifecycle:ended?'ENDED':assessment==='WARNING'?(validFrom&&Date.parse(validFrom)>now.getTime()?'SCHEDULED':validTo&&Date.parse(validTo)<=now.getTime()?'EXPIRED':'ACTIVE'):'UNKNOWN',messageContext:context,regions,geographicScope:national?'NATIONAL':regions.length?'REGIONAL':'UNKNOWN',publishedAt,publicationDate:day.toISODate(),retrievedAt:now.toISOString(),validFrom,validTo,sources:[{id:'PAA',name:'Państwowa Agencja Atomistyki',url:canonical.href,tier:1}],instructions:[],officialWarning:assessment==='WARNING',reviewed:false,revision:1,correction:null,latitude:null,longitude:null,geometry:null,locationText:location,areaPrecision:national?'COUNTRY':regions.length?'PROVINCE':'UNKNOWN',adapterVersion:PAA_VERSION,sourceContentHash:createHash('sha256').update(html).digest('hex'),radiationAssessment:{state:assessment,evidence:warning??null}});
}
export const paaAdapter:SourceAdapter={id:'PAA',version:PAA_VERSION,minSyncIntervalSeconds:300,async sync({now,fetchText,previousEvents=[]}){
 const pages=new Set<string>(),urls=new Set<string>();let next:string|null=PAA_INDEX;
 for(let i=0;next&&i<3;i++){
  if(pages.has(next))throw new Error('PAA_PAGINATION_LOOP');pages.add(next);
  const index=parsePaaIndex(await fetchText(next),next);index.urls.forEach(u=>urls.add(u));next=index.next;
 }
 // Re-fetch known messages even after they leave the recent publication window.
 for(const e of previousEvents.filter(e=>e.sources.some(s=>s.id==='PAA'))){for(const source of e.sources.filter(s=>s.id==='PAA'))urls.add(sourceUrl(source.url).href);}
 if(urls.size>100)throw new Error('PAA_RECHECK_LIMIT_REACHED');
 const events:Event[]=[];
 const known=new Set(previousEvents.flatMap(e=>e.sources.filter(s=>s.id==='PAA').map(s=>s.url)));
 const list=[...urls];
 for(let i=0;i<list.length;i+=3){
  const parsed=await Promise.all(list.slice(i,i+3).map(async url=>{const e=parsePaaArticle(await fetchText(url),url,now);if(!e&&known.has(url))throw new Error('PAA_KNOWN_MESSAGE_CONTRACT_CHANGED');return e;}));
  for(const e of parsed)if(e)events.push(e);
 }
 // The archive cannot establish a complete list of active warnings.
 return {events,complete:false,coverage:'RECENT_PUBLICATIONS',pagesFetched:pages.size};
}};

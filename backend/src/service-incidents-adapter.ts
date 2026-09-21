import * as cheerio from 'cheerio';
import {createHash} from 'node:crypto';
import {DateTime} from 'luxon';
import {eventSchema,REGIONS,type Event} from './domain.js';
import type {SourceAdapter} from './source-adapter.js';

export const POLICE_INDEX='https://policja.pl/pol/aktualnosci';
export const POLICE_RSS='https://policja.pl/dokumenty/rss/1-rss-1.rss';
export const PSP_INCIDENTS_INDEX='https://www.gov.pl/web/kgpsp/aktualnosci';
export const POLICE_VERSION='police-rss-incidents/1.0.0';
export const PSP_INCIDENTS_VERSION='psp-govpl-incidents/1.0.0';

const clean=(s:string)=>s.replace(/\u00a0/g,' ').replace(/\s+/g,' ').trim();
const provinceStems:Record<string,string>={
  '02':'dolnośląsk','04':'kujawsko-pomorsk','06':'lubelsk','08':'lubusk',
  '10':'łódzk','12':'małopolsk','14':'mazowieck','16':'opolsk','18':'podkarpack',
  '20':'podlask','22':'pomorsk','24':'śląsk','26':'świętokrzysk','28':'warmińsko-mazursk',
  '30':'wielkopolsk','32':'zachodniopomorsk',
};

export function isAllowedPoliceUrl(value:string){
  let u:URL;try{u=new URL(value);}catch{return false;}
  if(u.protocol!=='https:'||!['policja.pl','www.policja.pl'].includes(u.hostname)||u.port||u.username||u.password||u.hash)return false;
  if(u.href===POLICE_RSS)return true;
  if(u.pathname==='/pol/aktualnosci')return u.search==='';
  return /^\/pol\/aktualnosci\/\d+,[^/?#]{1,240}\.html$/.test(u.pathname)&&u.search==='';
}
function policeArticleUrl(value:string){
  const u=new URL(value,POLICE_INDEX);u.hash='';
  if(!isAllowedPoliceUrl(u.href)||!/^\/pol\/aktualnosci\/\d+,/.test(u.pathname))throw new Error('POLICE_URL_DENIED');
  return u;
}
function pspUrl(value:string,base=PSP_INCIDENTS_INDEX){
  const u=new URL(value,base);
  if(u.protocol!=='https:'||u.hostname!=='www.gov.pl'||u.port||u.username||u.password||!u.pathname.startsWith('/web/kgpsp/'))throw new Error('PSP_INCIDENTS_URL_DENIED');
  u.hash='';return u;
}
function explicitRegions(text:string){
  const labelled=[...text.matchAll(/(?:woj[.:]|województw\p{L}*)\s*:?\s*([^.;)]+)/giu)].map(m=>m[1]).join(' ');
  return Object.entries(provinceStems).filter(([,stem])=>new RegExp(`(?<![\\p{L}-])${stem}\\p{L}*`,'iu').test(labelled)).map(([id])=>id).sort();
}
function correctionText(text:string){
  const match=clean(text).split(/(?<=[.!?])\s+/u).find(s=>/^(?:korekta|sprostowanie|aktualizacja)\b/iu.test(s));
  return match?.slice(0,4000)??null;
}
type Classification={eventType:Event['eventType'];severity:Event['severity']};
export function classifyServiceIncident(title:string,description:string):Classification|null{
  const text=clean(title+' '+description);
  const editorial=/(?:\brocznic\w*\b|\bhistoryczn\w*\b|\b(?:19|20)\d{2}\s*r\.?.*\b(?:rocznic|sprzed)\b|konferenc\w*|szkoleni\w*|trening\w*|ćwiczeni\w*|warsztat\w*|kampani\w*|profilakty\w*|konkurs\w*|mistrzostw\w*|turniej\w*|uroczysto\w*|rekolekc\w*|narad\w*|spotkani\w*|podsumowani\w*|nab[oó]r\w*|dotacj\w*|przekazani\w*\s+sprzęt|nowy\w*\s+sztandar)/iu.test(text);
  if(editorial)return null;

  const explosion=/(?:\bwybuch\w*|\beksplozj\w*)/iu.test(text);
  if(explosion)return {eventType:'EXPLOSION',severity:/(?:ewaku\w*|ofiar\w*|poszkodowan\w*|zawali\w*|zakład\w*|fabryk\w*|magazyn\w*|infrastruktur\w*)/iu.test(text)?'HIGH':'NORMAL'};

  const hazmat=/(?:HAZMAT|zagrożeni\w* chemiczn\w*|substancj\w* chemiczn\w*|wyciek\w* (?:amoniak\w*|chlor\w*|kwas\w*|gazu\b|substancj\w*)|rozszczeln\w*.*(?:amoniak|chlor|gaz|chemiczn)|skażeni\w* chemiczn\w*)/iu.test(text);
  if(hazmat)return {eventType:'HAZMAT',severity:/(?:ewaku\w*|stref\w* zagrożenia|zakład\w*|magazyn\w*|infrastruktur\w*)/iu.test(text)?'HIGH':'NORMAL'};

  const industrialFire=/(?:pożar\w*|płon\w*)/iu.test(text)&&/(?:duż\w* pożar|magazyn\w*|hal\w*|zakład\w*|fabryk\w*|rafineri\w*|elektrowni\w*|stacj\w* transformator|składowisk\w*|centrum logistyczn\w*|budyn\w* wielorodzinn\w*|szpital\w*|szkoł\w*|infrastruktur\w* krytyczn\w*|ewaku\w*|kilkadziesiąt zastęp\w*|wiele zastęp\w*)/iu.test(text);
  if(industrialFire)return {eventType:'FIRE',severity:/(?:ewaku\w*|zakład\w*|fabryk\w*|rafineri\w*|elektrowni\w*|infrastruktur\w* krytyczn\w*|duż\w* pożar)/iu.test(text)?'HIGH':'NORMAL'};

  const massRescue=/(?:katastrof\w* budowlan\w*|zawali\w* (?:się )?(?:budyn|hal|dach)|wypadek kolejow\w*|katastrof\w* kolejow\w*|akcj\w* ratownicz\w*)/iu.test(text)
    &&/(?:ewaku\w*|poszkodowan\w*|ofiar\w*|zgin\w*|szpital\w*|\b(?:1[0-9]|[2-9][0-9]|\d{3,})\s*(?:os[oó]b|pasażer)|kilkanaście|kilkadziesiąt|wiele zastęp\w*|specjalistyczn\w* grup\w*)/iu.test(text);
  const majorRoad=/(?:wypad\w*|zderzeni\w*|katastrof\w*)/iu.test(text)&&/(?:autostrad\w*|droga krajow\w*|trasa szybkiego ruchu|ekspresow\w*|\bS\d{1,2}\b|\bA\d{1,2}\b)/u.test(text)&&/(?:zablokowan\w*|zamknięt\w*|wstrzyman\w* ruch|objazd\w*)/iu.test(text);
  if(massRescue||majorRoad)return {eventType:'RESCUE',severity:massRescue?'HIGH':'NORMAL'};

  const publicSafety=/(?:strzelanin\w*|aktywn\w* napastnik\w*|atak\w* z użyciem broni|zagrożeni\w* bombow\w*|podejrzeni\w* ładunk\w* wybuchow\w*)/iu.test(text)
    &&/(?:ewaku\w*|postrzel\w*|rann\w*|ofiar\w*|zgin\w*|trwa\w* (?:obław|akcj|poszukiw)|zamknięt\w* (?:ulic|droga|teren)|wstrzyman\w* ruch)/iu.test(text);
  if(publicSafety)return {eventType:'PUBLIC_SAFETY',severity:'HIGH'};

  return null;
}

export type PoliceRssItem={id:string;title:string;description:string;url:string;publishedAt:string|null;publicationDate:string|null};
export function parsePoliceRss(xml:string,now=new Date()):PoliceRssItem[]{
  if(/<!DOCTYPE|<!ENTITY/i.test(xml))throw new Error('POLICE_RSS_UNSAFE_XML');
  const $=cheerio.load(xml,{xml:true}),channel=$('rss > channel'),items=channel.children('item');
  if(channel.length!==1||!items.length||items.length>100)throw new Error('POLICE_RSS_CONTRACT_CHANGED');
  const seen=new Set<string>();
  const out:PoliceRssItem[]=[];
  items.each((_,node)=>{
    const n=$(node),title=clean(n.children('title').first().text()),description=clean(cheerio.load(n.children('description').first().text()).text()),link=clean(n.children('link').first().text()),pubDate=clean(n.children('pubDate').first().text());
    if(!title||!link)throw new Error('POLICE_RSS_CONTRACT_CHANGED');
    const u=policeArticleUrl(link),id=u.pathname.match(/^\/pol\/aktualnosci\/(\d+),/)?.[1];
    if(!id||seen.has(id))throw new Error('POLICE_RSS_DUPLICATE_ID');seen.add(id);
    let publishedAt:string|null=null,publicationDate:string|null=null;
    if(pubDate){
      const d=DateTime.fromRFC2822(pubDate,{setZone:true});
      if(!d.isValid||d.toMillis()>now.getTime()+36*3600_000)throw new Error('POLICE_RSS_DATE_INVALID');
      publishedAt=d.toUTC().toISO();publicationDate=d.setZone('Europe/Warsaw').toISODate();
    }
    out.push({id,title,description,url:u.href,publishedAt,publicationDate});
  });
  return out;
}
function policeEvent(item:PoliceRssItem,now:Date):Event|null{
  const classification=classifyServiceIncident(item.title,item.description);if(!classification)return null;
  const regions=explicitRegions(item.title+' '+item.description);
  return eventSchema.parse({
    id:'POLICE-'+item.id,title:item.title,description:item.description||item.title,eventType:classification.eventType,severity:classification.severity,
    verification:'CONFIRMED',lifecycle:'UNKNOWN',messageContext:'ACTUAL',regions,geographicScope:regions.length?'REGIONAL':'UNKNOWN',
    publishedAt:item.publishedAt,publicationDate:item.publicationDate,retrievedAt:now.toISOString(),validFrom:null,validTo:null,
    sources:[{id:'POLICE',name:'Policja',url:item.url,tier:1}],instructions:[],officialWarning:false,reviewed:false,revision:1,
    correction:correctionText(item.description),latitude:null,longitude:null,geometry:null,locationText:null,areaPrecision:regions.length?'PROVINCE':'UNKNOWN',
    adapterVersion:POLICE_VERSION,sourceContentHash:createHash('sha256').update(JSON.stringify(item)).digest('hex'),isDemo:false,
  });
}
export const policeAdapter:SourceAdapter={id:'POLICE',version:POLICE_VERSION,minSyncIntervalSeconds:900,async sync({now,fetchText}){
  const items=parsePoliceRss(await fetchText(POLICE_RSS),now),events=items.map(i=>policeEvent(i,now)).filter((e):e is Event=>e!==null);
  return {events,complete:false,coverage:'RECENT_PUBLICATIONS',pagesFetched:1};
}};

export function parsePspIndex(html:string,url=PSP_INCIDENTS_INDEX){
  const $=cheerio.load(html),article=$('main article'),links=article.find('.art-prev .title a[href]');
  if(article.length!==1||clean(article.find('h2').first().text())!=='Aktualności'||!links.length||links.length>50)throw new Error('PSP_INCIDENTS_INDEX_CONTRACT_CHANGED');
  const urls:string[]=[];
  links.each((i,node)=>{
    const link=$(node),title=clean(link.text());
    if(!title)throw new Error(`PSP_INCIDENTS_INDEX_CONTRACT_CHANGED:link=${i}:title=EMPTY`);
    const u=pspUrl(link.attr('href')!,url);u.search='';urls.push(u.href);
  });
  const href=article.find('#js-pagination-page-next').attr('href');let next:string|null=null;
  if(href){const u=pspUrl(href,url);if(u.pathname!==new URL(PSP_INCIDENTS_INDEX).pathname||!/^\d+$/.test(u.searchParams.get('page')??'')||u.searchParams.get('size')!=='10'||[...u.searchParams.keys()].some(k=>!['page','size'].includes(k)))throw new Error('PSP_INCIDENTS_PAGINATION_CONTRACT_CHANGED');next=u.href;}
  return {urls:[...new Set(urls)],next};
}
function pspLocation(title:string){
  const m=clean(title).match(/^(.{2,100}?)\s+[–—-]\s+/u);return m?m[1].trim():null;
}
export function parsePspArticle(html:string,url:string,now=new Date()):Event|null{
  const canonical=pspUrl(url);canonical.search='';
  const $=cheerio.load(html),article=$('main article'),body=article.find('.editor-content');
  body.find('script,style').remove();
  const title=clean(article.find('h2').first().text()),intro=clean(article.find('p.intro').text());
  const paragraphs=body.find('p,li').map((_,n)=>clean($(n).text())).get().filter(Boolean);
  const description=[intro,...paragraphs].filter(Boolean).join('\n\n')||clean(body.text());
  const day=DateTime.fromFormat(clean(article.find('.event-date').text()),'dd.MM.yyyy',{zone:'Europe/Warsaw'});
  if(article.length!==1||(body.length<1||body.length>10)||!title||description.length<20||!day.isValid||day.startOf('day').toMillis()>now.getTime()+86400000)throw new Error('PSP_INCIDENTS_ARTICLE_CONTRACT_CHANGED');
  const classification=classifyServiceIncident(title,description);if(!classification)return null;
  const regions=explicitRegions(title+' '+description),locationText=pspLocation(title);
  const publishedRaw=article.find('time[datetime]').first().attr('datetime');
  const publishedAt=publishedRaw&&/^\d{4}-\d{2}-\d{2}T.*(?:Z|[+-]\d{2}:\d{2})$/.test(publishedRaw)?publishedRaw:null;
  return eventSchema.parse({
    id:'PSP_INCIDENTS-'+createHash('sha256').update(canonical.href).digest('hex').slice(0,24),title,description,eventType:classification.eventType,severity:classification.severity,
    verification:'CONFIRMED',lifecycle:'UNKNOWN',messageContext:'ACTUAL',regions,geographicScope:regions.length?'REGIONAL':'UNKNOWN',
    publishedAt,publicationDate:day.toISODate(),retrievedAt:now.toISOString(),validFrom:null,validTo:null,
    sources:[{id:'PSP_INCIDENTS',name:'Państwowa Straż Pożarna — zdarzenia',url:canonical.href,tier:1}],instructions:[],officialWarning:false,reviewed:false,revision:1,
    correction:correctionText(description),latitude:null,longitude:null,geometry:null,locationText,areaPrecision:regions.length?'PROVINCE':locationText?'EXACT':'UNKNOWN',
    adapterVersion:PSP_INCIDENTS_VERSION,sourceContentHash:createHash('sha256').update(html).digest('hex'),isDemo:false,
  });
}
export const pspIncidentsAdapter:SourceAdapter={id:'PSP_INCIDENTS',version:PSP_INCIDENTS_VERSION,minSyncIntervalSeconds:900,async sync({now,fetchText,previousEvents=[]}){
  const pages=new Set<string>(),urls=new Set<string>();let next:string|null=PSP_INCIDENTS_INDEX;
  for(let i=0;next&&i<2;i++){
    if(pages.has(next))throw new Error('PSP_INCIDENTS_PAGINATION_LOOP');pages.add(next);
    const index=parsePspIndex(await fetchText(next),next);index.urls.forEach(u=>urls.add(u));next=index.next;
  }
  for(const e of previousEvents.filter(e=>e.sources.some(s=>s.id==='PSP_INCIDENTS'))){for(const s of e.sources.filter(s=>s.id==='PSP_INCIDENTS'))urls.add(pspUrl(s.url).href);}
  if(urls.size>60)throw new Error('PSP_INCIDENTS_RECHECK_LIMIT_REACHED');
  const known=new Set(previousEvents.flatMap(e=>e.sources.filter(s=>s.id==='PSP_INCIDENTS').map(s=>s.url))),events:Event[]=[];
  const list=[...urls];
  for(let i=0;i<list.length;i+=4){
    const parsed=await Promise.all(list.slice(i,i+4).map(async u=>{const e=parsePspArticle(await fetchText(u),u,now);if(!e&&known.has(u))throw new Error('PSP_INCIDENTS_KNOWN_MESSAGE_CONTRACT_CHANGED');return e;}));
    events.push(...parsed.filter((e):e is Event=>e!==null));
  }
  return {events,complete:false,coverage:'RECENT_PUBLICATIONS',pagesFetched:pages.size};
}};

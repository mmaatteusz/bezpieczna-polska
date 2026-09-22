import * as cheerio from 'cheerio';
import {createHash} from 'node:crypto';
import {DateTime} from 'luxon';
import {eventSchema,type Event} from './domain.js';
import type {SourceAdapter} from './source-adapter.js';

export const CERT_FEED='https://moje.cert.pl/advisory_feed/advisory/feed/';
export const CERT_INDEX='https://moje.cert.pl/komunikaty/';
export const CERT_VERSION='cert-rss/1.0.0';
export const CSIRT_GOV_RSS_PAGE='https://www.csirt.gov.pl/cer/rss';

const clean=(value:string)=>value.replace(/\s+/g,' ').trim();
const htmlText=(value:string)=>{
 const $=cheerio.load('<div id="root">'+value+'</div>');
 $('script,style').remove();
 return clean($('#root').text());
};

function certArticleUrl(value:string){
 const u=new URL(value);
 if(u.protocol!=='https:'||u.hostname!=='moje.cert.pl'||u.port||u.username||u.password||!/^\/komunikaty\/\d{4}\/\d+\/[a-z0-9-]+\/$/.test(u.pathname))throw new Error('CERT_URL_DENIED');
 u.search='';u.hash='';return u;
}

function eventId(url:URL){
 const m=url.pathname.match(/^\/komunikaty\/(\d{4})\/(\d+)\//);
 if(!m)throw new Error('CERT_ID_INVALID');
 return `CERT-${m[1]}-${m[2]}`;
}

function severity(title:string,description:string):Event['severity']{
 const text=clean(title+' '+description).toLocaleLowerCase('pl');
 if(/(?:krytyczn|aktywnie wykorzystywan|piln\w* aktualiz|zero[- ]day|zdaln\w* wykonani\w* kodu|rce\b)/iu.test(text))return 'HIGH';
 if(/(?:phishing|złośliw\w* oprogram|malware|podatno|wyłudzeni|oszust|kampani)/iu.test(text))return 'NORMAL';
 return 'INFORMATIONAL';
}

function context(title:string,description:string):Event['messageContext']{
 const text=title+' '+description;
 if(/ćwicz|cwicz|exercise/iu.test(text))return 'EXERCISE';
 if(/\btest(?:owy|owa|owe| systemu)?\b/iu.test(text))return 'TEST';
 return 'ACTUAL';
}

export function parseCertFeed(xml:string,now=new Date()):Event[]{
 if(/<!DOCTYPE|<!ENTITY/i.test(xml))throw new Error('UNSAFE_XML');
 const $=cheerio.load(xml,{xml:true});
 const rss=$('rss'),channel=rss.children('channel');
 if(rss.length!==1||rss.attr('version')!=='2.0'||channel.length!==1)throw new Error('CERT_FEED_CONTRACT_CHANGED');
 const channelTitle=clean(channel.children('title').first().text());
 const channelLink=clean(channel.children('link').first().text());
 if(!/moje\.cert\.pl/i.test(channelTitle)||new URL(channelLink).hostname!=='moje.cert.pl')throw new Error('CERT_FEED_CONTRACT_CHANGED');
 const items=channel.children('item');
 if(!items.length||items.length>100)throw new Error('CERT_FEED_EMPTY_OR_TOO_LARGE');
 const events:Event[]=[];
 const seen=new Set<string>();
 items.each((_,node)=>{
  const item=$(node);
  const title=clean(item.children('title').first().text());
  const rawLink=clean(item.children('link').first().text());
  const rawDescription=item.children('description').first().text();
  const description=htmlText(rawDescription);
  const rawDate=clean(item.children('pubDate').first().text());
  const categories=item.children('category').map((_,n)=>clean($(n).text())).get().filter(Boolean);
  if(!title||title.length>350||!rawLink||!description||description.length>40000||!rawDate)throw new Error('CERT_ITEM_CONTRACT_CHANGED');
  const url=certArticleUrl(rawLink),id=eventId(url);
  if(seen.has(id))throw new Error('CERT_DUPLICATE_ID');seen.add(id);
  const published=DateTime.fromRFC2822(rawDate,{setZone:true});
  if(!published.isValid||published.toMillis()>now.getTime()+5*60_000)throw new Error('CERT_DATE_INVALID');
  const combined=(title+' '+description).toLocaleLowerCase('pl');
  const report=categories.some(c=>/raporty miesięczne|wydarzenia/iu.test(c))||/^raport miesięczny/iu.test(title);
  if(report)return;
  const expired=/^wygasł[yae]?\b/iu.test(title)||/^wygasł[yae]?\b/iu.test(description);
  const event=eventSchema.parse({
   id,title,description,eventType:'CYBER',severity:severity(title,description),verification:'CONFIRMED',
   lifecycle:expired?'EXPIRED':'UNKNOWN',messageContext:context(title,description),regions:[],geographicScope:'UNKNOWN',
   publishedAt:published.toUTC().toISO(),publicationDate:published.setZone('Europe/Warsaw').toISODate(),retrievedAt:now.toISOString(),
   validFrom:null,validTo:null,sources:[{id:'CERT',name:'CERT Polska',url:url.href,tier:1}],instructions:[],
   officialWarning:false,reviewed:false,revision:1,correction:null,latitude:null,longitude:null,geometry:null,locationText:null,
   areaPrecision:'UNKNOWN',adapterVersion:CERT_VERSION,sourceContentHash:createHash('sha256').update($.html(node)).digest('hex'),isDemo:false
  });
  // Every CERT advisory is informational for the main physical-safety status.
  // Severity only helps ordering within the cyber section.
  if(/(?:nie ma zagrożenia|brak zagrożenia)/iu.test(combined)&&event.severity==='HIGH')throw new Error('CERT_SEVERITY_CONTRADICTION');
  events.push(event);
 });
 if(!events.length)throw new Error('CERT_NO_ACTIONABLE_ADVISORIES');
 return events;
}

export function parseCsirtGovRssLanding(html:string){
 const $=cheerio.load(html),main=$('main');
 if(main.length!==1||!main.text().includes('Co to jest RSS?')||!main.text().includes('Podłączanie kanałów RSS'))throw new Error('CSIRT_RSS_PAGE_CONTRACT_CHANGED');
 const boxes=main.find('.box-default').filter((_,n)=>clean($(n).find('h3').first().text())==='Lista');
 if(boxes.length!==1)throw new Error('CSIRT_RSS_PAGE_CONTRACT_CHANGED');
 const links=boxes.find('ul a[href]').map((_,n)=>{
  const u=new URL($(n).attr('href')!,CSIRT_GOV_RSS_PAGE);
  if(u.protocol!=='https:'||!['csirt.gov.pl','www.csirt.gov.pl'].includes(u.hostname)||u.port||u.username||u.password)throw new Error('CSIRT_RSS_URL_DENIED');
  u.hash='';return u.href;
 }).get();
 return [...new Set(links)];
}

export const certAdapter:SourceAdapter={
 id:'CERT',version:CERT_VERSION,minSyncIntervalSeconds:900,
 async sync({now,fetchText}){
  const events=parseCertFeed(await fetchText(CERT_FEED),now);
  return {events,complete:false,coverage:'RECENT_PUBLICATIONS',pagesFetched:1};
 }
};

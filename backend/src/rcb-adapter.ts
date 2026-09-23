import * as cheerio from 'cheerio';
import {createHash} from 'node:crypto';
import {DateTime} from 'luxon';
import {eventSchema, type Event} from './domain.js';
import type {SourceAdapter} from './source-adapter.js';

export const RCB_INDEX = 'https://www.gov.pl/web/rcb/komunikaty';
const VERSION = 'rcb-html/1.1.0';
const clean = (text:string) => text.replace(/\s+/g,' ').trim();
function sourceUrl(href:string, base=RCB_INDEX):URL {
  const u=new URL(href,base);
  if(u.protocol!=='https:'||u.hostname!=='www.gov.pl'||u.port||u.username||u.password||!u.pathname.startsWith('/web/rcb/'))throw new Error('RCB_URL_DENIED');
  u.hash='';return u;
}
export function parseRcbIndex(html:string):string[]{
  const $=cheerio.load(html),urls=new Set<string>();
  $('main a[href]').each((_,a)=>{
    const href=$(a).attr('href')!;
    // Ignore ordinary navigation links; validate every candidate alert URL.
    if(!href.includes('/web/rcb/alert-rcb-'))return;
    const u=sourceUrl(href);
    if(/^\/web\/rcb\/alert-rcb-.+/.test(u.pathname)){u.search='';urls.add(u.href);}
  });
  if(!urls.size)throw new Error('RCB_HTML_CONTRACT_CHANGED');
  return [...urls];
}

const provinceStems:Record<string,string>={
  '02':'dolnośląsk','04':'kujawsko-pomorsk','06':'lubelsk','08':'lubusk',
  '10':'łódzk','12':'małopolsk','14':'mazowieck','16':'opolsk','18':'podkarpack',
  '20':'podlask','22':'pomorsk','24':'śląsk','26':'świętokrzysk','28':'warmińsko-mazursk',
  '30':'wielkopolsk','32':'zachodniopomorsk',
};
export function parseRcbArticle(html:string,url:string,now=new Date()):Event{
  const canonical=sourceUrl(url);canonical.search='';
  const $=cheerio.load(html),article=$('article').first();
  const title=clean(article.find('h2').first().text());
  const body=article.find('.editor-content').first();
  body.find('script,style').remove();
  const paragraphs=body.find('p,li').map((_,n)=>clean($(n).text())).get().filter(Boolean);
  const description=paragraphs.length?paragraphs.join('\n\n'):clean(body.text());
  const dateText=clean(article.find('.event-date').first().text());
  const publication=DateTime.fromFormat(dateText,'dd.MM.yyyy',{zone:'Europe/Warsaw'});
  if(!/^Alert RCB\s*[-–—]/i.test(title)||description.length<20||!publication.isValid)throw new Error('RCB_ARTICLE_CONTRACT_CHANGED');
  if(publication.startOf('day').toMillis()>now.getTime()+86400000)throw new Error('RCB_PUBLICATION_DATE_FUTURE');
  // Only the explicit recipient section establishes location, never mentions
  // of places inside the warning itself (e.g. an attack on Ukraine).
  const recipient=paragraphs.findIndex(p=>/wysłan|objęto|objęty|objęte|otrzymają/i.test(p));
  const locationText=recipient>=0?paragraphs.slice(recipient).join(' '):null;
  const national=!!locationText&&/cał(?:ego kraju|ej Polski|ym kraju)/i.test(locationText);
  // County names such as "powiat opolski" also occur in other provinces.
  // Match province names only within explicitly labelled woj./województwo lists.
  const provinceText=[...(locationText??'').matchAll(/(?:woj[.:]|województw\p{L}*)\s*:?\s*([^.;)]+)/giu)]
    .map(m=>m[1].split(/powiat|gmin|miast|[:(]|\s[–—]\s/i)[0]).join(' ');
  const regions=national?['PL']:Object.entries(provinceStems)
    .filter(([,stem])=>new RegExp(`(?<![\\p{L}-])${stem}\\p{L}*`,'iu').test(provinceText)).map(([id])=>id).sort();
  const text=title+' '+description;
  const context=/ćwicz|cwicz|trening system|exercise/i.test(text)?'EXERCISE':/test syren|test systemu/i.test(text)?'TEST':'ACTUAL';
  const bodyText=clean(body.text());
  const updateMarker=/aktualizacj|uaktualnieni/i.test(bodyText);
  const endedStatement=paragraphs.find(p=>
    /(?:zakończył się|zakończono|ustało|odwołan|odwolan|brak zagrożenia (?:na|dla) (?:terenie|terytorium) (?:Polski|RP))/iu.test(p)
  )??null;
  // RCB often keeps the original warning title and inserts an explicit
  // "Aktualizacja" into the body. Treat that authoritative update as the
  // lifecycle change instead of leaving a stale UNKNOWN warning forever.
  const cancelled=/odwołan|odwolano|zakaz przestał obowiązywać/i.test(title)||
    (updateMarker&&endedStatement!==null);
  const eventType=/powietrz|powietrza/i.test(title)?'AIR':/burz|wiatr|opad|upał|śnieg|mróz|powodz/i.test(title)?'WEATHER':/ewakuac/i.test(title)?'EVACUATION':/pożar/i.test(title)?'FIRE':'OTHER';
  return eventSchema.parse({
    id:'RCB-'+createHash('sha256').update(canonical.href).digest('hex').slice(0,24),
    title,description,eventType,severity:context==='ACTUAL'&&!cancelled?'NORMAL':'INFORMATIONAL',
    verification:'CONFIRMED',lifecycle:cancelled?'CANCELLED':'UNKNOWN',messageContext:context,
    regions,geographicScope:national?'NATIONAL':regions.length?'REGIONAL':'UNKNOWN',
    locationText,areaPrecision:national?'COUNTRY':regions.length?( /powiat|gmin|pow\./i.test(locationText!)?'PROVINCE_SUBSET':'PROVINCE'):'UNKNOWN',
    // The source provides a calendar date, not a time. Do not invent midnight
    // timestamps, expiry times or active status from a publication date.
    publicationDate:publication.toISODate(),publishedAt:null,retrievedAt:now.toISOString(),validFrom:null,validTo:null,
    sources:[{id:'RCB',name:'Rządowe Centrum Bezpieczeństwa',url:canonical.href,tier:1}],
    instructions:[],officialWarning:context==='ACTUAL'&&!cancelled,reviewed:false,revision:1,
    correction:cancelled?endedStatement:null,latitude:null,longitude:null,geometry:null,isDemo:false,
    adapterVersion:VERSION,sourceContentHash:createHash('sha256').update(html).digest('hex'),
  });
}

export const rcbAdapter:SourceAdapter={
  id:'RCB',version:VERSION,
  async sync({now,fetchText}){
    const urls=new Set<string>(),pages=new Set<string>();
    let next:string|null=RCB_INDEX;
    // Bounded recent-publication window; explicitly not a complete active feed.
    for(let page=0;next&&page<3;page++){
      if(pages.has(next))throw new Error('RCB_PAGINATION_LOOP');
      pages.add(next);
      const html=await fetchText(next),$=cheerio.load(html);
      for(const url of parseRcbIndex(html))urls.add(url);
      const href=$('#js-pagination-page-next').attr('href');
      if(href){
        const u=sourceUrl(href,next);
        if(u.pathname!=='/web/rcb/komunikaty'||!/^\d+$/.test(u.searchParams.get('page')??''))throw new Error('RCB_PAGINATION_CONTRACT_CHANGED');
        next=u.href;
      }else next=null;
    }
    if(urls.size>60)throw new Error('RCB_BATCH_TOO_LARGE');
    const events:Event[]=[];
    // Low bounded concurrency; one failed article rejects the whole batch.
    const list=[...urls];
    for(let i=0;i<list.length;i+=3){
      events.push(...await Promise.all(list.slice(i,i+3).map(async url=>parseRcbArticle(await fetchText(url),url,now))));
    }
    return {events,complete:false,coverage:'RECENT_PUBLICATIONS',pagesFetched:pages.size};
  },
};

import * as cheerio from 'cheerio';
import {createHash} from 'node:crypto';
import {DateTime} from 'luxon';
import {eventSchema,REGIONS,type Event} from './domain.js';
import type {SourceAdapter} from './source-adapter.js';

export const SG_INDEX='https://www.strazgraniczna.pl/pl/aktualnosci';
export const SG_RSS_PAGE='https://www.strazgraniczna.pl/pl/rss';
export const SG_VERSION='sg-operational-html/1.0.0';

const clean=(v:string)=>v.replace(/\u00a0/g,' ').replace(/\s+/g,' ').trim();
const escapeRe=(v:string)=>v.replace(/[\^$.*+?()[\]{}|\\]/g,'\\$&');

export function isAllowedSgUrl(value:string){
 let u:URL;
 try{u=new URL(value);}catch{return false;}
 if(u.protocol!=='https:'||u.hostname!=='www.strazgraniczna.pl'||u.port||u.username||u.password||u.hash)return false;
 if(u.pathname==='/pl/aktualnosci')return u.search===''||/^\?page=\d{1,2}$/.test(u.search);
 return /^\/pl\/aktualnosci\/\d+,[^/?#]{1,220}\.html$/.test(u.pathname)&&u.search==='';
}

function articleUrl(value:string){
 const u=new URL(value,SG_INDEX);
 if(!isAllowedSgUrl(u.href)||!/^\/pl\/aktualnosci\/\d+,/.test(u.pathname))throw new Error('SG_URL_DENIED');
 return u;
}

export function parseSgIndex(html:string){
 const $=cheerio.load(html);
 const sectionTitles=$('.naglowek h2').map((_,node)=>clean($(node).text())).get();
 if(!$('#content').length||!sectionTitles.includes('Aktualności'))throw new Error('SG_INDEX_CONTRACT_CHANGED');
 const byId=new Map<string,string>();
 $('a[href]').each((_,node)=>{
  const href=$(node).attr('href')??'';
  if(!/^\/pl\/aktualnosci\/\d+,[^?#]+\.html$/.test(href))return;
  const u=articleUrl(href),m=u.pathname.match(/^\/pl\/aktualnosci\/(\d+),/);
  if(!m)throw new Error('SG_INDEX_CONTRACT_CHANGED');
  const old=byId.get(m[1]);
  if(old&&old!==u.href)throw new Error('SG_DUPLICATE_ARTICLE_ID');
  byId.set(m[1],u.href);
 });
 const urls=[...byId.values()];
 if(!urls.length||urls.length>30)throw new Error('SG_INDEX_EMPTY_OR_TOO_LARGE');
 return urls;
}

function provinceRegions(text:string){
 const normalized=clean(text).toLocaleLowerCase('pl');
 const out:string[]=[];
 for(const [code,name] of Object.entries(REGIONS)){
  const stem=name.toLocaleLowerCase('pl').replace(/ie$/u,'');
  const re=new RegExp('\\bwoj(?:ew[oó]dztw\\w*)?\\.?[: ]{0,3}'+escapeRe(stem)+'\\w*','iu');
  if(re.test(normalized))out.push(code);
 }
 return [...new Set(out)];
}

function operationalKind(title:string,lead:string,body:string){
 const text=clean(title+' '+lead+' '+body).toLocaleLowerCase('pl');
 const border=/(przejści\w*\s+graniczn|granicy\s+państwow|odpraw\w*\s+graniczn|ruch\w*\s+graniczn|przekraczani\w*\s+granic|kontrol\w*\s+graniczn|ograniczen\w*\s+wjazd)/iu.test(text);
 if(!border)return null;
 const ended=/(przywr[oó]con\w*\s+(?:ruch|odpraw)|wznowion\w*\s+(?:ruch|odpraw)|otwarto\s+przejści|zniesion\w*\s+(?:ograniczen|kontrol)|zakończon\w*\s+utrudnien)/iu.test(text);
 if(ended)return 'ENDED' as const;
 const closed=/(wstrzym\w*\s+(?:ruch|odpraw)|zamkni\w*\s+przejści|przejści\w*\s+(?:jest|będzie)\s+zamkni|nieczynn\w*\s+przejści|zawieszon\w*\s+odpraw)/iu.test(text);
 if(closed)return 'CLOSED' as const;
 const restricted=/(utrudnien|ograniczen\w*\s+(?:w\s+)?ruch|czasow\w*\s+zmian\w*\s+organizac\w*\s+ruch|blokad\w*\s+(?:gran|przej)|wprowadzen\w*\s+(?:tymczasow\w*\s+)?kontrol\w*\s+graniczn|przedłużon\w*\s+(?:tymczasow\w*\s+)?kontrol\w*\s+graniczn)/iu.test(text);
 return restricted?'RESTRICTED' as const:null;
}

function instructionsFrom(text:string){
 return clean(text).split(/(?<=[.!?])\s+/u).filter(s=>/(podróżn|kierowc|prosimy|sugerujemy|zalecamy|uwzględni)/iu.test(s)).slice(0,4);
}

export function parseSgArticle(html:string,url:string,now=new Date()):Event|null{
 const u=articleUrl(url),$=cheerio.load(html);
 const head=$('.head').first(),article=$('article.txt').first();
 if(head.length!==1||article.length!==1)throw new Error('SG_ARTICLE_CONTRACT_CHANGED');
 const title=clean(head.children('h2').first().text());
 const lead=clean(head.children('h3').first().text());
 const body=clean(article.text());
 const dateText=clean(head.find('.metryka .data').first().text());
 if(!title||title.length>350||!body||body.length>40000||!/^\d{2}\.\d{2}\.\d{4}$/.test(dateText))throw new Error('SG_ARTICLE_CONTRACT_CHANGED');
 const date=DateTime.fromFormat(dateText,'dd.MM.yyyy',{zone:'Europe/Warsaw'});
 if(!date.isValid||date.toMillis()>now.getTime()+36*3600_000)throw new Error('SG_DATE_INVALID');
 const kind=operationalKind(title,lead,body);
 if(!kind)return null;
 const regions=provinceRegions(title+' '+lead+' '+body);
 const id=u.pathname.match(/^\/pl\/aktualnosci\/(\d+),/)?.[1];
 if(!id)throw new Error('SG_ID_INVALID');
 const exercise=/ćwicz|cwicz|exercise/iu.test(title+' '+lead+' '+body);
 const description=clean([lead,body].filter(Boolean).join(' '));
 const severity:Event['severity']=kind==='CLOSED'?'HIGH':kind==='RESTRICTED'?'NORMAL':'INFORMATIONAL';
 const lifecycle:Event['lifecycle']=kind==='ENDED'?'ENDED':'UNKNOWN';
 return eventSchema.parse({
  id:'SG-'+id,title,description,eventType:'BORDER',severity,verification:'CONFIRMED',lifecycle,
  messageContext:exercise?'EXERCISE':'ACTUAL',regions,geographicScope:regions.length?'REGIONAL':'UNKNOWN',
  publishedAt:null,publicationDate:date.toISODate(),retrievedAt:now.toISOString(),validFrom:null,validTo:null,
  sources:[{id:'SG',name:'Straż Graniczna',url:u.href,tier:1}],instructions:instructionsFrom(lead+' '+body),
  officialWarning:false,reviewed:false,revision:1,correction:null,latitude:null,longitude:null,geometry:null,
  locationText:title,areaPrecision:regions.length?'PROVINCE':'UNKNOWN',adapterVersion:SG_VERSION,
  sourceContentHash:createHash('sha256').update(JSON.stringify({title,lead,body,date:date.toISODate()})).digest('hex'),isDemo:false
 });
}

async function fetchInChunks(urls:string[],fetchText:(url:string)=>Promise<string>,now:Date){
 const events:Event[]=[];
 for(let i=0;i<urls.length;i+=5){
  const chunk=urls.slice(i,i+5);
  const parsed=await Promise.all(chunk.map(async url=>parseSgArticle(await fetchText(url),url,now)));
  events.push(...parsed.filter((e):e is Event=>e!==null));
 }
 return events;
}

export const sgAdapter:SourceAdapter={
 id:'SG',version:SG_VERSION,minSyncIntervalSeconds:900,
 async sync({now,fetchText,previousEvents=[]}){
  const pages=[SG_INDEX,SG_INDEX+'?page=1'];
  const recent=(await Promise.all(pages.map(async u=>parseSgIndex(await fetchText(u))))).flat();
  const previous=previousEvents.filter(e=>e.sources.some(s=>s.id==='SG')&&!['ENDED','CANCELLED','EXPIRED'].includes(e.lifecycle)).map(e=>e.sources.find(s=>s.id==='SG')!.url).filter(isAllowedSgUrl).slice(0,10);
  const urls=[...new Set([...recent,...previous])].slice(0,30);
  const events=await fetchInChunks(urls,fetchText,now);
  return {events,complete:false,coverage:'RECENT_PUBLICATIONS',pagesFetched:pages.length};
 }
};

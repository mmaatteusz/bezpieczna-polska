import * as cheerio from 'cheerio';
import {DateTime} from 'luxon';
import {createHash} from 'node:crypto';
import {eventSchema,REGIONS,type Event,type Health} from './domain.js';
import {Store} from './store.js';
export const SOURCES=[
 {id:'RCB',name:'Rządowe Centrum Bezpieczeństwa',url:'https://www.gov.pl/web/rcb'},
 {id:'RSO',name:'Regionalny System Ostrzegania',url:'https://komunikaty.tvp.pl/'},
 {id:'CERT',name:'CERT Polska',url:'https://cert.pl/'},
 {id:'PAA',name:'Państwowa Agencja Atomistyki',url:'https://www.gov.pl/web/paa'},
 {id:'SG',name:'Straż Graniczna',url:'https://www.strazgraniczna.pl/'},
 {id:'LEVELS',name:'Stopnie alarmowe RP',url:'https://www.gov.pl/web/rcb'},
 {id:'SHELTERS',name:'Punkty schronienia',url:'https://gdziesieukryc.pl/'},
 {id:'UA',name:'Alarmy Ukrainy — adapter nieaktywny',url:'https://alerts.in.ua/'}
];
export async function initializeSources(store:Store){const existing=await store.health();for(const s of SOURCES)if(!existing.some(h=>h.id===s.id))await store.setHealth({...s,state:'NOT_CONFIGURED',lastSuccess:null,lastFailure:null,lastItemTime:null,failureCount:0,responseTime:null,maxAgeSeconds:600,complete:false});}
export function messageContext(text:string):Event['messageContext']{return /ćwicz|cwicz|exercise/i.test(text)?'EXERCISE':/test syren|test systemu/i.test(text)?'TEST':'UNKNOWN';}
function base(id:string,title:string,description:string,sourceId:string,url:string,now:Date):Event{return eventSchema.parse({id,title,description,eventType:'OTHER',severity:'NORMAL',verification:'UNVERIFIED',lifecycle:'UNKNOWN',messageContext:messageContext(title+' '+description),regions:[],geographicScope:'UNKNOWN',publishedAt:null,retrievedAt:now.toISOString(),validFrom:null,validTo:null,sources:[{id:sourceId,name:SOURCES.find(s=>s.id===sourceId)!.name,url,tier:1}],instructions:[],officialWarning:false,reviewed:false,revision:1,correction:null,latitude:null,longitude:null,isDemo:false});}
export function parseRcbIndex(html:string):string[]{const $=cheerio.load(html);const urls=new Set<string>();$('main a[href]').each((_,a)=>{const href=$(a).attr('href')!;const u=new URL(href,'https://www.gov.pl');if(u.hostname==='www.gov.pl'&&/^\/web\/rcb\/alert-rcb-.+/.test(u.pathname))urls.add(u.href);});if(!urls.size)throw new Error('RCB_HTML_CONTRACT_CHANGED');return [...urls].slice(0,10);}
export function parseRcbArticle(html:string,url:string,now=new Date()):Event{const $=cheerio.load(html);const title=$('article h2').first().text().trim();const content=$('article .editor-content').first().text().trim();if(!title||content.length<20)throw new Error('RCB_ARTICLE_CONTRACT_CHANGED');return base('RCB-'+createHash('sha256').update(url).digest('hex').slice(0,24),title,content,'RCB',url,now);}
export function parseRso(xml:string,now=new Date()):Event[]{
 if(/<!DOCTYPE|<!ENTITY/i.test(xml))throw new Error('UNSAFE_XML');
 const $=cheerio.load(xml,{xml:true});const total=Number($('pagination_info').attr('totalItems'));const nodes=$('news');if(!Number.isInteger(total)||total!==nodes.length||!nodes.length)throw new Error('RSO_INCOMPLETE_OR_EMPTY');
 return nodes.map((_,node)=>{const n=$(node);const text=(k:string)=>n.children(k).text().trim();const id=text('id');if(!/^\d+$/.test(id))throw new Error('RSO_ID_INVALID');
  const e=base('RSO-'+id,text('title'),text('content')||text('shortcut'),'RSO',`https://komunikaty.tvp.pl/komunikaty/${id}/detale`,now);
  const date=(v:string)=>{if(!v)return null;const d=DateTime.fromFormat(v,'yyyy-MM-dd HH:mm:ss',{zone:'Europe/Warsaw'});if(!d.isValid||d.getPossibleOffsets().length!==1)throw new Error('RSO_DATE_INVALID_OR_AMBIGUOUS');return d.toUTC().toISO();};
  e.publishedAt=date(text('created_at'));e.validFrom=date(text('valid_from'));e.validTo=date(text('valid_to'));if(e.validFrom&&e.validTo&&e.validTo<=e.validFrom)throw new Error('RSO_DATE_ORDER');
  e.lifecycle=e.validFrom&&Date.parse(e.validFrom)>now.getTime()?'SCHEDULED':e.validTo&&Date.parse(e.validTo)<=now.getTime()?'EXPIRED':e.validTo?'ACTIVE':'UNKNOWN';
  e.regions=n.find('province').map((_,p)=>{const name=$(p).text().toLocaleLowerCase('pl');const code=Object.keys(REGIONS).find(k=>REGIONS[k].toLocaleLowerCase('pl')===name);if(!code)throw new Error('RSO_UNKNOWN_REGION');return code;}).get();e.geographicScope=e.regions.length?'REGIONAL':'UNKNOWN';
  const alarm=text('rso_alarm');if(!['0','1'].includes(alarm))throw new Error('RSO_ALARM_INVALID');e.severity=alarm==='1'?'HIGH':'NORMAL';
  for(const k of ['latitude','longitude'] as const){if(text(k))e[k]=Number(text(k));}
  return eventSchema.parse(e);
 }).get();
}
export async function fetchPublic(url:string):Promise<string>{
 const u=new URL(url);if(u.protocol!=='https:'||u.username||u.password||u.port||!['www.gov.pl','komunikaty.tvp.pl'].includes(u.hostname))throw new Error('SOURCE_URL_DENIED');
 const response=await fetch(u,{redirect:'error',signal:AbortSignal.timeout(20000),headers:{'User-Agent':'BezpiecznaPolska-preview/0.1 (source contract evaluation)','Accept':'text/html,application/xml'}});if(!response.ok||!response.body)throw new Error('SOURCE_HTTP_ERROR');
 let size=0;const chunks:Uint8Array[]=[];for await(const chunk of response.body){size+=chunk.length;if(size>4*1024*1024)throw new Error('SOURCE_TOO_LARGE');chunks.push(chunk);}return Buffer.concat(chunks).toString('utf8');
}
export async function ingest(store:Store){await initializeSources(store);for(const source of SOURCES.filter(s=>['RCB','RSO'].includes(s.id))){const previous=(await store.health()).find(s=>s.id===source.id)!;const begin=Date.now();try{
 const now=new Date();let items:Event[];
 if(source.id==='RSO')items=parseRso(await fetchPublic('https://komunikaty.tvp.pl/komunikatyxml/wszystkie/wszystkie/0?_format=xml'),now);
 else{items=[];const urls=parseRcbIndex(await fetchPublic(source.url));for(const url of urls)items.push(parseRcbArticle(await fetchPublic(url),url,now));}
 for(const e of items)await store.put(e);
 const published=items.map(e=>e.publishedAt).filter((v):v is string=>v!==null).sort();await store.setHealth({...previous,state:'HEALTHY',lastSuccess:new Date().toISOString(),lastItemTime:published.at(-1)??null,responseTime:Date.now()-begin,failureCount:0,complete:false});
 }catch{await store.setHealth({...previous,state:'BROKEN',lastFailure:new Date().toISOString(),failureCount:previous.failureCount+1,responseTime:Date.now()-begin,complete:false});}}}

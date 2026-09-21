import * as cheerio from 'cheerio';
import {createHash} from 'node:crypto';
import {DateTime} from 'luxon';
import {eventSchema,REGIONS,type Event} from './domain.js';
import type {SourceAdapter} from './source-adapter.js';
import {WCZK_SOURCES} from './wczk-registry.js';

export const WCZK_PODKARPACKIE='https://rzeszow.uw.gov.pl/wczk/ostrzezenia';
const version='1.0.0';
const clean=(s:string)=>s.replace(/\s+/g,' ').trim();
function localDate(time:string,date:string){
 const d=DateTime.fromFormat(`${date} ${time}`,'dd.MM.yyyy HH:mm',{zone:'Europe/Warsaw'});
 if(!d.isValid||d.getPossibleOffsets().length!==1)throw new Error('WCZK_DATE_INVALID_OR_AMBIGUOUS');
 return d.toUTC().toISO()!;
}
export function parsePodkarpackie(html:string,now=new Date()):Event[]{
 const $=cheerio.load(html),source=WCZK_SOURCES.find(s=>s.id==='WCZK-18')!;
 const notices=$('main .voivodeship-notices > .voivodeship-notice');
 if($('link[rel="canonical"]').attr('href')!==WCZK_PODKARPACKIE||!notices.length||notices.length>100||$('main .voivodeship-notice__content').length!==notices.length)throw new Error('WCZK_HTML_CONTRACT_CHANGED');
 const events=notices.map((_,node)=>{
  const notice=$(node),content=notice.find('.voivodeship-notice__content > .entry-content');
  const headings=content.children('h3'),title=clean(headings.text());
  const id=notice.find('.voivodeship-map').attr('class')?.match(/\bvoivodeship-map-(\d+)\b/)?.[1];
  const paragraphs=content.children('p').map((_,p)=>clean($(p).text())).get();
  const description=paragraphs.join('\n');
  if(content.length!==1||headings.length!==1||!id||!/^Ostrzeżenie (hydrologiczne|meteorologiczne):/.test(title)||paragraphs.length<3)throw new Error('WCZK_HTML_CONTRACT_CHANGED');
  const validity=paragraphs.filter(p=>/^Ważność\s*:/i.test(p)),areas=paragraphs.filter(p=>/^Obszar\s*:/i.test(p));
  if(validity.length!==1||areas.length!==1)throw new Error('WCZK_FIELDS_CHANGED');
  const from=validity[0].match(/od godz\.\s*(\d{2}:\d{2})\s*dnia\s*(\d{2}\.\d{2}\.\d{4})/i);
  const until=validity[0].match(/do godz\.\s*(\d{2}:\d{2})\s*dnia\s*(\d{2}\.\d{2}\.\d{4})/i);
  if(!from||(!until&&!/do odwołania/i.test(validity[0])))throw new Error('WCZK_VALIDITY_CHANGED');
  const validFrom=localDate(from[1],from[2]),validTo=until?localDate(until[1],until[2]):null;
  const locationText=areas[0].replace(/^Obszar\s*:\s*/i,'');
  const regions=Object.entries(REGIONS).filter(([,name])=>new RegExp('(?<![\\p{L}-])'+name+'(?![\\p{L}-])','iu').test(locationText)).map(([id])=>id);
  // Do not substitute the publisher's location for the affected area.
  if(!regions.length)throw new Error('WCZK_AREA_UNRESOLVED');
  const correction=paragraphs.find(p=>/^(Sprostowanie|Korekta|Odwołanie)\s*:/i.test(p))??null;
  const cancelled=paragraphs.some(p=>/^Odwołanie\s*:/i.test(p));
  return eventSchema.parse({id:`WCZK-18-${id}`,title,description,eventType:'WEATHER',severity:'NORMAL',verification:'CONFIRMED',lifecycle:cancelled?'CANCELLED':Date.parse(validFrom)>+now?'SCHEDULED':validTo&&Date.parse(validTo)<=+now?'EXPIRED':'ACTIVE',messageContext:/ćwicz|test syren/i.test(description)?'EXERCISE':'ACTUAL',regions,geographicScope:'REGIONAL',publishedAt:null,retrievedAt:now.toISOString(),validFrom,validTo,sources:[{id:source.id,name:source.name,url:source.url,tier:1}],instructions:[],officialWarning:true,reviewed:false,revision:1,correction,latitude:null,longitude:null,locationText,areaPrecision:'PROVINCE_SUBSET',geometry:null,adapterVersion:version,sourceContentHash:createHash('sha256').update(content.html()??'').digest('hex'),isDemo:false});
 }).get();
 if(new Set(events.map(e=>e.id)).size!==events.length)throw new Error('WCZK_DUPLICATE_ID');
 return events;
}
export const podkarpackieAdapter:SourceAdapter={id:'WCZK-18',version,minSyncIntervalSeconds:900,async sync({now,fetchText}){
 const events=parsePodkarpackie(await fetchText(WCZK_PODKARPACKIE),now);
 // A bounded publication list cannot prove all hazards have ended.
 return {events,complete:false,coverage:'RECENT_PUBLICATIONS',pagesFetched:1};
}};
export const wczkAdapters=[podkarpackieAdapter];

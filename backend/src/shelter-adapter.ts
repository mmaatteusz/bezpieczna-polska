import {createHash} from 'node:crypto';
import * as cheerio from 'cheerio';
import {parse} from 'csv-parse/sync';
import {z} from 'zod';
import {REGIONS} from './domain.js';
import {shelterSchema,type Shelter} from './shelter.js';
import type {SourceAdapter} from './source-adapter.js';

export const SHELTER_DATASET='https://api.dane.gov.pl/1.4/datasets/28058';
export const SHELTER_CATALOG='https://gdziesieukryc.pl/PS_XML/punkty_schronienia.xml';
export const SHELTER_CSV='https://gdziesieukryc.pl/PS_XML/punkty_schronienia.csv';
export const SHELTER_DATASET_PAGE='https://dane.gov.pl/pl/dataset/28058,punkty-schronienia-w-polsce';
const headers=['Identyfikator publiczny','Nazwa','Rodzaj obiektu','Opis ogolny','Gmina','Powiat','Wojewodztwo','Szerokosc geograficzna','Dlugosc geograficzna','Adres','Dostepnosc'];
export function parseShelterCatalog(xml:string,now:Date){
 if(/<!DOCTYPE|<!ENTITY/i.test(xml))throw new Error('SHELTER_UNSAFE_XML');
 const $=cheerio.load(xml,{xml:true});
 const dataset=$('dataset').filter((_,e)=>$(e).children('extIdent').text()==='ps-gdziesieukryc-001');
 const resource=dataset.find('resource').filter((_,e)=>$(e).children('extIdent').text()==='ps-csv-001');
 if(dataset.length!==1||resource.length!==1||dataset.attr('status')!=='published'||resource.attr('status')!=='published'||resource.children('url').text()!==SHELTER_CSV||dataset.find('dbOrCopyrightedLicenseChosen').text()!=='CC BY 4.0')throw new Error('SHELTER_CATALOG_CONTRACT_CHANGED');
 const dataDate=z.iso.date().parse(resource.children('dataDate').text());
 const sourceUpdatedAt=z.iso.datetime({offset:true}).parse(resource.children('lastUpdateDate').text());
 const count=Number(resource.children('description').children('polish').text().match(/zawierający\s+(\d+)\s+rekordów/)?.[1]);
 if(!Number.isInteger(count)||count<1||count>500000)throw new Error('SHELTER_COUNT_MISSING');
 const age=now.getTime()-Date.parse(sourceUpdatedAt);
 if(age< -86400000||Date.parse(dataDate)>now.getTime()+86400000)throw new Error('SHELTER_FUTURE_DATE');
 if(age>14*86400000||now.getTime()-Date.parse(dataDate)>14*86400000)throw new Error('SHELTER_DATA_OUTDATED');
 return {dataDate,sourceUpdatedAt,count};
}
export function parseShelterCsv(csv:string,meta:ReturnType<typeof parseShelterCatalog>):Shelter[]{
 const rows=parse(csv,{bom:true,columns:(found:string[])=>{
  if(JSON.stringify(found)!==JSON.stringify(headers))throw new Error('SHELTER_CSV_COLUMNS_CHANGED');return found;
 },skip_empty_lines:true,max_record_size:20000}) as Record<string,string>[];
 if(rows.length!==meta.count)throw new Error('SHELTER_COUNT_MISMATCH');
 const ids=new Set<string>();
 return rows.map(r=>{
  const id='PSP-'+r[headers[0]];
  if(ids.has(id))throw new Error('SHELTER_DUPLICATE_ID');ids.add(id);
  const regionId=Object.keys(REGIONS).find(k=>REGIONS[k].toLocaleLowerCase('pl')===r.Wojewodztwo.toLocaleLowerCase('pl'));
  const coordinate=(value:string)=>/^-?\d+(\.\d+)?$/.test(value)?Number(value):NaN;
  return shelterSchema.parse({id,sourceId:'SHELTERS',name:r.Nazwa,sourceType:r['Rodzaj obiektu'],category:'SHELTER_POINT',protectionClass:'UNKNOWN',description:r['Opis ogolny'],address:r.Adres,municipality:r.Gmina,county:r.Powiat,regionId,
   latitude:coordinate(r['Szerokosc geograficzna']),longitude:coordinate(r['Dlugosc geograficzna']),
   availability:({'Całodobowa':'24H','Na żądanie':'ON_REQUEST','Określone godziny':'LIMITED_HOURS'} as Record<string,string>)[r.Dostepnosc]??'UNKNOWN',sourceAvailability:r.Dostepnosc,
   openingHours:null,capacity:null,wheelchairAccess:'UNKNOWN',dataDate:meta.dataDate,sourceUpdatedAt:meta.sourceUpdatedAt,
   sourceUrl:SHELTER_CSV,datasetUrl:SHELTER_DATASET_PAGE,license:'CC BY 4.0',publisher:'Komenda Główna Państwowej Straży Pożarnej'});
 });
}
export const shelterAdapter:SourceAdapter={id:'SHELTERS',version:'psp-csv/1.0.0',minSyncIntervalSeconds:21600,
 async sync({now,fetchText}){
  const catalog=JSON.parse(await fetchText(SHELTER_DATASET));
  if(catalog.data?.id!=='28058'||catalog.data?.relationships?.institution?.data?.id!=='22'||catalog.data?.attributes?.license_name!=='CC BY 4.0'||catalog.data?.attributes?.source?.url!==SHELTER_CATALOG)throw new Error('SHELTER_PUBLISHER_CONTRACT_CHANGED');
  const before=parseShelterCatalog(await fetchText(SHELTER_CATALOG),now);
  const csv=await fetchText(SHELTER_CSV),shelters=parseShelterCsv(csv,before);
  const after=parseShelterCatalog(await fetchText(SHELTER_CATALOG),now);
  if(JSON.stringify(before)!==JSON.stringify(after))throw new Error('SHELTER_EXPORT_CHANGED_DURING_SYNC');
  return {events:[],shelters,complete:true,coverage:'FACILITY_CATALOG',pagesFetched:4,
   metadata:{dataDate:before.dataDate,sourceUpdatedAt:before.sourceUpdatedAt,sourceContentHash:createHash('sha256').update(csv).digest('hex'),sourceUrl:SHELTER_CSV,datasetUrl:SHELTER_DATASET_PAGE,license:'CC BY 4.0'}};
 }
};

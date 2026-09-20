import {createHash} from 'node:crypto';
import {inflateRawSync} from 'node:zlib';
import {parse} from 'csv-parse/sync';
import {z} from 'zod';
import {REGIONS} from './domain.js';
import {shelterSchema,type Shelter} from './shelter.js';
import type {SourceAdapter} from './source-adapter.js';

export const SHELTER_DATASET='https://api.dane.gov.pl/1.4/datasets/28058';
export const SHELTER_RESOURCE='https://api.dane.gov.pl/1.4/resources/1393918';
export const SHELTER_DOWNLOAD='https://api.dane.gov.pl/resources/1393918,punkty-schronienia-dane-csv/file';
export const SHELTER_ORIGIN_CSV='https://gdziesieukryc.pl/PS_XML/punkty_schronienia.csv';
export const SHELTER_ARCHIVE='https://api.dane.gov.pl/datasets/28058,punkty-schronienia-w-polsce/resources/files/download';
export const SHELTER_DATASET_PAGE='https://dane.gov.pl/pl/dataset/28058,punkty-schronienia-w-polsce';
const headers=['Identyfikator publiczny','Nazwa','Rodzaj obiektu','Opis ogolny','Gmina','Powiat','Wojewodztwo','Szerokosc geograficzna','Dlugosc geograficzna','Adres','Dostepnosc'];

export function parseShelterResource(text:string,now:Date){
 const root=JSON.parse(text) as any,data=root?.data,attributes=data?.attributes;
 if(data?.id!=='1393918'||data?.type!=='resource'||data?.relationships?.dataset?.data?.id!=='28058'||data?.relationships?.institution?.data?.id!=='22')throw new Error('SHELTER_RESOURCE_CONTRACT_CHANGED');
 if(attributes?.format!=='csv'||attributes?.download_url!==SHELTER_DOWNLOAD||attributes?.file_url!==SHELTER_ORIGIN_CSV)throw new Error('SHELTER_RESOURCE_CONTRACT_CHANGED');
 const dataDate=z.iso.date().parse(attributes.data_date);
 const sourceUpdatedAt=z.iso.datetime({offset:true}).parse(attributes.modified);
 const count=Number(String(attributes.description??'').match(/zawieraj\p{L}*\s+(\d+)\s+rekord/iu)?.[1]);
 if(!Number.isInteger(count)||count<1||count>500000)throw new Error('SHELTER_COUNT_MISSING');
 const age=now.getTime()-Date.parse(sourceUpdatedAt);
 if(age< -86400000||Date.parse(dataDate)>now.getTime()+86400000)throw new Error('SHELTER_FUTURE_DATE');
 if(age>14*86400000||now.getTime()-Date.parse(dataDate)>14*86400000)throw new Error('SHELTER_DATA_OUTDATED');
 return {dataDate,sourceUpdatedAt,count};
}

type ZipEntry={name:string;method:number;flags:number;compressedSize:number;uncompressedSize:number;localOffset:number};
export function extractShelterCsv(zip:Uint8Array):string{
 const b=Buffer.from(zip.buffer,zip.byteOffset,zip.byteLength);
 if(b.length<22||b.length>32*1024*1024)throw new Error('SHELTER_ARCHIVE_SIZE_INVALID');
 let eocd=-1;
 for(let i=b.length-22;i>=Math.max(0,b.length-65557);i--){if(b.readUInt32LE(i)===0x06054b50){eocd=i;break;}}
 if(eocd<0)throw new Error('SHELTER_ARCHIVE_INVALID');
 const count=b.readUInt16LE(eocd+10),centralSize=b.readUInt32LE(eocd+12),centralOffset=b.readUInt32LE(eocd+16);
 if(count<1||count>100||centralOffset+centralSize>eocd)throw new Error('SHELTER_ARCHIVE_INVALID');
 const entries:ZipEntry[]=[];let offset=centralOffset;
 for(let i=0;i<count;i++){
  if(offset+46>b.length||b.readUInt32LE(offset)!==0x02014b50)throw new Error('SHELTER_ARCHIVE_INVALID');
  const flags=b.readUInt16LE(offset+8),method=b.readUInt16LE(offset+10),compressedSize=b.readUInt32LE(offset+20),uncompressedSize=b.readUInt32LE(offset+24);
  const nameLength=b.readUInt16LE(offset+28),extraLength=b.readUInt16LE(offset+30),commentLength=b.readUInt16LE(offset+32),localOffset=b.readUInt32LE(offset+42);
  const end=offset+46+nameLength+extraLength+commentLength;if(end>b.length)throw new Error('SHELTER_ARCHIVE_INVALID');
  const name=b.subarray(offset+46,offset+46+nameLength).toString((flags&0x800)?'utf8':'utf8');
  if((flags&1)!==0||compressedSize===0xffffffff||uncompressedSize===0xffffffff||uncompressedSize>64*1024*1024)throw new Error('SHELTER_ARCHIVE_UNSUPPORTED');
  entries.push({name,method,flags,compressedSize,uncompressedSize,localOffset});offset=end;
 }
 const candidates=entries.filter(e=>/1393918/i.test(e.name)&&/\.csv$/i.test(e.name)&&!e.name.endsWith('/'));
 if(candidates.length!==1)throw new Error('SHELTER_ARCHIVE_RESOURCE_AMBIGUOUS');
 const entry=candidates[0];if(![0,8].includes(entry.method))throw new Error('SHELTER_ARCHIVE_COMPRESSION_UNSUPPORTED');
 if(entry.localOffset+30>b.length||b.readUInt32LE(entry.localOffset)!==0x04034b50)throw new Error('SHELTER_ARCHIVE_INVALID');
 const localName=b.readUInt16LE(entry.localOffset+26),localExtra=b.readUInt16LE(entry.localOffset+28),start=entry.localOffset+30+localName+localExtra,end=start+entry.compressedSize;
 if(end>b.length)throw new Error('SHELTER_ARCHIVE_INVALID');
 const compressed=b.subarray(start,end),raw=entry.method===0?Buffer.from(compressed):inflateRawSync(compressed);
 if(raw.length!==entry.uncompressedSize||raw.length>64*1024*1024)throw new Error('SHELTER_ARCHIVE_LENGTH_MISMATCH');
 return new TextDecoder('utf-8',{fatal:true}).decode(raw);
}

export function parseShelterCsv(csv:string,meta:ReturnType<typeof parseShelterResource>):Shelter[]{
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
   sourceUrl:SHELTER_ARCHIVE,datasetUrl:SHELTER_DATASET_PAGE,license:'CC BY 4.0',publisher:'Komenda Główna Państwowej Straży Pożarnej'});
 });
}

export const shelterAdapter:SourceAdapter={id:'SHELTERS',version:'dane-gov-pl-archive/3.0.0',minSyncIntervalSeconds:21600,
 async sync({now,fetchText,fetchBytes}){
  const catalog=JSON.parse(await fetchText(SHELTER_DATASET));
  if(catalog.data?.id!=='28058'||catalog.data?.relationships?.institution?.data?.id!=='22'||catalog.data?.attributes?.license_name!=='CC BY 4.0'||catalog.data?.relationships?.resources?.meta?.count!==1||catalog.data?.attributes?.archived_resources_files_url!==SHELTER_ARCHIVE)throw new Error('SHELTER_PUBLISHER_CONTRACT_CHANGED');
  const before=parseShelterResource(await fetchText(SHELTER_RESOURCE),now);
  const archive=await fetchBytes(SHELTER_ARCHIVE),csv=extractShelterCsv(archive),shelters=parseShelterCsv(csv,before);
  const after=parseShelterResource(await fetchText(SHELTER_RESOURCE),now);
  if(JSON.stringify(before)!==JSON.stringify(after))throw new Error('SHELTER_EXPORT_CHANGED_DURING_SYNC');
  return {events:[],shelters,complete:true,coverage:'FACILITY_CATALOG',pagesFetched:4,
   metadata:{dataDate:before.dataDate,sourceUpdatedAt:before.sourceUpdatedAt,sourceContentHash:createHash('sha256').update(csv).digest('hex'),sourceUrl:SHELTER_ARCHIVE,datasetUrl:SHELTER_DATASET_PAGE,license:'CC BY 4.0'}};
 }
};

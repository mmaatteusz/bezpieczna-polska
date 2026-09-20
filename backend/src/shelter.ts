import {z} from 'zod';
import {REGIONS} from './domain.js';

// A permanent facility is not a warning Event and never affects hazard status.
export const shelterSchema=z.object({
 id:z.string().regex(/^PSP-OZO-[A-F0-9]{12}$/),sourceId:z.literal('SHELTERS'),
 name:z.string().min(1).max(300),sourceType:z.string().min(1).max(300),
 category:z.literal('SHELTER_POINT'),protectionClass:z.literal('UNKNOWN'),
 description:z.string().max(10000),address:z.string().min(1).max(1000),
 municipality:z.string().min(1).max(200),county:z.string().min(1).max(200),
 regionId:z.string().refine(s=>s in REGIONS),
 latitude:z.number().min(49).max(55),longitude:z.number().min(14).max(25),
 availability:z.enum(['24H','ON_REQUEST','LIMITED_HOURS','UNKNOWN']),sourceAvailability:z.string().max(300),
 openingHours:z.null(),capacity:z.null(),wheelchairAccess:z.literal('UNKNOWN'),
 dataDate:z.iso.date(),sourceUpdatedAt:z.iso.datetime({offset:true}),
 sourceUrl:z.literal('https://gdziesieukryc.pl/PS_XML/punkty_schronienia.csv'),
 datasetUrl:z.literal('https://dane.gov.pl/pl/dataset/28058,punkty-schronienia-w-polsce'),
 license:z.literal('CC BY 4.0'),publisher:z.literal('Komenda Główna Państwowej Straży Pożarnej'),
});
export type Shelter=z.infer<typeof shelterSchema>;
export type ShelterFilter={regionId:string;q:string;limit:number;offset:number;version?:string;bbox?:[number,number,number,number]};
export function searchText(value:string){return value.normalize('NFD').replace(/[\u0300-\u036f]/g,'').toLocaleLowerCase('pl').replace(/ł/g,'l');}

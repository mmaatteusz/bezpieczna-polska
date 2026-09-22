import {z} from 'zod';
import {geometrySchema,type Event} from './domain.js';
import type {UaRegion} from './ukraine-adapter.js';
// Public UN OCHA administrative boundary service; no operational data.
export const UA_BOUNDARY_SOURCE='https://gis.unocha.org/server/rest/services/Hosted/UKR_Simplified_Boundaries/FeatureServer/1';
export const UA_BOUNDARY_QUERY=UA_BOUNDARY_SOURCE+'/query?where=1%3D1&outFields=adm1_name,adm1_name1,adm1_name2,adm1_name3,adm1_pcode&outSR=4326&f=geojson';
const normalize=(s:string)=>s.normalize('NFC').toLowerCase().replace(/[’ʼ`]/g,"'").replace(/\s+/g,' ').trim();
export function parseUaBoundaries(raw:unknown){
 const data=z.object({type:z.literal('FeatureCollection'),exceededTransferLimit:z.literal(false).optional(),features:z.array(z.object({type:z.literal('Feature'),properties:z.object({adm1_name:z.string().nullable(),adm1_name1:z.string().nullable(),adm1_name2:z.string().nullable(),adm1_name3:z.string().nullable(),adm1_pcode:z.string().regex(/^UA[0-9]+$/)}),geometry:geometrySchema.refine(g=>g.type!=='Point')})).min(1).max(30)}).parse(raw);
 if(new Set(data.features.map(f=>f.properties.adm1_pcode)).size!==data.features.length)throw new Error('UA_BOUNDARY_DUPLICATE');
 return data.features;
}
export function enrichUaGeometry(events:Event[],regions:UaRegion[],raw:unknown){
 const features=parseUaBoundaries(raw);
 return events.map(e=>{
  const r=regions.find(r=>r.id===e.ukraine?.regionId);
  if(!r||r.type!=='State')return e;
  // Exact publisher name only. Never map a district/city to its parent oblast.
  const matches=features.filter(f=>[f.properties.adm1_name,f.properties.adm1_name1,f.properties.adm1_name2,f.properties.adm1_name3].some(n=>n!==null&&normalize(n)===normalize(r.name)));
  if(matches.length!==1)return e;
  return {...e,geometry:matches[0].geometry,geometrySource:UA_BOUNDARY_SOURCE};
 });
}

import {DatabaseSync} from 'node:sqlite';
import {createHash} from 'node:crypto';
import pg from 'pg';
import {eventSchema,type Event,type Health} from './domain.js';
type Row=Record<string,unknown>;
export interface Db {all(sql:string,params?:unknown[]):Promise<Row[]>;run(sql:string,params?:unknown[]):Promise<void>;close():Promise<void>;}
export function openDb(url?:string,path='bezpieczna.db'):Db{
 if(url){const p=new pg.Pool({connectionString:url,max:5});const convert=(s:string)=>{let i=0;return s.replace(/\?/g,()=>`$${++i}`);};return {all:async(s,v=[])=>{return (await p.query(convert(s),v)).rows as Row[];},run:async(s,v=[])=>{await p.query(convert(s),v);},close:async()=>p.end()};}
 const d=new DatabaseSync(path);d.exec('PRAGMA journal_mode=WAL; PRAGMA foreign_keys=ON;');return {all:async(s,v=[])=>d.prepare(s).all(...v as (string|number|null)[]) as Row[],run:async(s,v=[])=>{d.prepare(s).run(...v as (string|number|null)[]);},close:async()=>d.close()};
}
export class Store{
 constructor(readonly db:Db){}
 async init(){await this.db.run('CREATE TABLE IF NOT EXISTS event_revisions(event_id TEXT NOT NULL, revision INTEGER NOT NULL, payload TEXT NOT NULL, content_hash TEXT NOT NULL, actor TEXT NOT NULL, reason TEXT NOT NULL, recorded_at TEXT NOT NULL, PRIMARY KEY(event_id,revision))');await this.db.run('CREATE TABLE IF NOT EXISTS source_health(id TEXT PRIMARY KEY,payload TEXT NOT NULL)');}
 async events():Promise<Event[]>{const rows=await this.db.all('SELECT r.payload FROM event_revisions r JOIN (SELECT event_id,MAX(revision) AS rev FROM event_revisions GROUP BY event_id) last ON r.event_id=last.event_id AND r.revision=last.rev');return rows.map(r=>eventSchema.parse(JSON.parse(r.payload as string)));}
 async get(id:string){const r=await this.db.all('SELECT payload FROM event_revisions WHERE event_id=? ORDER BY revision DESC LIMIT 1',[id]);return r.length?eventSchema.parse(JSON.parse(r[0].payload as string)):null;}
 async put(input:Event,actor='adapter',reason='Source content updated',expectedRevision?:number){
  const e=eventSchema.parse(input);const previous=await this.get(e.id);
  if(expectedRevision!==undefined&&(previous?.revision??0)!==expectedRevision)throw new Error('REVISION_CONFLICT');
  if(actor==='adapter'&&previous?.reviewed)return false;
  const hash=(v:Event)=>{const {retrievedAt,revision,...stable}=v;return createHash('sha256').update(JSON.stringify(stable)).digest('hex');};
  if(previous&&hash(previous)===hash(e))return false;
  const next={...e,revision:(previous?.revision??0)+1};
  try{await this.db.run('INSERT INTO event_revisions(event_id,revision,payload,content_hash,actor,reason,recorded_at) VALUES(?,?,?,?,?,?,?)',[next.id,next.revision,JSON.stringify(next),hash(next),actor,reason,new Date().toISOString()]);}catch(err){if(err instanceof Error&&/unique|constraint|duplicate/i.test(err.message))throw new Error('REVISION_CONFLICT');throw err;}
  return true;
 }
 async timeline(id:string){return (await this.db.all('SELECT payload,actor,reason,recorded_at FROM event_revisions WHERE event_id=? ORDER BY revision',[id])).map(r=>({...r,payload:JSON.parse(r.payload as string)}));}
 async health():Promise<Health[]>{return (await this.db.all('SELECT payload FROM source_health')).map(r=>JSON.parse(r.payload as string) as Health);}
 async setHealth(h:Health){await this.db.run('INSERT INTO source_health(id,payload) VALUES(?,?) ON CONFLICT(id) DO UPDATE SET payload=excluded.payload',[h.id,JSON.stringify(h)]);}
}

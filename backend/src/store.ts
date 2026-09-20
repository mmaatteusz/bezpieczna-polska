import {DatabaseSync} from 'node:sqlite';
import {createHash} from 'node:crypto';
import pg from 'pg';
import {eventSchema,type Event,type Health} from './domain.js';
import {shelterSchema,searchText,type Shelter,type ShelterFilter} from './shelter.js';
type Row=Record<string,unknown>;
export interface Db {
 kind:'postgres'|'sqlite';
 all(sql:string,params?:unknown[]):Promise<Row[]>;
 run(sql:string,params?:unknown[]):Promise<void>;
 transaction<T>(work:(db:Db)=>Promise<T>):Promise<T>;
 close():Promise<void>;
}
export function openDb(url?:string,path='bezpieczna.db'):Db{
 if(url){
  const pool=new pg.Pool({connectionString:url,max:5});
  const convert=(s:string)=>{let i=0;return s.replace(/\?/g,()=>`$${++i}`);};
  const handle=(client:pg.Pool|pg.PoolClient):Db=>({kind:'postgres',
   all:async(s,v=[]) => (await client.query(convert(s),v)).rows as Row[],
   run:async(s,v=[])=>{await client.query(convert(s),v);},
   transaction:async work=>{
    const c=await pool.connect();
    try{await c.query('BEGIN ISOLATION LEVEL REPEATABLE READ');const result=await work(handle(c));await c.query('COMMIT');return result;}
    catch(e){await c.query('ROLLBACK');throw e;}finally{c.release();}
   },close:async()=>pool.end(),
  });return handle(pool);
 }
 const d=new DatabaseSync(path);d.exec('PRAGMA journal_mode=WAL; PRAGMA foreign_keys=ON;');
 const raw:Db={kind:'sqlite',all:async(s,v=[])=>d.prepare(s).all(...v as (string|number|null)[]) as Row[],run:async(s,v=[])=>{d.prepare(s).run(...v as (string|number|null)[]);},transaction:async()=>{throw new Error('NESTED_TRANSACTION_UNSUPPORTED');},close:async()=>d.close()};
 let tail:Promise<unknown>=Promise.resolve();
 const queued=<T>(job:()=>Promise<T>)=>{const result=tail.then(job);tail=result.catch(()=>{});return result;};
 return {...raw,all:(s,v)=>queued(()=>raw.all(s,v)),run:(s,v)=>queued(()=>raw.run(s,v)),close:()=>queued(()=>raw.close()),transaction:work=>queued(async()=>{
  d.exec('BEGIN');try{const result=await work(raw);d.exec('COMMIT');return result;}catch(e){d.exec('ROLLBACK');throw e;}
 })};
}
export class Store{
 constructor(readonly db:Db){}
 async init(){
  if(this.db.kind==='postgres')await this.db.run('CREATE EXTENSION IF NOT EXISTS postgis');
  await this.db.run('CREATE TABLE IF NOT EXISTS event_revisions(event_id TEXT NOT NULL, revision INTEGER NOT NULL, payload TEXT NOT NULL, content_hash TEXT NOT NULL, actor TEXT NOT NULL, reason TEXT NOT NULL, recorded_at TEXT NOT NULL, PRIMARY KEY(event_id,revision))');
  await this.db.run('CREATE TABLE IF NOT EXISTS source_health(id TEXT PRIMARY KEY,payload TEXT NOT NULL)');
  await this.db.run('CREATE TABLE IF NOT EXISTS shelters(id TEXT PRIMARY KEY,region_id TEXT NOT NULL,search_text TEXT NOT NULL,payload TEXT NOT NULL)');
  await this.db.run('CREATE INDEX IF NOT EXISTS shelter_region_idx ON shelters(region_id,id)');
  if(this.db.kind==='postgres'){
   // An indexed generated column keeps geometry and the audited event payload
   // in the same atomic write, including existing events during migration.
   await this.db.run(`ALTER TABLE event_revisions ADD COLUMN IF NOT EXISTS geom geometry(Geometry,4326) GENERATED ALWAYS AS (
    CASE WHEN payload::jsonb->'geometry' IS NOT NULL AND payload::jsonb->'geometry' <> 'null'::jsonb
     THEN ST_SetSRID(ST_GeomFromGeoJSON(payload::jsonb->'geometry'),4326)
     WHEN payload::jsonb->>'longitude' IS NOT NULL AND payload::jsonb->>'latitude' IS NOT NULL
     THEN ST_SetSRID(ST_MakePoint((payload::jsonb->>'longitude')::double precision,(payload::jsonb->>'latitude')::double precision),4326)
     ELSE NULL END) STORED CHECK (geom IS NULL OR ST_IsValid(geom))`);
   await this.db.run('CREATE INDEX IF NOT EXISTS event_geometry_gist ON event_revisions USING GIST (geom)');
   await this.db.run(`ALTER TABLE shelters ADD COLUMN IF NOT EXISTS geom geometry(Point,4326) GENERATED ALWAYS AS (ST_SetSRID(ST_MakePoint((payload::jsonb->>'longitude')::double precision,(payload::jsonb->>'latitude')::double precision),4326)) STORED`);
   await this.db.run('CREATE INDEX IF NOT EXISTS shelter_geometry_gist ON shelters USING GIST (geom)');
  }
 }
 async events():Promise<Event[]>{
  const rows=await this.db.all('SELECT r.payload FROM event_revisions r JOIN (SELECT event_id,MAX(revision) AS rev FROM event_revisions GROUP BY event_id) last ON r.event_id=last.event_id AND r.revision=last.rev');
  return rows.map(r=>eventSchema.parse(JSON.parse(r.payload as string))).sort((a,b)=>(b.publishedAt??b.publicationDate??'').localeCompare(a.publishedAt??a.publicationDate??'')||a.id.localeCompare(b.id));
 }
 async snapshot(){return this.db.transaction(async db=>{const s=new Store(db);return {events:await s.events(),health:await s.health()};});}
 async get(id:string){const r=await this.db.all('SELECT payload FROM event_revisions WHERE event_id=? ORDER BY revision DESC LIMIT 1',[id]);return r.length?eventSchema.parse(JSON.parse(r[0].payload as string)):null;}
 async put(input:Event,actor='adapter',reason='Source content updated',expectedRevision?:number){
  const e=eventSchema.parse(input);const previous=await this.get(e.id);
  if(expectedRevision!==undefined&&(previous?.revision??0)!==expectedRevision)throw new Error('REVISION_CONFLICT');
  if(actor==='adapter'&&previous?.reviewed)return false;
  // Formatting changes in upstream HTML must not generate user-facing alerts.
  const hash=(v:Event)=>{const {retrievedAt,revision,sourceContentHash,...stable}=v;return createHash('sha256').update(JSON.stringify(stable)).digest('hex');};
  if(previous&&hash(previous)===hash(e))return false;
  const next={...e,revision:(previous?.revision??0)+1};
  try{await this.db.run('INSERT INTO event_revisions(event_id,revision,payload,content_hash,actor,reason,recorded_at) VALUES(?,?,?,?,?,?,?)',[next.id,next.revision,JSON.stringify(next),hash(next),actor,reason,new Date().toISOString()]);}catch(err){if(err instanceof Error&&/unique|duplicate/i.test(err.message))throw new Error('REVISION_CONFLICT');throw err;}
  return true;
 }
 async applySync(events:Event[],health:Health){
  await this.db.transaction(async db=>{const s=new Store(db);for(const e of events)await s.put(e);await s.setHealth(health);});
 }
 async applyShelterSync(items:Shelter[],health:Health){
  if(health.id!=='SHELTERS'||health.coverage!=='FACILITY_CATALOG'||!health.complete||!items.length||items.length!==health.itemCount||!health.sourceContentHash)throw new Error('SHELTER_INVALID_BATCH');
  // Validate everything before beginning replacement. A failed transaction keeps
  // the entire previous national package and its previous success timestamp.
  const rows=items.map(s=>shelterSchema.parse(s));
  if(new Set(rows.map(s=>s.id)).size!==rows.length)throw new Error('SHELTER_DUPLICATE_ID');
  await this.db.transaction(async db=>{
   const scoped=new Store(db),previous=(await scoped.health()).find(h=>h.id==='SHELTERS');
   if(previous?.sourceContentHash!==health.sourceContentHash||previous?.sourceUpdatedAt!==health.sourceUpdatedAt||previous?.dataDate!==health.dataDate){
    await db.run('DELETE FROM shelters');
    for(let i=0;i<rows.length;i+=200){
     const batch=rows.slice(i,i+200),params=batch.flatMap(s=>[s.id,s.regionId,searchText(`${s.municipality} ${s.county} ${s.address}`),JSON.stringify(s)]);
     await db.run(`INSERT INTO shelters(id,region_id,search_text,payload) VALUES ${batch.map(()=>'(?,?,?,?)').join(',')}`,params);
    }
   }
   await scoped.setHealth(health);
  });
 }
 async shelterPage(filter:ShelterFilter){
  return this.db.transaction(db=>new Store(db).readShelterPage(filter));
 }
 private async readShelterPage({regionId,q,limit,offset,version,bbox}:ShelterFilter){
  const health=(await this.health()).find(h=>h.id==='SHELTERS')??null;
  if(version&&health?.sourceContentHash!==version)throw new Error('SHELTER_VERSION_CHANGED');
  const conditions:string[]=[],params:unknown[]=[];
  if(regionId!=='PL'){conditions.push('region_id=?');params.push(regionId);}
  if(q){conditions.push("search_text LIKE ? ESCAPE '!'");params.push('%'+searchText(q).replace(/[!%_]/g,s=>'!'+s)+'%');}
  if(bbox){
   if(this.db.kind!=='postgres')throw new Error('POSTGIS_REQUIRED');
   conditions.push('ST_Intersects(geom,ST_MakeEnvelope(?,?,?,?,4326))');params.push(...bbox);
  }
  const where=conditions.length?' WHERE '+conditions.join(' AND '):'';
  const total=Number((await this.db.all('SELECT COUNT(*) AS total FROM shelters'+where,params))[0].total);
  const rows=await this.db.all('SELECT payload FROM shelters'+where+' ORDER BY id LIMIT ? OFFSET ?',[...params,limit,offset]);
  return {items:rows.map(r=>shelterSchema.parse(JSON.parse(r.payload as string))),total,offset,limit,hasMore:offset+rows.length<total,version:health?.sourceContentHash??null,health,regionId,query:q};
 }
 async spatialEvents(bbox?:[number,number,number,number]){
  if(this.db.kind==='postgres'){
   const rows=await this.db.all(`SELECT r.payload FROM event_revisions r JOIN (SELECT event_id,MAX(revision) AS rev FROM event_revisions GROUP BY event_id) last ON r.event_id=last.event_id AND r.revision=last.rev WHERE r.geom IS NOT NULL${bbox?' AND ST_Intersects(r.geom,ST_MakeEnvelope(?,?,?,?,4326))':''} ORDER BY r.event_id`,bbox);
   return rows.map(r=>eventSchema.parse(JSON.parse(r.payload as string)));
  }
  if(bbox)throw new Error('POSTGIS_REQUIRED');
  return (await this.events()).filter(e=>e.geometry!==null);
 }
 async timeline(id:string){return (await this.db.all('SELECT payload,actor,reason,recorded_at FROM event_revisions WHERE event_id=? ORDER BY revision',[id])).map(r=>({...r,payload:JSON.parse(r.payload as string)}));}
 async health():Promise<Health[]>{return (await this.db.all('SELECT payload FROM source_health ORDER BY id')).map(r=>JSON.parse(r.payload as string) as Health);}
 async setHealth(h:Health){await this.db.run('INSERT INTO source_health(id,payload) VALUES(?,?) ON CONFLICT(id) DO UPDATE SET payload=excluded.payload',[h.id,JSON.stringify(h)]);}
}

import {openDb,type Db} from './store.js';
import {serverConfig} from './config.js';
import {migration001} from './migrations/001_initial.js';
import {migration002} from './migrations/002_worker_leases.js';

const migrations=[migration001,migration002] as const;
export const SCHEMA_VERSION=migrations.at(-1)!.version;

async function appliedVersions(db:Db){
 return (await db.all('SELECT version FROM schema_migrations ORDER BY version ASC')).map(row=>Number(row.version));
}
export async function assertSchema(db:ReturnType<typeof openDb>){
 const versions=await appliedVersions(db);
 if(versions.length!==migrations.length||versions.some((version,index)=>version!==migrations[index].version))throw new Error('Schema migration missing or incompatible');
 for(const table of ['event_revisions','incident_revisions','source_health','neptun_track_revisions','radiation_measurements','shelters','push_devices','push_outbox','worker_leases']){
  await db.all(`SELECT 1 FROM ${table} LIMIT 0`);
 }
 if(db.kind==='postgres'){
  const extensions=await db.all("SELECT extname FROM pg_extension WHERE extname='postgis'");
  if(extensions.length!==1)throw new Error('PostGIS extension missing');
 }
}
export async function migrate(db:ReturnType<typeof openDb>){
 await db.run('CREATE TABLE IF NOT EXISTS schema_migrations(version INTEGER PRIMARY KEY, applied_at TEXT NOT NULL)');
 const existing=await appliedVersions(db);
 if(existing.some(version=>version>SCHEMA_VERSION))throw new Error('Database schema is newer than this application');
 const applied=new Set(existing);
 for(const migration of migrations){
  if(applied.has(migration.version))continue;
  await db.transaction(async tx=>{
   await migration.up(tx);
   await tx.run('INSERT INTO schema_migrations(version,applied_at) VALUES(?,?)',[migration.version,new Date().toISOString()]);
  });
  applied.add(migration.version);
 }
 await assertSchema(db);
}
if(process.argv[1]&&import.meta.url===new URL('file://'+process.argv[1]).href){
 serverConfig();
 if(!process.env.DATABASE_URL)throw new Error('DATABASE_URL required for deployment migration');
 const db=openDb(process.env.DATABASE_URL);
 try{await migrate(db);console.log(JSON.stringify({level:'info',component:'migration',version:SCHEMA_VERSION,status:'complete'}));}
 finally{await db.close();}
}

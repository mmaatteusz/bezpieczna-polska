import {openDb,Store} from './store.js';
import {serverConfig} from './config.js';
export const SCHEMA_VERSION=1;
export async function assertSchema(db:ReturnType<typeof openDb>){
 const rows=await db.all('SELECT version FROM schema_migrations ORDER BY version DESC LIMIT 1');
 if(Number(rows[0]?.version)!==SCHEMA_VERSION)throw new Error('Schema migration missing or incompatible');
 for(const table of ['event_revisions','incident_revisions','source_health','neptun_track_revisions','radiation_measurements','shelters','push_devices','push_outbox']){
  await db.all(`SELECT 1 FROM ${table} LIMIT 0`);
 }
 if(db.kind==='postgres'){
  const extensions=await db.all("SELECT extname FROM pg_extension WHERE extname='postgis'");
  if(extensions.length!==1)throw new Error('PostGIS extension missing');
 }
}
export async function migrate(db:ReturnType<typeof openDb>){
 await db.run('CREATE TABLE IF NOT EXISTS schema_migrations(version INTEGER PRIMARY KEY, applied_at TEXT NOT NULL)');
 const rows=await db.all('SELECT version FROM schema_migrations ORDER BY version DESC LIMIT 1');
 if(rows.length&&Number(rows[0].version)>SCHEMA_VERSION)throw new Error('Database schema is newer than this application');
 await new Store(db).init();
 await db.run('INSERT INTO schema_migrations(version,applied_at) VALUES(?,?) ON CONFLICT(version) DO NOTHING',[SCHEMA_VERSION,new Date().toISOString()]);
 await assertSchema(db);
}
if(process.argv[1]&&import.meta.url===new URL('file://'+process.argv[1]).href){
 serverConfig();
 if(!process.env.DATABASE_URL)throw new Error('DATABASE_URL required for deployment migration');
 const db=openDb(process.env.DATABASE_URL);
 try{await migrate(db);console.log(JSON.stringify({level:'info',component:'migration',version:SCHEMA_VERSION,status:'complete'}));}
 finally{await db.close();}
}

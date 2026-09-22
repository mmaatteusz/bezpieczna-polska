import {openDb,Store} from './store.js';import {buildApp} from './app.js';import {ingest} from './adapters.js';
if(process.env.NODE_ENV==='production'&&!process.env.DATABASE_URL)throw new Error('Production requires DATABASE_URL with PostGIS');
const db=openDb(process.env.DATABASE_URL,process.env.SQLITE_PATH);const store=new Store(db);await store.init();const app=await buildApp(store,process.env.ADMIN_TOKEN);
let running=false;async function sync(){if(running)return;running=true;try{await ingest(store);}catch{console.error('Ingestion failed; existing data retained');}finally{running=false;}}
const timer=process.env.ENABLE_INGESTION!=='false'?setInterval(()=>void sync(),60000):null;if(timer)void sync();
await app.listen({port:Number(process.env.PORT??8080),host:process.env.HOST??'127.0.0.1'});
for(const signal of ['SIGINT','SIGTERM'])process.on(signal,()=>{void(async()=>{if(timer)clearInterval(timer);await app.close();await db.close();process.exit(0);})();});

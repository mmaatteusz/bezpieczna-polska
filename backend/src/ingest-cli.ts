import {openDb,Store} from './store.js';import {ingest} from './adapters.js';
const db=openDb(process.env.DATABASE_URL,process.env.SQLITE_PATH);try{const store=new Store(db);await store.init();await ingest(store);console.log(JSON.stringify({events:(await store.events()).length,sources:await store.health()},null,2));}finally{await db.close();}

import type {Db} from './store.js';
import {statfs,readFile} from 'node:fs/promises';

export async function initWorkerMetrics(db:Db){
 await db.run('CREATE TABLE IF NOT EXISTS worker_metrics(name TEXT PRIMARY KEY,started_at TEXT NOT NULL,finished_at TEXT,last_success_at TEXT,duration_ms INTEGER,error_code TEXT)');
}
export async function workerStarted(db:Db,name:string,now=new Date()){
 await db.run(`INSERT INTO worker_metrics(name,started_at) VALUES(?,?) ON CONFLICT(name) DO UPDATE SET started_at=excluded.started_at,finished_at=NULL`,[name,now.toISOString()]);
}
export async function workerFinished(db:Db,name:string,started:number,ok:boolean,now=new Date()){
 await db.run(`UPDATE worker_metrics SET finished_at=?,duration_ms=?,error_code=?,last_success_at=CASE WHEN ?=1 THEN ? ELSE last_success_at END WHERE name=? AND started_at=?`,[now.toISOString(),Math.max(0,now.getTime()-started),ok?null:'WORKER_FAILED',Number(ok),now.toISOString(),name,new Date(started).toISOString()]);
}
export async function operationalMetrics(db:Db,now=new Date()){
 const age=(value:unknown)=>typeof value==='string'&&Number.isFinite(Date.parse(value))?Math.max(0,(now.getTime()-Date.parse(value))/1000):null;
 const queue=await db.all('SELECT state,COUNT(*) AS count,MIN(created_at) AS oldest_at,MIN(next_attempt_at) AS next_due_at FROM push_outbox GROUP BY state');
 const intervals:Record<string,number>={ingest:60,'neptun-live':5,'ukraine-alarm':90,push:15};
 const workers=await db.all('SELECT * FROM worker_metrics ORDER BY name');
 let disk:unknown={state:'UNAVAILABLE'};
 try{const d=await statfs(process.env.MONITOR_DISK_PATH??'/');disk={state:'AVAILABLE',totalBytes:d.blocks*d.bsize,availableBytes:d.bavail*d.bsize,usedPercent:d.blocks?100*(1-d.bfree/d.blocks):0};}catch{}
 let backup:unknown={state:'NOT_CONFIGURED',ageSeconds:null};
 if(process.env.BACKUP_STATUS_FILE){
  try{const b=JSON.parse(await readFile(process.env.BACKUP_STATUS_FILE,'utf8'));const seconds=age(b.completedAt);if(seconds===null||typeof b.offVm!=='boolean')throw new Error();backup={state:'AVAILABLE',ageSeconds:seconds,offVm:b.offVm,restoreVerifiedAt:b.restoreVerifiedAt??null};}
  catch{backup={state:'UNAVAILABLE',ageSeconds:null};}
 }
 return {push:{states:Object.fromEntries(queue.map(q=>[String(q.state),{count:Number(q.count),oldestAgeSeconds:age(q.oldest_at),overdueSeconds:['PENDING','RETRY'].includes(String(q.state))?age(q.next_due_at):null}]))},workers:workers.map(w=>({name:w.name,scheduleLagSeconds:Math.max(0,(age(w.started_at)??0)-(intervals[String(w.name)]??0)),running:w.finished_at===null,runAgeSeconds:w.finished_at===null?age(w.started_at):null,lastSuccessAgeSeconds:age(w.last_success_at),durationMs:w.duration_ms,errorCode:w.error_code})),disk,backup};
}

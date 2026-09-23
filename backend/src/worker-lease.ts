import type {Db} from './store.js';

const leaseName=/^[a-z][a-z0-9_-]{0,63}$/;
const owner=/^[A-Za-z0-9._:-]{1,160}$/;

export async function tryAcquireWorkerLease(
 db:Db,
 name:string,
 ownerId:string,
 ttlMs:number,
 now=new Date(),
){
 if(!leaseName.test(name)||!owner.test(ownerId)||!Number.isInteger(ttlMs)||ttlMs<5000||ttlMs>60*60*1000)throw new Error('INVALID_WORKER_LEASE');
 const current=now.toISOString(),expiresAt=new Date(now.getTime()+ttlMs).toISOString();
 await db.run(
  `INSERT INTO worker_leases(name,owner_id,expires_at) VALUES(?,?,?)
   ON CONFLICT(name) DO UPDATE SET owner_id=excluded.owner_id,expires_at=excluded.expires_at
   WHERE worker_leases.expires_at<=? OR worker_leases.owner_id=?`,
  [name,ownerId,expiresAt,current,ownerId],
 );
 const rows=await db.all('SELECT owner_id,expires_at FROM worker_leases WHERE name=?',[name]);
 return rows.length===1&&rows[0].owner_id===ownerId&&rows[0].expires_at===expiresAt;
}

export async function releaseWorkerLease(db:Db,name:string,ownerId:string){
 if(!leaseName.test(name)||!owner.test(ownerId))throw new Error('INVALID_WORKER_LEASE');
 await db.run('DELETE FROM worker_leases WHERE name=? AND owner_id=?',[name,ownerId]);
}

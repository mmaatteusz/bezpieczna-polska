import type {Db} from '../store.js';

export const migration002={
 version:2,
 name:'worker_leases',
 async up(db:Db){
  await db.run('CREATE TABLE IF NOT EXISTS worker_leases(name TEXT PRIMARY KEY, owner_id TEXT NOT NULL, expires_at TEXT NOT NULL)');
 },
};

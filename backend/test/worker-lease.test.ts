import test from 'node:test';
import assert from 'node:assert/strict';
import {openDb} from '../src/store.js';
import {migrate} from '../src/migrate.js';
import {tryAcquireWorkerLease,releaseWorkerLease} from '../src/worker-lease.js';

test('worker lease is exclusive, expires, and only its owner can release it',async()=>{
 const db=openDb(undefined,':memory:');
 try{
  await migrate(db);
  const t0=new Date('2026-09-23T12:00:00Z');
  assert.equal(await tryAcquireWorkerLease(db,'ingest','replica-a',60000,t0),true);
  assert.equal(await tryAcquireWorkerLease(db,'ingest','replica-b',60000,new Date('2026-09-23T12:00:30Z')),false);
  await releaseWorkerLease(db,'ingest','replica-b');
  assert.equal(await tryAcquireWorkerLease(db,'ingest','replica-b',60000,new Date('2026-09-23T12:01:01Z')),true);
  await releaseWorkerLease(db,'ingest','replica-a');
  assert.equal(await tryAcquireWorkerLease(db,'ingest','replica-a',60000,new Date('2026-09-23T12:01:02Z')),false);
  await releaseWorkerLease(db,'ingest','replica-b');
  assert.equal(await tryAcquireWorkerLease(db,'ingest','replica-a',60000,new Date('2026-09-23T12:01:03Z')),true);
 }finally{await db.close();}
});

import {test} from 'node:test';
import assert from 'node:assert/strict';
import {openDb,Store} from '../src/store.js';
import {buildApp} from '../src/app.js';
import {migrate,assertSchema} from '../src/migrate.js';
import {serverConfig,publicHttpsUrl} from '../src/config.js';

test('production configuration rejects dev endpoints and missing credentials',()=>{
 const valid={APP_ENV:'production',NODE_ENV:'production',DATABASE_URL:'postgresql://user:pass@db:5432/app',
  ADMIN_TOKEN:'A1b2C3d4E5f6G7h8I9j0K1l2M3n4O5p6',PUBLIC_BASE_URL:'https://api.real-domain.pl',
  BUILD_SHA:'a'.repeat(40),TRUST_PROXY:'true'};
 assert.equal(serverConfig(valid).production,true);
 for(const host of ['http://api.real-domain.pl','https://localhost','https://10.0.2.2','https://api-preview.domain.pl','https://api.example','https://api.example.org','https://api.domain.pl/?token=secret']){
  assert.throws(()=>publicHttpsUrl(host));
 }
 for(const key of ['DATABASE_URL','ADMIN_TOKEN','PUBLIC_BASE_URL','BUILD_SHA','TRUST_PROXY'] as const){
  assert.throws(()=>serverConfig({...valid,[key]:''}));
 }
});
test('migration is idempotent and required before serving',async()=>{
 const db=openDb(undefined,':memory:');
 try{
  await assert.rejects(assertSchema(db));
  await migrate(db);await migrate(db);await assertSchema(db);
  assert.deepEqual((await db.all('SELECT version FROM schema_migrations ORDER BY version')).map(r=>r.version),[1,2]);
  await db.run('DROP TABLE push_outbox');
  await assert.rejects(assertSchema(db));
 }finally{await db.close();}
});
test('readiness depends on database, not external sources; metrics require admin auth',async()=>{
 const db=openDb(undefined,':memory:'),store=new Store(db),token='0123456789abcdef0123456789abcdef';
 await store.init();const app=await buildApp(store,token,undefined,{stage:'preview',buildSha:'f'.repeat(40)});
 try{
  assert.equal((await app.inject('/ready')).statusCode,200);
  assert.equal((await app.inject('/readyz')).statusCode,503);
  const health=await app.inject('/health');
  assert.equal(health.json().buildSha,'f'.repeat(40));
  assert.equal(health.headers['x-content-type-options'],'nosniff');
  assert.equal((await app.inject('/admin/metrics')).statusCode,401);
  const metrics=await app.inject({url:'/admin/metrics',headers:{authorization:'Bearer '+token}});
  assert.equal(metrics.statusCode,200);
  assert.ok(metrics.json().requests['GET /health']);
  const oversized=await app.inject({method:'POST',url:'/v1/around',payload:{long:'x'.repeat(129*1024)}});
  assert.equal(oversized.statusCode,413);
  assert.ok(!oversized.body.includes('stack'));
  const production=await buildApp(store,token,undefined,{stage:'production',buildSha:'f'.repeat(40),trustProxy:true});
  try{
   assert.equal((await production.inject('/ready')).statusCode,503);
   assert.equal((await production.inject('/health')).headers['strict-transport-security'],'max-age=31536000; includeSubDomains');
  }finally{await production.close();}
 }finally{await app.close();await db.close();}
});

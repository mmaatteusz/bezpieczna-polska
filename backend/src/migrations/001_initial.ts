import {Store,type Db} from '../store.js';

export const migration001={
 version:1,
 name:'initial_schema',
 async up(db:Db){
  // Preserve the already deployed alpha.17 schema as migration 001.
  // Store.init is idempotent and remains the canonical builder for that baseline.
  await new Store(db).init({reconcile:false});
 },
};

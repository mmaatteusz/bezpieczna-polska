import type {Db} from '../store.js';
import {initPushStore} from '../push.js';

export const migration003={
 version:3,
 name:'push_provider_acceptance',
 async up(db:Db){await initPushStore(db);},
};

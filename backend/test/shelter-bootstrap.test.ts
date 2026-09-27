import test from 'node:test';
import assert from 'node:assert/strict';
import {createHash} from 'node:crypto';
import {gzipSync} from 'node:zlib';
import {decodeShelterSnapshot,validateBootstrapBaseUrl} from '../src/shelter-bootstrap.js';

const sha=(v:Buffer|string)=>createHash('sha256').update(v).digest('hex');

test('shelter bootstrap reconstructs exact CSV and rejects tampering',()=>{
 const csv='a,b\n1,2\n';
 const gzip=gzipSync(Buffer.from(csv));
 const encoded=gzip.toString('base64');
 const parts=[encoded.slice(0,5),encoded.slice(5,13),encoded.slice(13)];
 assert.equal(decodeShelterSnapshot(parts,sha(gzip),sha(csv)),csv);
 assert.throws(()=>decodeShelterSnapshot([encoded+'A'],sha(gzip),sha(csv)),/GZIP_HASH_MISMATCH|INVALID_BASE64/);
 assert.throws(()=>decodeShelterSnapshot(parts,'0'.repeat(64),sha(csv)),/GZIP_HASH_MISMATCH/);
 assert.throws(()=>decodeShelterSnapshot(parts,sha(gzip),'0'.repeat(64)),/CSV_HASH_MISMATCH/);
});

test('shelter bootstrap only accepts raw GitHub ops shelter path',()=>{
 assert.equal(validateBootstrapBaseUrl('https://raw.githubusercontent.com/mmaatteusz/bezpieczna-polska/ops-shelters-snapshot-20260927/ops/shelters/parts').hostname,'raw.githubusercontent.com');
 for(const value of [
  'http://raw.githubusercontent.com/mmaatteusz/bezpieczna-polska/x/ops/shelters/parts/',
  'https://evil.example/ops/shelters/parts/',
  'https://raw.githubusercontent.com/other/repo/main/ops/shelters/parts/'
 ])assert.throws(()=>validateBootstrapBaseUrl(value),/URL_DENIED/);
});

import test from 'node:test';
import assert from 'node:assert/strict';
import {latLngToCell} from 'h3-js';
import {
  defaultGpsInterferenceDate,
  gpsInterferenceViewport,
  gpsJamLevel,
  gpsJamPercent,
  parseGpsJamCsv,
} from '../src/gps-interference.js';

test('GPSJAM percentage and thresholds follow the published methodology',()=>{
  assert.equal(gpsJamPercent(99,1),0);
  assert.equal(gpsJamLevel(2),'LOW');
  assert.equal(gpsJamLevel(2.01),'MEDIUM');
  assert.equal(gpsJamLevel(10),'MEDIUM');
  assert.equal(gpsJamLevel(10.01),'HIGH');
  assert.equal(defaultGpsInterferenceDate(new Date('2026-09-27T00:30:00Z')),'2026-09-26');
});

test('GPSJAM CSV becomes validated H3 polygons',()=>{
  const hex=latLngToCell(52.2297,21.0122,4);
  const cells=parseGpsJamCsv(
    'hex,count_good_aircraft,count_bad_aircraft\n'+hex+',80,20\n',
  );
  assert.equal(cells.length,1);
  assert.equal(cells[0].h3,hex);
  assert.equal(cells[0].level,'HIGH');
  assert.ok(cells[0].boundary.length>=7);
  assert.deepEqual(cells[0].boundary[0],cells[0].boundary.at(-1));
});

test('GPS interference viewport returns only visible hexes and explicit OSINT metadata',async()=>{
  const inside=latLngToCell(52.2297,21.0122,4);
  const outside=latLngToCell(40.7128,-74.0060,4);
  const csv='hex,count_good_aircraft,count_bad_aircraft\n'+
    inside+',80,20\n'+
    outside+',100,1\n';
  const original=globalThis.fetch;
  globalThis.fetch=async()=>new Response(csv,{status:200,headers:{'content-type':'text/csv'}}) as any;
  try{
    const result=await gpsInterferenceViewport({
      bbox:[13.5,48.5,24.5,55.5],
      date:'2026-09-25',
    });
    assert.equal(result.metadata.provider,'GPSJAM');
    assert.equal(result.metadata.authority,'OSINT');
    assert.equal(result.metadata.dataDate,'2026-09-25');
    assert.equal(result.features.length,1);
    assert.equal(result.features[0].properties.h3,inside);
    assert.equal(result.features[0].geometry.type,'Polygon');
  }finally{
    globalThis.fetch=original;
  }
});

import assert from 'node:assert/strict';
import test from 'node:test';
import { buildApp } from '../src/app.js';
import { createFlightradar24 } from '../src/flightradar24.js';
import { openDb, Store } from '../src/store.js';

const checkedAt = Date.parse('2026-11-23T13:33:00Z');
const position = (id: number, lat: number, lon: number, changes = {}) => ({
  fr24_id: id.toString(16),
  flight: 'LO321',
  operating_as: 'LOT',
  lat,
  lon,
  track: 145,
  alt: 29_000,
  gspeed: 428,
  timestamp: '2026-11-23T13:32:50Z',
  source: 'ADSB',
  orig_iata: 'WAW',
  dest_icao: 'LROP',
  reg: 'SYNTHETIC-REG',
  hex: '123456',
  ...changes,
});

test('the public route uses one passenger-only FR24 request and publishes only flights in neighbouring countries', async () => {
  const rows = [
    position(1, 52.2, 21), // Poland
    position(2, 48.7, 19.1), // Slovakia
    position(3, 47.5, 19.1), // Hungary
    position(4, 44.43, 26.1), // Romania
    position(5, 47, 28.86), // Moldova
    position(6, 53.9, 27.56), // Belarus
    position(7, 55.75, 37.62), // Western Russia
    position(8, 50.45, 30.52), // Ukraine
    position(9, 44.95, 34.1), // Crimea, Ukraine
    position(10, 50.08, 14.42), // Czech Republic
    position(11, 51.5, -0.12), // Outside the map coverage
    position(12, 52.2, 21, { flight: null }),
    position(13, 52.2, 21, { operating_as: null }),
    position(14, 52.2, 21, { source: 'ESTIMATED' }),
    position(15, 52.2, 21, { timestamp: '2026-11-23T13:30:00Z' }),
    position(16, 52.2, 21, { gspeed: 10 }),
    position(1, 52.25, 21.06, { timestamp: '2026-11-23T13:32:55Z' }),
    position(1, 52.1, 21, { timestamp: '2026-11-23T13:32:45Z' }),
  ];
  let requests = 0;
  let clock = checkedAt;
  const liveFlights = createFlightradar24('test-token', async (input, init) => {
    requests++;
    const url = new URL(input.toString());
    assert.equal(url.origin, 'https://fr24api.flightradar24.com');
    assert.equal(url.pathname, '/api/live/flight-positions/full');
    assert.equal(url.searchParams.get('categories'), 'P');
    assert.equal(url.searchParams.get('bounds'), '56,43.5,14,42');
    assert.equal(url.searchParams.get('data_sources'), 'ADSB,MLAT,UAT');
    assert.equal(new Headers(init?.headers).get('Authorization'), 'Bearer test-token');
    assert.equal(new Headers(init?.headers).get('Accept-Version'), 'v1');
    return Response.json({ data: rows });
  }, () => clock);
  const db = openDb(undefined, ':memory:');
  const store = new Store(db);
  await store.init();
  const app = await buildApp(store, undefined, undefined, { liveFlights });
  try {
    const results = await Promise.all([
      app.inject('/v1/neptun/live-flights'),
      app.inject('/v1/neptun/live-flights?categories=M&bounds=89,1,1,179'),
    ]);
    assert.ok(results.every(result => result.statusCode === 200));
    assert.equal(requests, 1);
    const result = results[0].json();
    assert.deepEqual(results[1].json(), result);
    assert.equal(result.state, 'LIVE');
    assert.equal(result.limitReached, false);
    assert.deepEqual(result.flights.map((flight: { country: string }) => flight.country), [
      'PL', 'SK', 'HU', 'RO', 'MD', 'BY', 'RU',
    ]);
    assert.deepEqual(result.flights[0], {
      id: '1', number: 'LO321', country: 'PL', latitude: 52.25, longitude: 21.06,
      track: 145, altitudeFt: 29_000, speedKt: 428,
      observedAt: '2026-11-23T13:32:55.000Z', from: 'WAW', to: 'LROP',
    });
    clock += 59_000;
    assert.equal((await liveFlights()).flights.length, 7);
    assert.equal(requests, 1);
    clock += 31_000;
    assert.deepEqual((await liveFlights()).flights, []);
    assert.equal(requests, 2);
  } finally {
    await app.close();
    await db.close();
  }
});

test('missing token and provider failure are distinct from a successful empty result', async () => {
  const disabled = createFlightradar24(' ', async () => assert.fail('unexpected upstream request'));
  assert.deepEqual(await disabled(), { state: 'NOT_CONFIGURED', flights: [] });

  let clock = checkedAt;
  let requests = 0;
  const liveFlights = createFlightradar24('test-token', async () => {
    requests++;
    if (requests === 2) return new Response(null, { status: 402 });
    return Response.json({ data: [position(1, 52.2, 21, { timestamp: new Date(clock).toISOString() })] });
  }, () => clock);
  assert.equal((await liveFlights()).flights.length, 1);
  clock += 60_000;
  assert.deepEqual(await liveFlights(), { state: 'UNAVAILABLE', flights: [] });
  clock += 60_000;
  assert.equal((await liveFlights()).state, 'UNAVAILABLE');
  assert.equal(requests, 2);
  clock += 240_000;
  assert.equal((await liveFlights()).flights.length, 1);
  assert.equal(requests, 3);
  const empty = createFlightradar24('test-token', async () => Response.json({ data: [] }));
  const result = await empty();
  assert.equal(result.state, 'LIVE');
  assert.deepEqual(result.flights, []);
});

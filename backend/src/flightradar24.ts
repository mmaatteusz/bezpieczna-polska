import { z } from 'zod';
import borders from './neptun-flight-countries.json' with { type: 'json' };

const bounds = { north: 56, south: 43.5, west: 14, east: 42 };
const captureIntervalMs = 60_000;
const positionMaxAgeMs = 90_000;
const flightLimit = 300;
const positionSources = ['ADSB', 'MLAT', 'UAT'] as const;
const flightNumber = z.string().regex(/^[A-Z0-9]{2}\d{1,4}[A-Z]?$/);
const airportCode = z.string().regex(/^[A-Z]{3,4}$/);
const position = z.object({
  fr24_id: z.string().regex(/^[a-f0-9]{1,16}$/i),
  flight: flightNumber,
  operating_as: z.string().regex(/^[A-Z]{3}$/),
  lat: z.number().gte(-90).lte(90),
  lon: z.number().gte(-180).lte(180),
  track: z.number().int().gte(0).lte(360),
  alt: z.number().int().positive().lte(60_000),
  gspeed: z.number().int().gte(50).lte(800),
  timestamp: z.iso.datetime({ offset: true }),
  source: z.enum(positionSources),
  orig_iata: z.unknown().optional(),
  dest_iata: z.unknown().optional(),
  orig_icao: z.unknown().optional(),
  dest_icao: z.unknown().optional(),
});
const responseSchema = z.object({ data: z.array(z.unknown()).max(flightLimit) });

type Flight = {
  id: string;
  number: string;
  country: string;
  latitude: number;
  longitude: number;
  track: number;
  altitudeFt: number;
  speedKt: number;
  observedAt: string;
  from: string | null;
  to: string | null;
};

type LiveFlights =
  | { state: 'NOT_CONFIGURED' | 'UNAVAILABLE'; flights: [] }
  | { state: 'LIVE'; checkedAt: string; limitReached: boolean; flights: Flight[] };

function withinRing(lon: number, lat: number, ring: number[][]) {
  let inside = false;
  for (let i = 0, j = ring.length - 1; i < ring.length; j = i++) {
    const [x, y] = ring[i];
    const [previousX, previousY] = ring[j];
    if ((y > lat) !== (previousY > lat) && lon < x + (previousX - x) * (lat - y) / (previousY - y)) {
      inside = !inside;
    }
  }
  return inside;
}

function countryAt(lon: number, lat: number) {
  if (lat < bounds.south || lat > bounds.north || lon < bounds.west || lon > bounds.east) return null;
  // Ukraine comes first so simplified shared edges never assign its area to a neighbour.
  for (const [country, polygons] of Object.entries(borders)) {
    if (polygons.some(([outer, ...holes]) =>
      withinRing(lon, lat, outer) && !holes.some(hole => withinRing(lon, lat, hole)))) {
      return country === 'UA' ? null : country;
    }
  }
  return null;
}

function airport(iata: unknown, icao: unknown) {
  return airportCode.safeParse(iata).data ?? airportCode.safeParse(icao).data ?? null;
}

function normalizeFlights(rows: unknown[], checkedAt: number) {
  const flights = new Map<string, Flight>();
  for (const row of rows) {
    const { data } = position.safeParse(row);
    if (!data) continue;
    const time = Date.parse(data.timestamp);
    if (time < checkedAt - positionMaxAgeMs || time > checkedAt + 5000) continue;
    const country = countryAt(data.lon, data.lat);
    if (!country) continue;
    const observedAt = new Date(time).toISOString();
    const previous = flights.get(data.fr24_id);
    if (previous && previous.observedAt >= observedAt) continue;
    flights.set(data.fr24_id, {
      id: data.fr24_id,
      number: data.flight,
      country,
      latitude: data.lat,
      longitude: data.lon,
      track: data.track % 360,
      altitudeFt: data.alt,
      speedKt: data.gspeed,
      observedAt,
      from: airport(data.orig_iata, data.orig_icao),
      to: airport(data.dest_iata, data.dest_icao),
    });
  }
  return [...flights.values()];
}

export function createFlightradar24(token?: string, request = fetch, now = Date.now) {
  const apiToken = token?.trim();
  const url = new URL('https://fr24api.flightradar24.com/api/live/flight-positions/full');
  url.search = new URLSearchParams({
    bounds: [bounds.north, bounds.south, bounds.west, bounds.east].join(','),
    categories: 'P',
    data_sources: positionSources.join(','),
    gspeed: '50-800',
    limit: String(flightLimit),
  }).toString();

  let cached: LiveFlights = { state: 'NOT_CONFIGURED', flights: [] };
  let refreshAfter = 0;
  let pending: Promise<void> | undefined;

  async function refresh() {
    let retryMs = captureIntervalMs;
    try {
      const response = await request(url, {
        headers: { Accept: 'application/json', 'Accept-Version': 'v1', Authorization: `Bearer ${apiToken}` },
        signal: AbortSignal.timeout(8000),
        redirect: 'error',
      });
      if (!response.ok) {
        if ([401, 402, 403, 429].includes(response.status)) retryMs = 5 * captureIntervalMs;
        throw new Error('Flightradar24 request failed');
      }
      const { data } = responseSchema.parse(await response.json());
      const checkedAt = now();
      cached = {
        state: 'LIVE',
        checkedAt: new Date(checkedAt).toISOString(),
        limitReached: data.length === flightLimit,
        flights: normalizeFlights(data, checkedAt),
      };
    } catch {
      cached = { state: 'UNAVAILABLE', flights: [] };
    } finally {
      refreshAfter = now() + retryMs;
    }
  }

  return async (): Promise<LiveFlights> => {
    if (!apiToken) return cached;
    if (now() >= refreshAfter) {
      pending ??= refresh().finally(() => { pending = undefined; });
      await pending;
    }
    if (cached.state !== 'LIVE') return cached;
    const cutoff = now() - positionMaxAgeMs;
    return { ...cached, flights: cached.flights.filter(f => Date.parse(f.observedAt) >= cutoff) };
  };
}

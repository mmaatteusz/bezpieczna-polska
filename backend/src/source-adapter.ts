import type {Event} from './domain.js';

export type SourceContext = {now: Date; fetchText: (url: string) => Promise<string>};
export type SourceBatch = {
  events: Event[];
  // A publication archive is never proof that there are no active warnings.
  complete: boolean;
  coverage: 'RECENT_PUBLICATIONS' | 'ACTIVE_WARNINGS';
  pagesFetched: number;
};
export interface SourceAdapter {
  readonly id: string;
  readonly version: string;
  sync(context: SourceContext): Promise<SourceBatch>;
}

// Enable sources one by one, in the agreed integration order.
export const SOURCES = [
  {id: 'RCB', name: 'Rządowe Centrum Bezpieczeństwa', url: 'https://www.gov.pl/web/rcb/komunikaty', enabled: true},
  {id: 'SHELTERS', name: 'Punkty schronienia PSP / dane.gov.pl', url: 'https://www.gov.pl/web/kgpsp', enabled: false},
  {id: 'LEVELS', name: 'Stopnie alarmowe RP', url: 'https://www.gov.pl/web/rcb', enabled: false},
  {id: 'RSO', name: 'Regionalny System Ostrzegania / WCZK', url: 'https://komunikaty.tvp.pl/', enabled: false},
  {id: 'PAA', name: 'Państwowa Agencja Atomistyki', url: 'https://www.gov.pl/web/paa', enabled: false},
  {id: 'CERT', name: 'CERT Polska', url: 'https://cert.pl/', enabled: false},
  {id: 'SG', name: 'Straż Graniczna', url: 'https://www.strazgraniczna.pl/', enabled: false},
  {id: 'UA', name: 'Oficjalne alarmy Ukrainy — integracja oczekuje', url: 'https://dsns.gov.ua/', enabled: false},
];

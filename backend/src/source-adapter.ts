import {WCZK_SOURCES} from './wczk-registry.js';
import type {Event} from './domain.js';
import type {Shelter} from './shelter.js';

export type SourceContext = {now: Date; previousEvents?: Event[]; fetchText: (url: string) => Promise<string>; fetchBytes?: (url: string) => Promise<Uint8Array>};
export type SourceBatch = {
  events: Event[];
  shelters?: Shelter[];
  metadata?: {dataDate:string;sourceUpdatedAt:string;sourceContentHash:string;sourceUrl:string;datasetUrl:string;license:string;fallbackSelected?:'PRIMARY_OFFICIAL_SOURCE'|'SECONDARY_OFFICIAL_SOURCE'};
  // A publication archive is never proof that there are no active warnings.
  complete: boolean;
  coverage: 'RECENT_PUBLICATIONS' | 'ACTIVE_WARNINGS' | 'FACILITY_CATALOG';
  pagesFetched: number;
};
export interface SourceAdapter {
  readonly id: string;
  readonly version: string;
  readonly minSyncIntervalSeconds?: number;
  sync(context: SourceContext): Promise<SourceBatch>;
}

// Enable sources one by one, in the agreed integration order.
export const SOURCES = [
  ...WCZK_SOURCES,
  {id: 'RCB', name: 'Rządowe Centrum Bezpieczeństwa', url: 'https://www.gov.pl/web/rcb/komunikaty', enabled: true},
  {id: 'SHELTERS', name: 'Punkty schronienia PSP / dane.gov.pl', url: 'https://dane.gov.pl/pl/dataset/28058,punkty-schronienia-w-polsce', enabled: true},
  {id: 'LEVELS', name: 'Stopnie alarmowe RP', url: 'https://www.gov.pl/web/rcb/komunikaty', enabled: true},
  {id: 'RSO', name: 'Regionalny System Ostrzegania / WCZK', url: 'https://komunikaty.tvp.pl/', enabled: true},
  {id: 'PAA', name: 'PAA — komunikaty', url: 'https://www.gov.pl/web/paa/aktualnosci2', enabled: true},
  {id: 'PAA_MEASUREMENTS', name: 'PAA — pomiary (format niezweryfikowany)', url: 'https://monitoring.paa.gov.pl/maps-portal/', enabled: false, implementation:'BLOCKED_SOURCE_VERIFICATION', integrationNote:'Portal zwrócił blokadę WAF. Nie zweryfikowano formatu stacji i pomiarów; brak integracji zamiast domyślonego API.'},
  {id: 'CERT', name: 'CERT Polska — komunikaty bezpieczeństwa', url: 'https://moje.cert.pl/komunikaty/', enabled: true},
  {id: 'CSIRT_GOV', name: 'CSIRT GOV — ostrzeżenia publiczne', url: 'https://www.csirt.gov.pl/cer/rss', enabled: false, implementation:'RSS_CHANNEL_LIST_EMPTY', integrationNote:'Oficjalna strona usługi RSS działa, ale publiczna lista kanałów jest obecnie pusta. Nie importujemy raportów historycznych jako bieżących ostrzeżeń.'},
  {id: 'SG', name: 'Straż Graniczna', url: 'https://www.strazgraniczna.pl/', enabled: false},
  {id: 'UA', name: 'Oficjalne alarmy Ukrainy — integracja oczekuje', url: 'https://dsns.gov.ua/', enabled: false},
];

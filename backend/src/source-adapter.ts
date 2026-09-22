import {WCZK_SOURCES} from './wczk-registry.js';
import type {Event} from './domain.js';
import type {Shelter} from './shelter.js';

export type SourceContext = {now: Date; previousEvents?: Event[]; fetchText: (url: string) => Promise<string>; fetchBytes?: (url: string) => Promise<Uint8Array>};
export type SourceBatch = {
  events: Event[];
  uaMetadata?: NonNullable<import('./domain.js').Health['uaMetadata']>;
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
  {id: 'SG', name: 'Straż Graniczna — operacyjne informacje graniczne', url: 'https://www.strazgraniczna.pl/pl/aktualnosci', enabled: true, implementation:'OFFICIAL_NEWS_OPERATIONAL_FILTER', integrationNote:'Publiczna lista RSS KGSG jest pusta. Integracja używa oficjalnych Aktualności z konserwatywnym filtrem zamknięć, ograniczeń, kontroli i utrudnień granicznych.'},
  {id: 'POLICE', name: 'Policja — istotne zdarzenia', url: 'https://policja.pl/pol/aktualnosci', enabled: true, implementation:'OFFICIAL_RSS_INCIDENT_FILTER', integrationNote:'Oficjalny RSS Aktualności Policji. Importowane są wyłącznie zdarzenia o znaczeniu sytuacyjnym; zwykłe zatrzymania, kradzieże, przemyt, statystyki i materiały PR są odrzucane.'},
  {id: 'PSP_INCIDENTS', name: 'PSP — istotne zdarzenia', url: 'https://www.gov.pl/web/kgpsp/aktualnosci', enabled: true, implementation:'OFFICIAL_NEWS_INCIDENT_FILTER', integrationNote:'Centralne Aktualności KG PSP na gov.pl z konserwatywnym filtrem zdarzeń. Brak zweryfikowanego krajowego live API/RSS incydentów; lista publikacji nie oznacza pełnego pokrycia.'},
  {id: 'UA', name: 'UkraineAlarm — oficjalne alarmy Ukrainy', url: 'https://map.ukrainealarm.com/', enabled: true, implementation:'UKRAINEALARM_V3', integrationNote:'Oficjalne API wymaga klucza. Historia źródła jest ograniczona. Alarmy UA nie wpływają na status Polski.'},
  {id: 'NEPTUN', name: 'NEPTUN — historyczna warstwa OSINT', url: 'https://example.invalid/neptun', enabled: false, implementation:'HISTORICAL_CURATED_ONLY', integrationNote:'Brak aktywnego feedu. Publikacja wyłącznie zakończonych, historycznych i zgrubnych śladów po audytowanej weryfikacji; brak aktywnych dokładnych pozycji.'},
];

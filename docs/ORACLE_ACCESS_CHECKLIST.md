# Oracle OCI — dostęp i sekrety przed pierwszym bootstrapem

Ten etap wykonujemy dopiero po utworzeniu VM w Oracle Cloud. Nie zmienia on produkcji, nie dotyka Railway i nie wymaga `PRODUCTION_API_BASE_URL` ani `PREVIEW_API_BASE_URL`.

## Dane potrzebne z OCI

Zapisz poza repo:

- publiczny IPv4 VM,
- użytkownik SSH z obrazu Ubuntu — standardowo `ubuntu`,
- prywatny klucz SSH odpowiadający kluczowi dodanemu przy tworzeniu VM,
- fingerprint host key SSH potwierdzony niezależnym kanałem,
- informację, że VM to ARM64 / Ampere A1.

## GitHub Actions — sekrety, nie variables

Dopiero gdy VM istnieje, będą potrzebne cztery **Repository secrets**:

- `ORACLE_SSH_HOST` — publiczny IPv4 lub stabilna nazwa hosta,
- `ORACLE_SSH_USER` — np. `ubuntu`,
- `ORACLE_SSH_PRIVATE_KEY` — cały prywatny klucz OpenSSH,
- `ORACLE_SSH_KNOWN_HOSTS` — zweryfikowana linia/linii known_hosts.

Nie zapisujemy prywatnego klucza, haseł DB ani tokenów w plikach repo.

## Przypięcie host key

Nie ustawiamy `StrictHostKeyChecking=no` i nie ufamy ślepo wynikowi `ssh-keyscan`.

Najpierw zweryfikuj fingerprint host key niezależnie, a potem:

```bash
EXPECTED_SSH_FINGERPRINT='SHA256:ZWERYFIKOWANY_FINGERPRINT' \
  bash infra/oracle/pin-ssh-host-key.sh <PUBLICZNY_IP>
```

Skrypt:

1. pobierze host keys,
2. wypisze ich SHA-256,
3. przerwie pracę, jeśli żaden nie odpowiada oczekiwanemu fingerprintowi,
4. dopiero po zgodności pokaże treść do `ORACLE_SSH_KNOWN_HOSTS`.

## Pierwszy dry run

Po ustawieniu czterech sekretów uruchom ręcznie workflow:

`Oracle SSH preflight`

Ten workflow **niczego nie instaluje** i nie wdraża API. Sprawdza tylko:

- połączenie SSH z przypiętym host key,
- system Ubuntu,
- architekturę ARM64,
- liczbę CPU,
- RAM,
- rozmiar root filesystem,
- działanie bezinterakcyjnego `sudo`,
- czy porty 5432/8080 nie są już przypadkiem wystawione.

Dopiero po zielonym preflight uruchamiamy `bootstrap-host.sh`.

## Czego nadal nie robimy

Na tym etapie nie ustawiamy:

- `PRODUCTION_API_BASE_URL`,
- `PREVIEW_API_BASE_URL`.

Nie zmieniamy adresu aplikacji i nie wyłączamy Railway.

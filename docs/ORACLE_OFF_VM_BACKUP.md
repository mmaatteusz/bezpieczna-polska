# Backup poza VM i odzyskiwanie bez PC

Backup lokalny nie chroni przed utratą instancji. Wysyłamy dump bazy,
sumę kontrolną i metadane do prywatnego bucketu OCI Object Storage.
Sekretów `backend.env`, klucza SSH i keystore Androida nie wysyłamy tym hookiem.

## Konfiguracja OCI

W Home Region utwórz prywatny bucket Standard `bezpieczna-polska-backups`.
Pozostaw publiczny dostęp wyłączony. Zanotuj namespace Object Storage.
Dynamic group `bp-backup-vm` ma obejmować dokładnie jedną instancję:

```text
instance.id = 'OCID_INSTANCJI'
```

Nadaj jej wyłącznie tworzenie i sprawdzanie obiektów w tym buckecie:

```text
Allow dynamic-group bp-backup-vm to manage objects in compartment id OCID_COMPARTMENT where all {target.bucket.name='bezpieczna-polska-backups', any {request.permission='OBJECT_CREATE', request.permission='OBJECT_INSPECT'}}
```

Dla domen IAM może być wymagane kwalifikowanie nazwy dynamic group domeną.
VM nie dostaje uprawnień do pobierania danych, nadpisywania ani kasowania kopii.
Nie stosuj szerokiego `manage object-family in tenancy`.
Administrator pobiera kopie przez konsolę, poza rolą VM.

Skonfiguruj limit/monitoring zajętości i lifecycle dla starych kopii stosownie
do dostępnego limitu storage. Nie blokuj nieodwracalnie retention rule podczas
pierwszego testu. Nie obiecujemy bezpłatności bez sprawdzenia limitów tenancji.

## Konfiguracja VM

Skopiuj `infra/oracle/backup-object-storage.json.example` do
`/etc/bezpieczna-polska/backup-object-storage.json` i uzupełnij namespace.
Następnie jako root uruchom `infra/oracle/install-backup-upload.sh`.
SDK OCI korzysta z instance principals; nie tworzymy klucza API ani GitHub Secrets.

```bash
sudo systemctl start bezpieczna-polska-backup.service
sudo journalctl -u bezpieczna-polska-backup.service -n 20 --no-pager
```

Wymagane `OFF_VM_UPLOAD_PASS files=3 overwrite=false`. Job sprawdza MD5
podczas transferu oraz rozmiar, MD5 i SHA256 metadanych zapisanego obiektu.
Po instalacji brak hooka lub błąd wysyłki powoduje niepowodzenie joba.
Nie traktuj samego aktywnego timera jako dowodu poprawnego backupu.

Przed cutoverem pobierz dump i checksum z bucketu, sprawdź SHA256 i wykonaj
restore drill na pobranej kopii. Nie zastępuj tego testem oryginalnego lokalnego pliku.
Monitoruj niepowodzenia joba i wiek ostatniej poprawnej zdalnej kopii.

## Odtworzenie dostępu i release

Klucz SSH, hasła, sekrety backendu i klucz upload Androida wymagają osobnej
szyfrowanej kopii w zaufanym magazynie poza PC i VM oraz sprawdzenia odczytu.
GitHub Secrets nie są magazynem odzyskiwania: zapisanej wartości nie można
później odczytać. Keystore preview nie zastępuje podpisu release Google Play.
Play App Signing oddziela klucz podpisujący aplikację od klucza upload.

`recovery-config.py create` uruchomiony jako root przez interpreter venv OCI
tworzy pakiet pięciu plików konfiguracji hosta. Hasło wpisuje się interaktywnie
(co najmniej 16 znaków), poza historią poleceń. Scrypt N=131072, r=8, p=1
wyprowadza klucz AES-256-GCM; losowa sól i nonce są zapisane w kopercie JSON.
Pakiet trafia do `recovery/host-recovery-TIMESTAMP.enc` w tym samym prywatnym
buckecie, z zakazem nadpisania i weryfikacją metadanych. Skrypt wymaga obok
pliku `upload-backup.py`. Hasło przechowuj w niezależnym menedżerze haseł.

Po pobraniu obiektu z konsoli skopiuj go na host i uruchom jako root
`recovery-config.py verify PATH`. Wymagane `CONFIG_RECOVERY_PASS`.
Weryfikacja odszyfrowuje archiwum w pamięci i sprawdza komplet plików,
bez wypisywania wartości lub zapisu sekretów na dysk. Na nowym hoście do
odzyskania plików wykorzystaj `unseal()` z tego skryptu oraz ręcznie przejrzyj
ścieżki przed zapisem do katalogu odzyskiwania; nigdy bezpośrednio na aktywny host.
Kopie konfiguracji odświeżaj po zmianach sekretów. Nie zastępują one dziennego dumpu.

Nie usuwaj lokalnych plików przed potwierdzeniem niezależnej kopii i odzyskania
dostępu. Repozytorium i publiczne APK mogą być odbudowane przez GitHub Actions.

Dokumentacja:
- https://docs.oracle.com/en-us/iaas/Content/Identity/Reference/objectstoragepolicyreference.htm
- https://docs.oracle.com/en-us/iaas/tools/python/latest/api/object_storage/client/oci.object_storage.ObjectStorageClient.html
- https://support.google.com/googleplay/android-developer/answer/9842756

---
type: Spec
title: gRPC Integration Tests for sync_client
---

## Problem

`SQLiteWrapperSyncGRPC` (che estende `SqliteWrapperGRPC` con `SQLiteWrapperSyncMixin`) consente di usare un database SQLite remoto via gRPC invece che locale. Non esistono test automatizzati per questa classe — l'unica verifica è manuale tramite l'applicativo di esempio. Inoltre la docker-compose dei test di integrazione non include i servizi gRPC necessari (`sqlitewrapperserver` + `envoy`).

## Proposed Outcome

Test di integrazione per `SQLiteWrapperSyncGRPC` che coprano operazioni CRUD via gRPC con logOperation e sync REST end-to-end con database remoto. La docker-compose esistente viene estesa con i servizi gRPC.

## User Stories

1. Come sviluppatore, voglio test che `SQLiteWrapperSyncGRPC` esegua correttamente insert/update/delete/query su un database remoto via gRPC e che il mixin registri le operazioni in sync_data, così da verificare che la combinazione gRPC + mixin funzioni.
2. Come sviluppatore, voglio test che l'intero flusso di sync (register via REST → insert via gRPC → sync REST → verifica su secondo client) funzioni con database gRPC, così da coprire lo scenario d'uso reale dell'esempio.
3. Come sviluppatore, voglio test con due client gRPC che sincronizzano tra loro via server REST, così da verificare la propagazione dei cambiamenti in configurazione multi-dispositivo.
4. Come sviluppatore, voglio che la CI esegua questi test nello stesso job di integrazione esistente, senza necessità di docker-compose aggiuntive.

## Requirements

### R1: Docker compose esteso

1. Aggiungere il servizio `sqlitewrapperserver` (immagine `sfalda/sqlite_wrapper_server:latest`) al file `test/integration/docker/docker-compose.yml`. [L2]
2. Aggiungere il servizio `envoy` (immagine `envoyproxy/envoy:v1.33-latest`) con la configurazione `envoy.yaml`. [L2]
3. Il servizio `sqlitewrapperserver` deve esporre la porta interna 50051. [L4]
4. Il servizio `envoy` deve esporre la porta 50052 sul host, collegata a `sqlitewrapperserver:50051`. [L4]
5. Copiare `envoy.yaml` in `test/integration/docker/`. [L6]
6. Usare `tmpfs` per i dati del server gRPC (nessuna persistenza su disco). [L6]
7. Il server gRPC deve essere configurato con `UNAUTHENTICATED=true` e `SHARED_DB=true`. [L2]

### R2: CRUD + logOperation via gRPC [L5]

Usando `SQLiteWrapperSyncGRPC` connesso a `localhost:50052` via envoy, con sync configurato (sync_details popolato):

1. **Insert**: inserire un todo via gRPC → riga presente in `todos` e sync_data sul server remoto.
2. **Update**: modificare titolo via gRPC → sync_data registra `U`.
3. **Delete**: eliminare via gRPC → sync_data registra `D` (o collassa I/D).
4. **Query**: leggere dati via gRPC → risultati corretti.
5. **shouldSync**: dopo insert, `shouldSync` restituisce true.

### R3: Sync REST completo con DB gRPC [L5]

Usando `SQLiteWrapperSyncGRPC` come database e `SyncRepository` per il sync:

1. **Register + sync**: registrare un utente via REST, inserire dati via gRPC, fare sync → dati propagati.
2. **Secondo client**: registrare un secondo client (stesso utente) con DB gRPC, fare sync → riceve i dati.
3. **Modifica + sync**: modificare un record sul primo client, sync → secondo client vede la modifica.
4. **Cancellazione + sync**: cancellare un record, sync → propagato all'altro client.

### R4: Multi-cliente gRPC [L5]

Due istanze di `SQLiteWrapperSyncGRPC` (stesso server gRPC, database name diversi) che sincronizzano tramite `SyncRepository`:

1. Inserire dati su client A via gRPC → sync REST → client B vede i dati via gRPC.
2. Modificare su B → sync → A vede la modifica.

### R5: CI

I nuovi test devono essere taggati `@Tag('integration')` ed eseguiti nello stesso job `test-integration` di `.github/workflows/dart.yml`, senza modifiche al flusso CI. [L2]

## Technical Decisions

### TD1: Connessione gRPC

`SQLiteWrapperSyncGRPC` viene istanziato con `host: 'localhost', port: 50052` (via envoy). [L4]

### TD2: Schema del database remoto

Il server gRPC (`sqlite_wrapper_server`) con `SHARED_DB=true` usa un unico file SQLite condiviso montato su `/data`. Con `tmpfs`, i dati sono in memoria e persi a ogni riavvio del container. [L6]

### TD3: Setup e teardown

`setUpAll` apre la connessione gRPC e registra l'utente; `tearDownAll` chiude la connessione. I test condividono lo stato (come nei test REST). [L6]

## Testing Strategy

### Test Seams

1. **Docker compose esteso**: i nuovi servizi gRPC si aggiungono al docker-compose esistente, nessun nuovo seam richiesto.
2. **`SQLiteWrapperSyncGRPC`**: sostituisce `SQLiteWrapperSync` nei test, usando `SqliteWrapperGRPC` (connessione remota) invece di `SQLiteWrapperCore` (locale).
3. **`FakeHttpHelper`** non usato; i test gRPC chiamano il vero server REST (come i test REST esistenti).

### File

| File | Tag | Dipende da |
|---|---|---|
| `test/integration/sync_grpc_test.dart` | `@Tag('integration')` | Docker (sync server, postgres, sqlitewrapperserver, envoy) |

## Out of Scope

- Test unitari con `FakeHttpHelper` per `SQLiteWrapperSyncGRPC` (la classe delega tutto a `SqliteWrapperGRPC` e al mixin, già coperti dai test esistenti).
- Test di `UploadChunks` o chunked upload via gRPC.
- Test di riconnessione o failover del server gRPC.

## Blocking Questions

None.

## Open Questions

None.

## Follow-Ups

1. Se il server gRPC (`sfalda/sqlite_wrapper_server`) cambia API o protobuf, aggiornare i test.
2. Se il pacchetto `sqlite_wrapper` introduce nuove funzionalità gRPC, estendere i test.

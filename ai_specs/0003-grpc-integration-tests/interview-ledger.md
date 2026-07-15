---
type: Interview Ledger
parent: spec.md
---

## Records

### L1

Status: current

Question: I test gRPC devono coprire solo CRUD via gRPC con mixin, o anche la combo gRPC + sync REST?

Answer: Entrambi — CRUD/logOperation via gRPC e sync REST completo con DB gRPC.

Decision: Testare sia le operazioni locali (CRUD con mixin su DB remoto) sia il sync REST end-to-end con database gRPC.

### L2

Status: current

Question: I servizi gRPC vanno aggiunti al docker-compose esistente o in un file separato?

Answer: Aggiunti al file esistente `test/integration/docker/docker-compose.yml`.

Decision: Unico docker-compose.yml con tutti i servizi (Postgres, sync server REST, sqlitewrapperserver, envoy).

### L3

Status: current

Question: File dei test gRPC separato o dentro sync_api_test.dart?

Answer: File separato `test/integration/sync_grpc_test.dart`.

Decision: Nuovo file di test, stesso tag `@integration`.

### L4

Status: current

Question: Connessione via envoy (porta 50052) o diretta (50051)?

Answer: Porta 50052 via envoy.

Decision: Test via envoy proxy, come nell'esempio applicativo.

### L5

Status: current

Question: Quali scenari testare?

Answer: Tutti — CRUD/logOperation, sync REST completo con DB gRPC, multi-cliente gRPC.

Decision: Tre gruppi di test: (1) CRUD via gRPC con verifica sync_data, (2) sync end-to-end (register→insert→sync→verify) con DB gRPC, (3) due client gRPC che syncano tramite server REST.

### L6

Status: current

Question: Dove mettere i file di supporto (envoy.yaml, dati gRPC)?

Answer: `envoy.yaml` in `test/integration/docker/`, dati gRPC su `tmpfs` (come già Postgres).

Decision: Self-contained in test/integration/docker/.

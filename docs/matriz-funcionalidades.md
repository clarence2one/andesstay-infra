# Matriz de funcionalidades — AndesStay

Alcance completo del proyecto AndesStay (caso DSY1107 – Desarrollo Cloud Native I) con el estado de cada funcionalidad, el componente responsable y una evidencia verificable en los repositorios (endpoint, archivo, commit o prueba). Los commits citados están en la rama `main` de cada repositorio.

**Estados:** ✅ Implementada · 🟡 Parcial · ❌ No implementada

## Resumen

| Estado | Cantidad |
|---|---|
| ✅ Implementada | 42 |
| 🟡 Parcial | 1 |
| ❌ No implementada | 0 |
| **Total del alcance** | **45** |

**Grado de implementación:** 42 ÷ 45 = **93,3 %** (solo cuentan las implementadas y operativas).

## 1. Identidad y seguridad

| # | Funcionalidad | Estado | Componente | Evidencia |
|---|---|---|---|---|
| 1 | Login con Azure AD (MSAL, authorization code + PKCE, redirect) | ✅ | frontend-andesstay | `src/app/core/auth/auth-config.ts` (`MSALInstanceFactory`, `MSALGuardConfigFactory`) · commit `0404836` |
| 2 | Envío automático del JWT en cada llamada al backend | ✅ | frontend-andesstay | `MsalInterceptor` con `protectedResourceMap` hacia `bffUrl/*` en `auth-config.ts` · commit `0404836` |
| 3 | Cierre de sesión y redirección a `/login` ante un 401 | ✅ | frontend-andesstay | `src/app/core/auth/auth-error.interceptor.ts` |
| 4 | Protección de rutas del frontend según el rol del tenant | ✅ | frontend-andesstay | `src/app/core/auth/role.guard.ts` + `data.roles` en `app.routes.ts` |
| 5 | Validación del JWT (firma, issuer, audiencia, vigencia) en el BFF | ✅ | ms-andesstay-bff | `config/SecurityConfig.java`, `security/AudienceValidator.java` · commit `5e95b5b` |
| 6 | Autorización por método HTTP, ruta y rol en el BFF | ✅ | ms-andesstay-bff | `SecurityConfig.filterChain` (p. ej. `POST /api/catalog/**` solo Admin) · commit `3eedb0b` (regla `/api/rabbit/**`) |
| 7 | Revalidación del JWT y `@PreAuthorize` en cada microservicio | ✅ | reservations, catalog, audit, report, rabbit-admin, kafka-admin | `config/SecurityConfig.java` + `security/AzureRolesConverter.java` en cada repo; `@PreAuthorize` en los controladores |

## 2. Catálogo

| # | Funcionalidad | Estado | Componente | Evidencia |
|---|---|---|---|---|
| 8 | Listar y consultar unidades (habitaciones y cabañas) | ✅ | ms-andesstay-catalog | `GET /api/catalog/units`, `GET /api/catalog/units/{id}` · commit `477388e` |
| 9 | Crear y editar unidades, tarifa y disponibilidad (Admin) | ✅ | ms-andesstay-catalog | `POST /api/catalog/units`, `PUT /api/catalog/units/{id}` |
| 10 | Valores agregados como lista cerrada (enum `Amenity`) | ✅ | ms-andesstay-catalog | `GET /api/catalog/amenities`, `domain/Amenity.java` |
| 11 | Reserva y liberación de cupos atómica, sin sobreventa | ✅ | ms-andesstay-catalog | `POST /api/catalog/units/{id}/reserve` y `/release` (`UPDATE … WHERE availableUnits > 0`) |
| 12 | Foto de referencia subida directo a Amazon S3 con URL prefirmada | ✅ | catalog + frontend | `POST /api/catalog/units/images/presign` · commits `a182b9d` (catalog) y `ab62113` (frontend) |

## 3. Reservas

| # | Funcionalidad | Estado | Componente | Evidencia |
|---|---|---|---|---|
| 13 | Crear reserva con monto calculado desde la tarifa de catalog | ✅ | ms-andesstay-reservations | `POST /api/reservations` · commit `1807d64` |
| 14 | Listar y consultar reservas | ✅ | ms-andesstay-reservations | `GET /api/reservations`, `GET /api/reservations/{id}` |
| 15 | Máquina de estados (CREADA → CONFIRMADA → CHECKIN_PENDIENTE → EN_ESTADIA → CHECKOUT / CANCELADA) | ✅ | ms-andesstay-reservations | `PUT /api/reservations/{id}/status`, `domain/ReservationStateMachine.java` |
| 16 | Pasarela de pago simulada (inmediato o al check-in) | ✅ | reservations + frontend | `POST /api/reservations/{id}/pay` · vista `features/payment` |

## 4. Mensajería con Kafka (eventos)

| # | Funcionalidad | Estado | Componente | Evidencia |
|---|---|---|---|---|
| 17 | Publicación de eventos de reserva en `reservations.events` | ✅ | ms-andesstay-reservations | Productor Kafka en `messaging/kafka/` · tópico visible en Kafka UI (`:8089`) |
| 18 | Auditoría: consumo de eventos y línea de tiempo por reserva | ✅ | ms-andesstay-audit | `GET /api/audit/events`, `GET /api/audit/events/reservation/{id}` · commit `54e7f7c` |
| 19 | Reportería: ocupación, tiempo de ciclo, reservas por hora y top de unidades | ✅ | ms-andesstay-report | `GET /api/report/kpis`, `GET /api/report/top-units` · commit `46fdc36` |
| 20 | Reintentos y dead-letter topic (`.DLT`) en los consumidores Kafka | ✅ | audit, report | Tópico `reservations.events.DLT`; configuración en `config/KafkaConsumerConfig.java` |

## 5. Mensajería con RabbitMQ (comandos) — EP3

| # | Funcionalidad | Estado | Componente | Evidencia |
|---|---|---|---|---|
| 21 | Productor de comandos de email, voucher y housekeeping | ✅ | ms-andesstay-reservations | `messaging/rabbit/ReservationCommandPublisher.java` · `ReservationCommandPublisherTest` · commit `c48494c` |
| 22 | Nombres de colas, exchanges y routing keys centralizados en `application.yml` | ✅ | notify, reservations | `andesstay.messaging` en ambos `application.yml`; `MessagingProperties.java` · commits `8fd26d0`, `c48494c` |
| 23 | Beans `Queue`, `Exchange` y `Binding` por caso de uso, en clases de configuración separadas | ✅ | notify, reservations | `config/RabbitTopologyConfig.java` (notify, 3 flujos × cola principal, reintento y DLQ) · `config/RabbitExchangesConfig.java` (reservations) |
| 24 | Consumidores `@RabbitListener` agrupados por dominio, con ACK manual | ✅ | ms-andesstay-notify | `messaging/listener/` (Email, Housekeeping, Voucher) · `EmailNotificationListenerTest` |
| 25 | Manejo de errores: reintento con espera para errores recuperables, NACK a DLQ para los no recuperables o agotados, todo registrado en log | ✅ | ms-andesstay-notify | `messaging/support/CommandFailureHandler.java`, colas `q.cmd.*.retry` y `q.cmd.*.dlq` · `CommandFailureHandlerTest` (4 casos) · commit `8fd26d0` |
| 26 | Detección de comandos no enrutables o rechazados por el broker (publisher confirms y returns) | ✅ | ms-andesstay-reservations | `config/MessagingConfig.deliveryFailureLogging` + `publisher-confirm-type`/`publisher-returns` en `application.yml` |
| 27 | Microservicio administrador: API REST para crear y eliminar colas, exchanges y bindings | ✅ | ms-andesstay-rabbit-admin | `POST/GET/DELETE /api/rabbit/queues`, `POST/DELETE /api/rabbit/exchanges`, `POST/DELETE /api/rabbit/bindings` · `service/RabbitAdminService.java` · commit `b8e7d2f` |
| 28 | Validación de entrada del administrador (nombres vacíos, prefijo `amq.`, TTL, tipo de exchange, routing keys) | ✅ | ms-andesstay-rabbit-admin | DTOs en `web/dto` con Bean Validation · `RabbitAdminControllersTest` (11 casos) |
| 29 | Protección de la topología del sistema y seguridad por rol en el administrador | ✅ | ms-andesstay-rabbit-admin | `andesstay.rabbit-admin.protected-*` · `RabbitAdminApiIntegrationTest` (401, 403, ciclo completo y 409 contra RabbitMQ real) |

## 6. Frontend

| # | Funcionalidad | Estado | Componente | Evidencia |
|---|---|---|---|---|
| 30 | Dashboard con resumen según el rol | ✅ | frontend-andesstay | `features/dashboard` · commit `ab62113` |
| 31 | Vistas de catálogo, reservas, detalle, pago, reportes y auditoría | ✅ | frontend-andesstay | `src/app/features/*` · commit `0404836` |

## 7. Infraestructura, despliegue y calidad

| # | Funcionalidad | Estado | Componente | Evidencia |
|---|---|---|---|---|
| 32 | Infraestructura local con Docker Compose (Oracle, RabbitMQ, Kafka + Zookeeper) | ✅ | andesstay-infra | `db/`, `mq/`, `kafka/compose.yml` · commit `c4d5b86` |
| 33 | `.gitignore` por tecnología (Maven en el backend, Angular en el frontend) | ✅ | todos los repos | `.gitignore` en la raíz de cada repositorio |
| 34 | Despliegue en AWS: EC2 de infraestructura, una EC2 por microservicio (8), API Gateway, S3, Elastic IP | ✅ | andesstay-infra | `aws/provision.sh`, `aws/deploy-apps.sh`, `aws/redeploy.sh` · commits `842b4ca`, `21b29c7`. Los 8 microservicios responden `UP`; `GET https://e94n72mnmk.execute-api.us-east-1.amazonaws.com/api/rabbit/queues/q.cmd.email` sin token responde `401` (ruta publicada y protegida) |
| 35 | Pruebas automatizadas del backend | 🟡 | todos los microservicios | Pruebas unitarias e integración en notify, reservations y rabbit-admin (`./mvnw test`). catalog, audit, report y bff solo tienen la prueba de arranque (`contextLoads`) |
| 36 | Clúster de Kafka con 3 nodos de Zookeeper y 3 brokers | ✅ | andesstay-infra | `kafka/compose-cluster.yml` (zk1–zk3, kafka1–kafka3, Kafka UI en :8089) y user-data de AWS con los 3 brokers; `provision.sh` abre 9092–9094 y `deploy-apps.sh` exporta `KAFKA_TOPIC_REPLICATION_FACTOR=3` |
| 37 | Clúster de RabbitMQ de 2 nodos | ✅ | andesstay-infra | `mq/compose-cluster.yml` (rabbit1 + rabbit2 con Erlang cookie compartida y `join_cluster`, UI en :15672/:15673) y el mismo par de nodos en `aws/infra-user-data.sh` |

## 8. Ampliación de Kafka — EP5 (encargo) y EP6 (presentación)

| # | Funcionalidad | Estado | Componente | Evidencia |
|---|---|---|---|---|
| 38 | Microservicio administrador de Kafka: crear, listar, describir, modificar configs y eliminar tópicos | ✅ | ms-andesstay-kafka-admin | `POST/GET /api/kafka/topics`, `GET /topics/{name}`, `PATCH /topics/{name}/configs`, `DELETE /topics/{name}` · `service/KafkaAdminService.java` con `AdminClient`, `NewTopic` e `incrementalAlterConfigs` · 7 tests en `mvnw test` · 409 para la topología protegida |
| 39 | Consumer groups: listar, describir offsets por partición, reiniciar offsets y calcular lag | ✅ | ms-andesstay-kafka-admin | `GET /api/kafka/consumer-groups`, `GET /{group}`, `POST /{group}/offsets/reset` · `Lag = LogEndOffset - CurrentOffset` (materia 3.3.1) · `web/dto/PartitionOffsetResponse.java` |
| 40 | Tópicos con 3 particiones, factor de replicación 3 y `min.insync.replicas=2` | ✅ | reservations, audit, report | `config/KafkaTopicsConfig.java` con `NewTopic(...).configs(...)` en los 3 servicios · `andesstay.kafka.partitions=3` · RF desde `KAFKA_TOPIC_REPLICATION_FACTOR` |
| 41 | Políticas de retención por flujo y `cleanup.policy=delete` | ✅ | reservations, audit, report | `reservations.events` 7 días/1 GB · `reservations.events.DLT` 14 días/256 MB · `audit.timeline` 30 días/2 GB · `retention.ms`/`retention.bytes` en los `KafkaTopicsConfig.java` y en los `application.yml` |
| 42 | Productores con `acks=all`, idempotencia, reintentos, compresión y batching | ✅ | reservations, audit, report | `spring.kafka.producer.properties` en los 3 `application.yml`: `acks: all`, `enable.idempotence: true`, `retries: 3`, `compression.type: snappy`, `batch.size: 32768`, `linger.ms: 20` (materia 3.3.2) |
| 43 | Consumidores con un hilo por partición y validación del DTO del evento | ✅ | audit, report | `spring.kafka.listener.concurrency: 3` · `spring-boot-starter-validation` · `@Valid @Payload ReservationEvent` en los `@KafkaListener` · constraints en `messaging/ReservationEvent.java` (materia 3.3.3) |
| 44 | Exposición de la administración de Kafka por el BFF y despliegue en AWS | ✅ | bff + andesstay-infra | `andesstay.downstream.kafka-admin-url` y ruta `kafka` en `DownstreamProperties.asRouteTable()` · `/api/kafka/**` solo Admin en `SecurityConfig` · `SERVICES=(... kafka-admin ...)` y EC2 :8087 en `aws/provision.sh` y `aws/deploy-apps.sh` |
| 45 | Consumidor tipado de `audit.timeline` (ambos tópicos con productor y consumidor) | ✅ | audit + report | `audit` publica `AuditTimelineEntry` con `eventId`; `report` lo consume con `groupId=ms-andesstay-report-audit-timeline` y factory propia (`KafkaConsumerConfig`), valida el DTO y proyecta en `AUDIT_TIMELINE_PROJECTIONS` con idempotencia · `AuditTimelineEventListenerTest` (2 casos) |

## Cómo verificar

- **Endpoints:** con el backend local (ver [README de andesstay-infra](../README.md)) o el API Gateway de AWS, con un token de un usuario del tenant con el rol correspondiente.
- **Pruebas:** `./mvnw test` en cada microservicio. Las de integración de `ms-andesstay-rabbit-admin` necesitan RabbitMQ en `localhost:5672`; las pruebas de arranque con JPA (reservations, audit, report) necesitan Oracle en `localhost:1521`.
- **Mensajería:** consola de RabbitMQ (`:15672`/`:15673`, pestañas Queues y Exchanges) y Kafka UI (`:8089`).
- **Clúster y lag:** `docker exec andesstay-kafka1 kafka-topics --bootstrap-server localhost:9092 --describe` y `kafka-consumer-groups ... --describe`, o las rutas `GET /api/kafka/topics` y `GET /api/kafka/consumer-groups/{group}` del administrador de Kafka (ver los comandos completos en el [README de andesstay-infra](../README.md#verificación-rápida-del-clúster-para-la-demostración)).

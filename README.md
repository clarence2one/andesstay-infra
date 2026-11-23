# andesstay-infra

Infraestructura compartida del proyecto **AndesStay** (caso DSY1107 – Desarrollo Cloud Native I, Duoc UC): los `docker-compose` que levantan Oracle, RabbitMQ y Kafka+Zookeeper para desarrollo local (versión reducida de 1 broker / 1 nodo) y los `compose-cluster.yml` que levantan la topología que pide el caso para la evaluación: **3 Zookeeper + 3 brokers Kafka** y **2 nodos RabbitMQ en clúster**. También están las notas de cómo se replica lo mismo en AWS.

## Contenido

| Carpeta | Qué levanta | Puertos |
|---|---|---|
| `db/` | Oracle Database Free 23ai (imagen `gvenzl/oracle-free:23-slim`), con el PDB `FREEPDB1` y un usuario de aplicación ya creados | `1521` |
| `mq/` | `compose.yml`: RabbitMQ de un solo nodo · `compose-cluster.yml`: **2 nodos en clúster** | `5672`, `5673` (AMQP) · `15672`, `15673` (UI) |
| `kafka/` | `compose.yml`: 1 ZK + 1 broker · `compose-cluster.yml`: **3 ZK + 3 brokers + Kafka UI** (sin KRaft) | `2181`–`2183`, `9092`–`9094`, `8089` (UI) |

Cada carpeta es independiente: se pueden levantar todas juntas o solo las que se necesiten para trabajar en un microservicio puntual. El `compose.yml` simple alcanza para desarrollar; el `compose-cluster.yml` es el que se muestra en la demostración y el que se despliega en AWS.

| Otras carpetas | Contenido |
|---|---|
| `aws/` | Scripts de despliegue en el Learner Lab (ver [Despliegue en AWS](#despliegue-en-aws-aws-academy-learner-lab)) |
| `db/seed-catalog.sql` | Unidades de ejemplo para el catálogo |
| `docs/` | **[Matriz de funcionalidades](docs/matriz-funcionalidades.md)**: alcance completo del proyecto con estado, componente responsable y evidencia de cada funcionalidad |

## Preparar un computador nuevo

| Herramienta | Para qué | Versión |
|---|---|---|
| Git | Clonar los repos | cualquiera |
| Docker Desktop (abierto antes de levantar la infraestructura) | Oracle, RabbitMQ y Kafka en local | 4.x |
| Java (JDK) | Compilar y correr los microservicios | 21 o superior |
| Node.js + npm | Frontend Angular | Node 22 |
| AWS CLI v2 | Solo para desplegar o administrar AWS | 2.x |

**Hardware:** se recomiendan **16 GB de RAM** en el equipo. Oracle, Kafka, RabbitMQ y los 7 microservicios juntos ocupan bastante memoria (en Windows, Docker Desktop corre sobre WSL2 y toma la RAM que necesita del total del equipo).

**Puertos que deben estar libres:** `1521`, `5672`/`5673`, `15672`/`15673`, `2181`–`2183`, `9092`–`9094`, `8089` (infraestructura), `8081`–`8087`, `8090` (microservicios) y `4200` (frontend).

### Clonar los repos

Los 10 repos tienen que quedar como **carpetas hermanas** dentro de una misma carpeta, y el de infraestructura con el nombre `infra` (los scripts de `aws/` buscan `../ms-andesstay-*` e `infra/db/`). Se clona la rama **`main`**, que es la que tiene el código al día.

PowerShell:

```powershell
mkdir AndesStay; cd AndesStay
$repos = "andesstay-infra", "frontend-andesstay", "ms-andesstay-bff", "ms-andesstay-reservations",
         "ms-andesstay-catalog", "ms-andesstay-notify", "ms-andesstay-audit", "ms-andesstay-report",
         "ms-andesstay-rabbit-admin", "ms-andesstay-kafka-admin"
foreach ($r in $repos) { git clone -b main "https://github.com/MarCOCO999/$r.git" }
Rename-Item andesstay-infra infra
```

Git Bash / Linux / Mac:

```bash
mkdir AndesStay && cd AndesStay
for r in andesstay-infra frontend-andesstay ms-andesstay-bff ms-andesstay-reservations ms-andesstay-catalog \
         ms-andesstay-notify ms-andesstay-audit ms-andesstay-report ms-andesstay-rabbit-admin \
         ms-andesstay-kafka-admin; do
  git clone -b main https://github.com/MarCOCO999/$r.git
done
mv andesstay-infra infra
```

Maven no hace falta instalarlo: cada microservicio trae su wrapper (`mvnw` / `mvnw.cmd`). La primera compilación descarga las dependencias, así que requiere internet.

### Cuenta de Azure AD

El login (MSAL) funciona desde cualquier computador porque la redirección es a `http://localhost:4200`, pero la cuenta con la que se ingresa tiene que pertenecer al tenant del caso **y tener asignado un App Role** (`Admin`, `Operador`, `Cliente` o `Auditor`) en la aplicación registrada. Sin rol, el login funciona pero la API responde `403`.

## Cómo levantar todo en local

No requiere ninguna credencial de AWS. Comandos para PowerShell, desde la carpeta `AndesStay`:

**1. Infraestructura** (Docker Desktop abierto). Oracle tarda 1–3 minutos en quedar `(healthy)` en `docker ps`.

```powershell
docker compose -f infra\db\compose.yml up -d
docker compose -f infra\mq\compose.yml up -d
docker compose -f infra\kafka\compose.yml up -d
```

Para levantar la **topología de la evaluación** (3 ZK + 3 brokers y 2 nodos Rabbit) en vez de la versión reducida, reemplazar las dos últimas líneas:

```powershell
docker compose -f infra\mq\compose-cluster.yml up -d
docker compose -f infra\kafka\compose-cluster.yml up -d
```

Con el clúster de 3 brokers, los microservicios tienen que crear los tópicos con factor de replicación 3. Se exporta una sola vez por terminal antes de arrancarlos:

```powershell
$env:KAFKA_TOPIC_REPLICATION_FACTOR=3
$env:KAFKA_BOOTSTRAP_SERVERS="localhost:9092,localhost:9093,localhost:9094"
```

> Si se olvida la variable, el default es `1` (pensado para el broker único del `compose.yml`) y Kafka rechazará la creación de tópicos con RF=3 en un cluster donde `min.insync.replicas=2` no se puede cumplir con una sola réplica. En AWS, `deploy-apps.sh` ya exporta ambas variables con los 3 brokers.

**2. Microservicios**, cada uno en su propia terminal. `catalog` debe arrancar antes que `reservations`, y el BFF al final:

```powershell
cd ms-andesstay-catalog;      .\mvnw.cmd spring-boot:run   # 8083
cd ms-andesstay-reservations; .\mvnw.cmd spring-boot:run   # 8082
cd ms-andesstay-notify;       .\mvnw.cmd spring-boot:run   # 8090
cd ms-andesstay-audit;        .\mvnw.cmd spring-boot:run   # 8084
cd ms-andesstay-report;       .\mvnw.cmd spring-boot:run   # 8085
cd ms-andesstay-rabbit-admin; .\mvnw.cmd spring-boot:run   # 8086
cd ms-andesstay-kafka-admin;  .\mvnw.cmd spring-boot:run   # 8087
cd ms-andesstay-bff;          .\mvnw.cmd spring-boot:run   # 8081
```

Cada uno responde `"status":"UP"` en `http://localhost:<puerto>/actuator/health`.

**3. Datos de ejemplo** (la base parte vacía; correr una vez que `catalog` haya arrancado, porque es Hibernate quien crea las tablas):

```powershell
Get-Content infra\db\seed-catalog.sql | docker exec -i andesstay-oracle sqlplus -s andesstay/changeit@FREEPDB1
```

**4. Frontend** en http://localhost:4200 (`npm ci` solo la primera vez):

```powershell
cd frontend-andesstay; npm ci
npx ng serve          # contra el backend local (localhost:8081)
npx ng serve -c aws   # contra el API Gateway de AWS (environment.aws.ts)
```

| UI local | URL | Credenciales |
|---|---|---|
| Frontend | http://localhost:4200 | cuenta de Azure AD del caso |
| RabbitMQ (nodo 1 / nodo 2 del clúster) | http://localhost:15672 / http://localhost:15673 | `guest` / `guest` |
| Kafka UI (2 tópicos, 3 particiones, 3 réplicas) | http://localhost:8089 | — |

Credenciales por defecto (solo para desarrollo local, nunca usar en un ambiente real): Oracle `andesstay` / `changeit`, RabbitMQ `guest` / `guest`.

**Subida de fotos en local:** es lo único que depende de AWS. `catalog` firma la URL de subida con las credenciales de AWS del computador y contra el bucket de `S3_IMAGES_BUCKET`, así que para probarla hay que tener credenciales del lab vigentes y arrancar catalog con `$env:S3_IMAGES_BUCKET="andesstay-images-<account-id>"`. Todo lo demás funciona sin AWS.

Para apagar: `Ctrl+C` en cada microservicio y `docker compose -f infra\<db|mq|kafka>\compose.yml down` (o `compose-cluster.yml down` si levantaste el clúster; con `-v` se borran también los datos).

### Verificación rápida del clúster (para la demostración)

```powershell
# 3 brokers vivos y 3 Zookeeper
docker ps --format "table {{.Names}}\t{{.Status}}" | Select-String andesstay

# Tópicos con 3 particiones y 3 réplicas (ISR=3)
docker exec andesstay-kafka1 kafka-topics --bootstrap-server localhost:9092 --describe

# Lag por consumer group: Lag = LogEndOffset - CurrentOffset
docker exec andesstay-kafka1 kafka-consumer-groups --bootstrap-server localhost:9092 `
  --group ms-andesstay-audit --describe

# Clúster RabbitMQ de 2 nodos
docker exec andesstay-rabbit1 rabbitmqctl cluster_status
```

Lo mismo se puede ver sin consola desde **Kafka UI** (`http://localhost:8089`) y desde la API del administrador (`GET /api/kafka/topics` y `GET /api/kafka/consumer-groups/ms-andesstay-audit` en `ms-andesstay-kafka-admin`).

## Despliegue en AWS (AWS Academy Learner Lab)

Para la entrega del caso, esta misma infraestructura corre en una **EC2 de infraestructura** (Oracle + clúster RabbitMQ de 2 nodos + clúster Kafka de 3 Zookeeper y 3 brokers vía Docker, la misma configuración que los `compose-cluster.yml`), separada de las EC2 de aplicación (una por microservicio: BFF, reservations, catalog, notify, audit, report, rabbit-admin y **kafka-admin**). Un **API Gateway** HTTP API queda al frente del BFF como única puerta de entrada pública.

```
Angular (localhost:4200) → API Gateway HTTP → BFF (EC2 + Elastic IP :8081) → reservations | catalog | audit | report
                                                                                    │
                       EC2 infra: Oracle :1521 · Rabbit 2 nodos :5672/5673 · Kafka 3 brokers :9092-9094 ◄──┘ (+ notify)
```

### Credenciales del lab

En el Learner Lab: **AWS Details → AWS CLI → Show**, y copiar el bloque completo en `~/.aws/credentials` bajo `[default]`. `aws configure` por sí solo **no alcanza**: no pide el `aws_session_token`, que es obligatorio en el lab (se puede agregar con `aws configure set aws_session_token <token>`). Región: `aws configure set region us-east-1`. Las credenciales vencen al terminar cada sesión del lab y hay que repetir este paso.

```bash
aws sts get-caller-identity   # debe mostrar el rol voclabs
```

### Scripts (`aws/`)

Se corren con **bash** (en Windows, desde Git Bash). Todos usan el rol `LabInstanceProfile` en las EC2, así que ninguna clave de AWS queda en el código ni en las instancias.

| Script | Qué hace |
|---|---|
| `provision.sh` | Crea todo desde cero: security groups, buckets S3 (jars y fotos, con CORS y lectura pública solo de `units/*`), EC2 de infraestructura, una EC2 por microservicio, Elastic IP del BFF y API Gateway. Compila y sube los jars. Si un recurso ya existe lo reutiliza, así que se puede volver a correr. Al terminar imprime la URL del API Gateway. |
| `redeploy.sh <servicio> ...` | Compila el/los microservicio(s), sube el jar y lo reinicia en su EC2 vía SSM. Ej: `./redeploy.sh catalog reservations` |
| `seed.sh` | Carga las unidades de ejemplo en el Oracle de AWS (idempotente). |
| `infra-user-data.sh` | User-data de la EC2 de infraestructura (lo usa `provision.sh`). |
| `deploy-apps.sh` | Lanza las 8 EC2 de aplicación que falten (incluida `kafka-admin`) y actualiza la configuración de las que ya existen, con `KAFKA_TOPIC_REPLICATION_FACTOR=3` y los 3 brokers (lo usa `provision.sh`). |

**Despliegue desde cero** (lab nuevo o cuenta distinta):

```bash
cd infra/aws
./provision.sh
./seed.sh        # unos minutos después, cuando catalog ya arrancó
```

Después, poner la URL del API Gateway que imprimió `provision.sh` en `frontend-andesstay/src/environments/environment.aws.ts` y levantar el frontend contra AWS con `npx ng serve -c aws`.

**Sesiones siguientes del mismo lab:** no hay que desplegar nada. Al iniciar el lab las EC2 se encienden solas, y cada servicio arranca por sí mismo (systemd en las EC2 de aplicación, `restart: unless-stopped` en los contenedores). Las IP privadas no cambian y el BFF tiene Elastic IP, así que el API Gateway sigue funcionando. Lo único que cambia es la IP pública de la EC2 de infraestructura (UIs de RabbitMQ `:15672`, usuario `andesstay` / `changeit`, y Kafka `:8089`):

```bash
aws ec2 describe-instances --filters Name=tag:Name,Values=andesstay-infra \
  --query 'Reservations[0].Instances[0].PublicIpAddress' --output text
```

Se optó por Oracle **auto-gestionado con Docker en EC2** en vez de Amazon RDS for Oracle: RDS for Oracle requiere licencia (BYOL o License Included) y no aplica a los créditos de un Learner Lab, mientras que reutilizar el mismo contenedor que ya se usa en local no tiene costo de licencia y mantiene el mismo comportamiento entre desarrollo y despliegue.

Las imágenes de referencia de las unidades del catálogo se almacenan en **Amazon S3** (con subida directa desde el navegador vía URL prefirmada, ver [ms-andesstay-catalog](https://github.com/MarCOCO999/ms-andesstay-catalog)) en vez de un servicio externo como Cloudinary, para no introducir un proveedor adicional fuera del ecosistema AWS que ya usa el resto del caso.

## Repos relacionados

[frontend-andesstay](https://github.com/MarCOCO999/frontend-andesstay) · [ms-andesstay-bff](https://github.com/MarCOCO999/ms-andesstay-bff) · [ms-andesstay-reservations](https://github.com/MarCOCO999/ms-andesstay-reservations) · [ms-andesstay-catalog](https://github.com/MarCOCO999/ms-andesstay-catalog) · [ms-andesstay-notify](https://github.com/MarCOCO999/ms-andesstay-notify) · [ms-andesstay-audit](https://github.com/MarCOCO999/ms-andesstay-audit) · [ms-andesstay-report](https://github.com/MarCOCO999/ms-andesstay-report) · [ms-andesstay-rabbit-admin](https://github.com/MarCOCO999/ms-andesstay-rabbit-admin) · [ms-andesstay-kafka-admin](https://github.com/MarCOCO999/ms-andesstay-kafka-admin)

#!/bin/bash
# User-data de la EC2 de infraestructura (Amazon Linux 2023): instala Docker y levanta
# Oracle Free, el cluster RabbitMQ de 2 nodos y el cluster Kafka de 3 Zookeeper + 3 brokers
# (compose mq/compose-cluster.yml y kafka/compose-cluster.yml). La unica diferencia con el
# compose local es el listener anunciado de Kafka, que usa la IP privada de esta instancia
# para que las EC2 de aplicacion puedan conectarse a los tres brokers.
set -euxo pipefail

dnf install -y docker
systemctl enable --now docker
mkdir -p /usr/local/lib/docker/cli-plugins
curl -fsSL https://github.com/docker/compose/releases/download/v2.29.7/docker-compose-linux-x86_64 \
  -o /usr/local/lib/docker/cli-plugins/docker-compose
chmod +x /usr/local/lib/docker/cli-plugins/docker-compose

TOKEN=$(curl -s -X PUT http://169.254.169.254/latest/api/token -H "X-aws-ec2-metadata-token-ttl-seconds: 300")
PRIVATE_IP=$(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/local-ipv4)

mkdir -p /opt/andesstay
cat > /opt/andesstay/compose.yml <<EOF
name: andesstay
services:
  oracle:
    image: gvenzl/oracle-free:23-slim
    container_name: andesstay-oracle
    restart: unless-stopped
    ports: ["1521:1521"]
    environment:
      ORACLE_PASSWORD: changeit
      APP_USER: andesstay
      APP_USER_PASSWORD: changeit
    volumes: [oracle-data:/opt/oracle/oradata]

  rabbit1:
    image: rabbitmq:3.13-management
    container_name: andesstay-rabbit1
    hostname: rabbit1
    restart: unless-stopped
    environment:
      RABBITMQ_ERLANG_COOKIE: ANDESSTAY_CLUSTER_COOKIE
      RABBITMQ_DEFAULT_USER: andesstay
      RABBITMQ_DEFAULT_PASS: changeit
      RABBITMQ_NODE_PORT: 5672
    ports: ["5672:5672", "15672:15672"]
    volumes: [rabbit1-data:/var/lib/rabbitmq]
    healthcheck:
      test: ["CMD", "rabbitmq-diagnostics", "-q", "ping"]
      interval: 10s
      timeout: 5s
      retries: 10

  rabbit2:
    image: rabbitmq:3.13-management
    container_name: andesstay-rabbit2
    hostname: rabbit2
    restart: unless-stopped
    depends_on:
      rabbit1:
        condition: service_healthy
    environment:
      RABBITMQ_ERLANG_COOKIE: ANDESSTAY_CLUSTER_COOKIE
      RABBITMQ_DEFAULT_USER: andesstay
      RABBITMQ_DEFAULT_PASS: changeit
      RABBITMQ_NODE_PORT: 5672
    ports: ["5673:5672", "15673:15672"]
    volumes: [rabbit2-data:/var/lib/rabbitmq]
    entrypoint: /bin/bash
    command:
      - -c
      - |
        set -eu
        rabbitmq-server -detached
        until rabbitmqctl -n rabbit@rabbit1 await_startup; do sleep 2; done
        rabbitmqctl stop_app
        rabbitmqctl join_cluster rabbit@rabbit1
        rabbitmqctl start_app
        tail -f /dev/null
    healthcheck:
      test: ["CMD", "rabbitmq-diagnostics", "-q", "ping"]
      interval: 15s
      timeout: 5s
      retries: 15
      start_period: 30s

  zk1:
    image: confluentinc/cp-zookeeper:7.6.1
    container_name: andesstay-zk1
    restart: unless-stopped
    environment:
      ZOOKEEPER_SERVER_ID: 1
      ZOOKEEPER_CLIENT_PORT: 2181
      ZOOKEEPER_TICK_TIME: 2000
      ZOOKEEPER_SERVERS: zk1:2888:3888;zk2:2888:3888;zk3:2888:3888

  zk2:
    image: confluentinc/cp-zookeeper:7.6.1
    container_name: andesstay-zk2
    restart: unless-stopped
    environment:
      ZOOKEEPER_SERVER_ID: 2
      ZOOKEEPER_CLIENT_PORT: 2181
      ZOOKEEPER_TICK_TIME: 2000
      ZOOKEEPER_SERVERS: zk1:2888:3888;zk2:2888:3888;zk3:2888:3888

  zk3:
    image: confluentinc/cp-zookeeper:7.6.1
    container_name: andesstay-zk3
    restart: unless-stopped
    environment:
      ZOOKEEPER_SERVER_ID: 3
      ZOOKEEPER_CLIENT_PORT: 2181
      ZOOKEEPER_TICK_TIME: 2000
      ZOOKEEPER_SERVERS: zk1:2888:3888;zk2:2888:3888;zk3:2888:3888

  kafka1:
    image: confluentinc/cp-kafka:7.6.1
    container_name: andesstay-kafka1
    hostname: kafka1
    restart: unless-stopped
    depends_on: [zk1, zk2, zk3]
    ports: ["9092:9092"]
    environment:
      KAFKA_BROKER_ID: 1
      KAFKA_ZOOKEEPER_CONNECT: zk1:2181,zk2:2181,zk3:2181
      KAFKA_LISTENER_SECURITY_PROTOCOL_MAP: PLAINTEXT:PLAINTEXT,PLAINTEXT_HOST:PLAINTEXT
      KAFKA_LISTENERS: PLAINTEXT://0.0.0.0:29092,PLAINTEXT_HOST://0.0.0.0:9092
      KAFKA_ADVERTISED_LISTENERS: PLAINTEXT://kafka1:29092,PLAINTEXT_HOST://${PRIVATE_IP}:9092
      KAFKA_INTER_BROKER_LISTENER_NAME: PLAINTEXT
      KAFKA_OFFSETS_TOPIC_REPLICATION_FACTOR: 3
      KAFKA_TRANSACTION_STATE_LOG_REPLICATION_FACTOR: 3
      KAFKA_TRANSACTION_STATE_LOG_MIN_ISR: 2
      KAFKA_DEFAULT_REPLICATION_FACTOR: 3
      KAFKA_MIN_INSYNC_REPLICAS: 2
      KAFKA_AUTO_CREATE_TOPICS_ENABLE: "false"

  kafka2:
    image: confluentinc/cp-kafka:7.6.1
    container_name: andesstay-kafka2
    hostname: kafka2
    restart: unless-stopped
    depends_on: [zk1, zk2, zk3]
    ports: ["9093:9092"]
    environment:
      KAFKA_BROKER_ID: 2
      KAFKA_ZOOKEEPER_CONNECT: zk1:2181,zk2:2181,zk3:2181
      KAFKA_LISTENER_SECURITY_PROTOCOL_MAP: PLAINTEXT:PLAINTEXT,PLAINTEXT_HOST:PLAINTEXT
      KAFKA_LISTENERS: PLAINTEXT://0.0.0.0:29092,PLAINTEXT_HOST://0.0.0.0:9092
      KAFKA_ADVERTISED_LISTENERS: PLAINTEXT://kafka2:29092,PLAINTEXT_HOST://${PRIVATE_IP}:9093
      KAFKA_INTER_BROKER_LISTENER_NAME: PLAINTEXT
      KAFKA_OFFSETS_TOPIC_REPLICATION_FACTOR: 3
      KAFKA_TRANSACTION_STATE_LOG_REPLICATION_FACTOR: 3
      KAFKA_TRANSACTION_STATE_LOG_MIN_ISR: 2
      KAFKA_DEFAULT_REPLICATION_FACTOR: 3
      KAFKA_MIN_INSYNC_REPLICAS: 2
      KAFKA_AUTO_CREATE_TOPICS_ENABLE: "false"

  kafka3:
    image: confluentinc/cp-kafka:7.6.1
    container_name: andesstay-kafka3
    hostname: kafka3
    restart: unless-stopped
    depends_on: [zk1, zk2, zk3]
    ports: ["9094:9092"]
    environment:
      KAFKA_BROKER_ID: 3
      KAFKA_ZOOKEEPER_CONNECT: zk1:2181,zk2:2181,zk3:2181
      KAFKA_LISTENER_SECURITY_PROTOCOL_MAP: PLAINTEXT:PLAINTEXT,PLAINTEXT_HOST:PLAINTEXT
      KAFKA_LISTENERS: PLAINTEXT://0.0.0.0:29092,PLAINTEXT_HOST://0.0.0.0:9092
      KAFKA_ADVERTISED_LISTENERS: PLAINTEXT://kafka3:29092,PLAINTEXT_HOST://${PRIVATE_IP}:9094
      KAFKA_INTER_BROKER_LISTENER_NAME: PLAINTEXT
      KAFKA_OFFSETS_TOPIC_REPLICATION_FACTOR: 3
      KAFKA_TRANSACTION_STATE_LOG_REPLICATION_FACTOR: 3
      KAFKA_TRANSACTION_STATE_LOG_MIN_ISR: 2
      KAFKA_DEFAULT_REPLICATION_FACTOR: 3
      KAFKA_MIN_INSYNC_REPLICAS: 2
      KAFKA_AUTO_CREATE_TOPICS_ENABLE: "false"

  kafka-ui:
    image: provectuslabs/kafka-ui:v0.7.2
    container_name: andesstay-kafka-ui
    restart: unless-stopped
    depends_on: [kafka1, kafka2, kafka3]
    ports: ["8089:8080"]
    environment:
      KAFKA_CLUSTERS_0_NAME: andesstay-cluster
      KAFKA_CLUSTERS_0_BOOTSTRAPSERVERS: kafka1:29092,kafka2:29092,kafka3:29092
      KAFKA_CLUSTERS_0_ZOOKEEPER: zk1:2181,zk2:2181,zk3:2181

volumes:
  oracle-data:
  rabbit1-data:
  rabbit2-data:
EOF

docker compose -f /opt/andesstay/compose.yml up -d

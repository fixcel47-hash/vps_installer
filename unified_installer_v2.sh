#!/bin/bash

# ============================================
# Instalador Unificado de Herramientas Docker
# ============================================

# Colores para mensajes
RED=\'\\033[0;31m\'
GREEN=\'\\033[0;32m\'
YELLOW=\'\\033[0;33m\'
BLUE=\'\\033[0;34m\'
NC=\'\\033[0m\' # No Color

# Funciones de mensaje
show_message() { echo -e "${BLUE}[INFO]${NC} $1"; }
show_error() { echo -e "${RED}[ERROR]${NC} $1"; }
show_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; };
show_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }

# Función para solicitar entrada al usuario
ask_for_input() {
    local prompt_message="$1"
    local default_value="$2"
    local input_var_name="$3"
    local hide_input="$4" # \'true\' to hide input (for passwords)
    local input_value

    while true; do
        if [ -n "$default_value" ]; then
            if [ "$hide_input" = "true" ]; then
                read -s -p "${GREEN}${prompt_message} (default: *****): ${NC}" input_value
            else
                read -p "${GREEN}${prompt_message} (default: $default_value): ${NC}" input_value
            fi
        else
            if [ "$hide_input" = "true" ]; then
                read -s -p "${GREEN}${prompt_message}: ${NC}" input_value
            else
                read -p "${GREEN}${prompt_message}: ${NC}" input_value
            fi
        fi
        echo # Add a newline after silent input

        if [ -z "$input_value" ]; then
            if [ -n "$default_value" ]; then
                eval "$input_var_name=\"$default_value\""
                break
            else
                show_warning "Este campo no puede estar vacío. Por favor, introduce un valor."
            fi
        else
            eval "$input_var_name=\"$input_value\""
            break
        fi
    done
}

# Función para validar un dominio
validate_domain() {
    local domain="$1"
    # Expresión regular para validar un dominio simple (no cubre todos los casos, pero es suficiente para este contexto)
    if [[ $domain =~ ^[a-zA-Z0-9]([a-zA-Z0-9\\-]{0,61}[a-zA-Z0-9])?\\.[a-zA-Z]{2,}$ ]]; then
        return 0 # Válido
    else
        return 1 # Inválido
    fi
}

# Función para validar un email
validate_email() {
    local email="$1"
    # Expresión regular para validar un email simple
    if [[ $email =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$ ]]; then
        return 0 # Válido
    else
        return 1 # Inválido
    fi
}

# Función para solicitar y validar el dominio
ask_and_validate_domain() {
    local input_var_name="$1"
    local default_domain="$2"
    local domain_val
    while true; do
        ask_for_input "Introduce tu dominio (ej. midominio.com para HTTPS con Let\'s Encrypt)" "$default_domain" "domain_val"
        if [ -z "$domain_val" ]; then
            show_warning "No se ha introducido un dominio. Se utilizarán certificados auto-firmados y acceso por IP/puerto."
            eval "$input_var_name=\"\""
            break
        elif validate_domain "$domain_val"; then
            eval "$input_var_name=\"$domain_val\""
            break
        else
            show_error "Dominio inválido. Por favor, introduce un dominio válido o déjalo en blanco para auto-firmados."
        fi
    done
}

# Función para solicitar y validar el email
ask_and_validate_email() {
    local input_var_name="$1"
    local default_email="$2"
    local email_val
    while true; do
        ask_for_input "Introduce tu correo electrónico para Let\'s Encrypt (ej. tu@email.com)" "$default_email" "email_val"
        if [ -z "$email_val" ]; then
            show_warning "No se ha introducido un email. Let\'s Encrypt no estará disponible."
            eval "$input_var_name=\"\""
            break
        elif validate_email "$email_val"; then
            eval "$input_var_name=\"$email_val\""
            break
        else
            show_error "Correo electrónico inválido. Por favor, introduce un email válido o déjalo en blanco."
        fi
    done
}

# Función para solicitar y confirmar contraseña
ask_and_confirm_password() {
    local prompt_message="$1"
    local input_var_name="$2"
    local password_val
    local password_confirm
    while true; do
        ask_for_input "$prompt_message" "" "password_val" "true"
        ask_for_input "Confirma tu contraseña" "" "password_confirm" "true"
        if [ "$password_val" = "$password_confirm" ]; then
            eval "$input_var_name=\"$password_val\""
            break
        else
            show_error "Las contraseñas no coinciden. Inténtalo de nuevo."
        fi
    done
}

# Función para generar clave aleatoria de 32 caracteres (para SECRET_KEY_BASE y N8N_ENCRYPTION_KEY)
generate_random_key() {
    tr -dc \'A-Za-z0-9\'< /dev/urandom | head -c 32
}

# Función para generar un hash de contraseña para Traefik BasicAuth
generate_htpasswd() {
    local password="$1"
    echo "$(htpasswd -nb admin "$password" | sed -e \'s/\\$/\\$\\$/g\')"
}

# Función para ejecutar comandos mostrando animación de espera (simplificada)
run_command() {
    local cmd="$1"
    local msg="$2"
    show_message "$msg"
    if ! eval "$cmd"; then
        show_error "El comando falló: $cmd"
        exit 1
    fi
}

# Requiere root
if [ "$EUID" -ne 0 ]; then
  show_error "Este script debe ejecutarse como root (sudo)."
  exit 1
fi

show_message "Inicio del instalador unificado (Ubuntu 22.04)"

# === SOLICITAR DATOS AL USUARIO ===
show_message "\\n--- Configuración de la Instalación ---"

# Contraseña de administrador
ADMIN_PASSWORD=""
ask_and_confirm_password "Introduce tu contraseña de administrador (para servicios y Traefik Dashboard)" "ADMIN_PASSWORD"

# Dominio y Email
DOMAIN=""
EMAIL=""
ask_and_validate_domain "DOMAIN" ""
if [ -n "$DOMAIN" ]; then
    ask_and_validate_email "EMAIL" ""
fi

# Subdominios para los servicios
CHATWOOT_SUBDOMAIN="chatwoot"
N8N_SUBDOMAIN="n8n"
N8N_WEBHOOK_SUBDOMAIN="webhook"
PORTAINER_SUBDOMAIN="portainer"
REDISINSIGHT_SUBDOMAIN="redisinsight"
TRAEFIK_SUBDOMAIN="traefik"
EVOAPI_SUBDOMAIN="evoapi"
RABBITMQ_SUBDOMAIN="rabbitmq"

# Generar claves secretas
SECRET_KEY_BASE_CHATWOOT=$(generate_random_key)
N8N_ENCRYPTION_KEY=$(generate_random_key)
EVOAPI_SECRET_KEY=$(generate_random_key)
EVOAPI_AUTH_API_KEY=$(generate_random_key)
EVOAPI_RABBITMQ_ERLANG_COOKIE=$(generate_random_key)

# Generar hash de contraseña para Traefik BasicAuth
TRAEFIK_DASHBOARD_AUTH_HASH=$(generate_htpasswd "$ADMIN_PASSWORD")

show_message "\\n--- Resumen de Configuración ---"
show_message "Contraseña de Administrador: ******** (oculta)"
show_message "Dominio principal: ${DOMAIN:-No especificado (usando IP/localhost)}"
if [ -n "$DOMAIN" ]; then
    show_message "Email para Let\'s Encrypt: ${EMAIL}"
    show_message "Subdominio Chatwoot: ${CHATWOOT_SUBDOMAIN}.${DOMAIN}"
    show_message "Subdominio n8n: ${N8N_SUBDOMAIN}.${DOMAIN}"
    show_message "Subdominio n8n Webhook: ${N8N_WEBHOOK_SUBDOMAIN}.${DOMAIN}"
    show_message "Subdominio Portainer: ${PORTAINER_SUBDOMAIN}.${DOMAIN}"
    show_message "Subdominio RedisInsight: ${REDISINSIGHT_SUBDOMAIN}.${DOMAIN}"
    show_message "Subdominio Traefik Dashboard: ${TRAEFIK_SUBDOMAIN}.${DOMAIN}"
    show_message "Subdominio EvoAPI: ${EVOAPI_SUBDOMAIN}.${DOMAIN}"
    show_message "Subdominio RabbitMQ: ${RABBITMQ_SUBDOMAIN}.${DOMAIN}"
else
    show_message "Email para Let\'s Encrypt: No aplicable (no se especificó dominio)"
fi

read -p "Presiona Enter para continuar con la instalación o Ctrl+C para cancelar..."

# === VARIABLES INTERNAS ===
DATA_DIR="/home/docker"

# === PASOS DE INSTALACIÓN ===

# 1) Actualizar e instalar dependencias básicas
run_command "export DEBIAN_FRONTEND=noninteractive && apt-get update -y && apt-get upgrade -y && apt-get install -y ca-certificates curl gnupg lsb-release wget software-properties-common apt-transport-https apache2-utils" "Actualizando paquetes e instalando dependencias básicas (incluyendo apache2-utils para htpasswd)..."

# 2) Instalar Docker
if ! command -v docker >/dev/null 2>&1; then
  run_command "mkdir -p /etc/apt/keyrings && curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg && echo \"deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable\" | tee /etc/apt/sources.list.d/docker.list > /dev/null && apt-get update -y && apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin" "Instalando Docker Engine..."
  show_success "Docker instalado."
else
  show_message "Docker ya está instalado."
fi

# 3) Crear red Docker Swarm y redes frontend/backend
show_message "Inicializando Docker Swarm y creando redes..."
if ! docker info | grep -q "Swarm: active"; then
    run_command "docker swarm init" "Inicializando Docker Swarm..."
else
    show_message "Docker Swarm ya está inicializado."
fi

if ! docker network ls | grep -q "frontend"; then
    run_command "docker network create --driver overlay --attachable frontend" "Creando red Docker overlay \'frontend\'..."
else
    show_message "La red Docker \'frontend\' ya existe."
fi

if ! docker network ls | grep -q "backend"; then
    run_command "docker network create --driver overlay --attachable backend" "Creando red Docker overlay \'backend\'..."
else
    show_message "La red Docker \'backend\' ya existe."
fi

# 4) Crear directorios de datos
show_message "Creando directorios de datos para los servicios en ${DATA_DIR}..."
run_command "mkdir -p ${DATA_DIR}/traefik/letsencrypt ${DATA_DIR}/portainer/portainer_data ${DATA_DIR}/postgres/postgres_data ${DATA_DIR}/redis/redis_cache ${DATA_DIR}/redis/redisinsight ${DATA_DIR}/n8n/db ${DATA_DIR}/n8n/data ${DATA_DIR}/n8n/local-files ${DATA_DIR}/evoapi/evolution_instances ${DATA_DIR}/evoapi/evolution_postgres_data ${DATA_DIR}/evoapi/evolution_rabbitmq_data ${DATA_DIR}/chatwoot/chatwoot_storage ${DATA_DIR}/chatwoot/postgres_data" "Creando directorios..."

# 5) Generar docker-compose.yml unificado
COMPOSE_FILE="${DATA_DIR}/docker-compose.yml"

cat > "${COMPOSE_FILE}" <<EOF
version: '3.8'

services:
  # Traefik
  traefik:
    image: traefik:latest
    restart: unless-stopped
    command:
      - "--log.level=DEBUG"
      - "--api=true"
      - "--api.dashboard=true"
      - "--providers.swarm.endpoint=unix:///var/run/docker.sock"
      - "--providers.swarm.exposedbydefault=false"
      - "--providers.swarm.network=frontend"
      # Entrypoints
      - "--entrypoints.web.address=:80"
      - "--entrypoints.websecure.address=:443"
      - "--entrypoints.websecure.transport.respondingTimeouts.idleTimeout=3600"
      # Redirección HTTP a HTTPS
      - "--entrypoints.web.http.redirections.entryPoint.to=websecure"
      - "--entrypoints.web.http.redirections.entrypoint.permanent=true"
      - "--entrypoints.web.http.redirections.entryPoint.scheme=https"
      # Certbot/Let's Encrypt
      - "--certificatesresolvers.le.acme.httpchallenge=true"
      - "--certificatesresolvers.le.acme.httpchallenge.entrypoint=web"
      - "--certificatesresolvers.le.acme.email=${EMAIL}"
      - "--certificatesresolvers.le.acme.storage=/letsencrypt/acme.json"
      
    ports:
      - 80:80
      - 443:443
      
    networks:
      - frontend
      
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
      - traefik_letsencrypt:/letsencrypt

    deploy:
      mode: global
      placement:
        constraints:
          - node.role == manager
      labels:
        - traefik.enable=true
        - traefik.http.routers.traefik.rule=Host(\`${TRAEFIK_SUBDOMAIN}.${DOMAIN}\`)
        - traefik.http.routers.traefik.entrypoints=websecure
        - traefik.http.routers.traefik.tls.certresolver=le
        - traefik.http.routers.traefik.service=api@internal
        - traefik.http.routers.traefik.middlewares=auth
        - traefik.http.middlewares.auth.basicauth.users=${TRAEFIK_DASHBOARD_AUTH_HASH}
        - "traefik.http.services.dummy-svc.loadbalancer.server.port=9999"

  # Portainer
  agent:
    image: portainer/agent:latest 
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - /var/lib/docker/volumes:/var/lib/docker/volumes
    networks:
      - frontend
    deploy:
      mode: global
      placement:
        constraints: [node.platform.os == linux]

  portainer:
    image: portainer/portainer-ce:latest 
    command: -H tcp://tasks.agent:9001 --tlsskipverify
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - portainer_data:/data
    networks:
      - frontend
    deploy:
      mode: replicated
      replicas: 1
      placement:
        constraints: [node.role == manager]
      labels:
        - "traefik.enable=true"
        - "traefik.http.routers.portainer.rule=Host(\`${PORTAINER_SUBDOMAIN}.${DOMAIN}\`)" 
        - "traefik.http.services.portainer.loadbalancer.server.port=9000"
        - "traefik.http.routers.portainer.tls.certresolver=le"
        - "traefik.http.routers.portainer.service=portainer"
        - "traefik.docker.network=frontend"
        - "traefik.http.routers.portainer.entrypoints=websecure"
        - "traefik.http.routers.portainer.priority=1"

  # PostgreSQL (General)
  postgres-server:
    image: postgres:latest
    environment:
      POSTGRES_USER: postgres
      POSTGRES_PASSWORD: ${ADMIN_PASSWORD}
      POSTGRES_DB: default_db
    deploy:
      mode: replicated
      replicas: 1
    volumes:
      - postgres_data:/var/lib/postgresql/data
    networks:
      - backend
    restart: unless-stopped

  # Redis (General)
  redis-server:
    image: redis:latest
    command: redis-server --loglevel warning
    deploy:
      replicas: 1
      restart_policy:
        condition: any
    volumes:
      - redis_cache:/data
    networks:
      - backend

  redisinsight:
    image: redislabs/redisinsight:latest
    deploy:
      mode: replicated
      replicas: 1
      labels:
       - "traefik.enable=true"
       - "traefik.http.routers.redisinsight.rule=Host(\`${REDISINSIGHT_SUBDOMAIN}.${DOMAIN}\`)"
       - "traefik.http.routers.redisinsight.service=redisinsight"
       - "traefik.http.routers.redisinsight.entrypoints=websecure"
       - "traefik.http.routers.redisinsight.tls.certresolver=le"
       - "traefik.http.routers.redisinsight.tls=true"
       - "traefik.http.services.redisinsight.loadbalancer.server.port=5540"
    volumes:
      - redisinsight:/data
    networks:
      - backend
      - frontend

  # n8n
  'n8n-db':
    image: postgres:16
    restart: always
    user: root
    environment:
      - POSTGRES_USER=postgres
      - POSTGRES_DB=n8n
      - POSTGRES_PASSWORD=${ADMIN_PASSWORD}
    networks:
      - backend
    deploy:
      replicas: 1
      placement:
        constraints: [node.role == manager]
    volumes:
      - n8n_db:/var/lib/postgresql/data

  n8n_editor:
    image: n8nio/n8n:latest
    restart: always
    user: root
    environment:
      - N8N_ENCRYPTION_KEY=${N8N_ENCRYPTION_KEY}
      - DB_TYPE=postgresdb
      - DB_POSTGRESDB_HOST=n8n-db
      - DB_POSTGRESDB_PORT=5432
      - DB_POSTGRESDB_DATABASE=n8n
      - DB_POSTGRESDB_USER=postgres
      - DB_POSTGRESDB_PASSWORD=${ADMIN_PASSWORD}
      - N8N_PROTOCOL=https
      - N8N_HOST=${N8N_SUBDOMAIN}.${DOMAIN}
      - N8N_EDITOR_BASE_URL=https://${N8N_SUBDOMAIN}.${DOMAIN}
      - WEBHOOK_URL=https://${N8N_WEBHOOK_SUBDOMAIN}.${DOMAIN}
      - NODE_ENV=production
      - N8N_ENFORCE_SETTINGS_FILE_PERMISSIONS=true
      - EXECUTIONS_MODE=queue
      - QUEUE_BULL_REDIS_HOST=redis-server
      - QUEUE_BULL_REDIS_DB=2
      - QUEUE_BULL_REDIS_PORT=6379
      # - QUEUE_BULL_REDIS_PASSWORD=REPLACE_PASSWORD # Redis no tiene contraseña en esta configuración
      - OFFLOAD_MANUAL_EXECUTIONS_TO_WORKERS=true
      - N8N_RUNNERS_ENABLED=true
      - N8N_SECURE_COOKIE=false
    deploy:
      mode: replicated
      replicas: 1
      placement:
        constraints:
          - node.role == manager
      labels:
        - traefik.enable=true
        - traefik.http.routers.n8n_editor.rule=Host(\`${N8N_SUBDOMAIN}.${DOMAIN}\`)
        - traefik.http.routers.n8n_editor.service=n8n_editor
        - traefik.http.routers.n8n_editor.entrypoints=websecure
        - traefik.http.routers.n8n_editor.tls.certresolver=le
        - traefik.http.routers.n8n_editor.tls=true
        - traefik.http.services.n8n_editor.loadbalancer.server.port=5678
    volumes:
      - n8n_data:/home/node/.n8n
      - n8n_local-files:/files
    networks:
      - frontend
      - backend

  n8n_worker:
    image: n8nio/n8n:latest
    restart: always
    user: root
    command: worker --concurrency=5
    environment:
      - N8N_ENCRYPTION_KEY=${N8N_ENCRYPTION_KEY}
      - DB_TYPE=postgresdb
      - DB_POSTGRESDB_HOST=n8n-db
      - DB_POSTGRESDB_PORT=5432
      - DB_POSTGRESDB_DATABASE=n8n
      - DB_POSTGRESDB_USER=postgres
      - DB_POSTGRESDB_PASSWORD=${ADMIN_PASSWORD}
      - N8N_PROTOCOL=https
      - N8N_HOST=${N8N_SUBDOMAIN}.${DOMAIN}
      - N8N_EDITOR_BASE_URL=https://${N8N_SUBDOMAIN}.${DOMAIN}
      - WEBHOOK_URL=https://${N8N_WEBHOOK_SUBDOMAIN}.${DOMAIN}
      - NODE_ENV=production
      - N8N_ENFORCE_SETTINGS_FILE_PERMISSIONS=true
      - EXECUTIONS_MODE=queue
      - QUEUE_BULL_REDIS_HOST=redis-server
      - QUEUE_BULL_REDIS_DB=2
      - QUEUE_BULL_REDIS_PORT=6379
      # - QUEUE_BULL_REDIS_PASSWORD=REPLACE_PASSWORD
      - OFFLOAD_MANUAL_EXECUTIONS_TO_WORKERS=true
      - N8N_RUNNERS_ENABLED=true
      - N8N_SECURE_COOKIE=false
    deploy:
      mode: replicated
      replicas: 1
      placement:
        constraints:
          - node.role == manager
    volumes:
      - n8n_data:/home/node/.n8n
      - n8n_local-files:/files
    networks:
      - backend

  n8n_webhook:
    image: n8nio/n8n:latest
    restart: always
    user: root
    command: webhook
    environment:
      - N8N_ENCRYPTION_KEY=${N8N_ENCRYPTION_KEY}
      - DB_TYPE=postgresdb
      - DB_POSTGRESDB_HOST=n8n-db
      - DB_POSTGRESDB_PORT=5432
      - DB_POSTGRESDB_DATABASE=n8n
      - DB_POSTGRESDB_USER=postgres
      - DB_POSTGRESDB_PASSWORD=${ADMIN_PASSWORD}
      - N8N_PROTOCOL=https
      - N8N_HOST=${N8N_SUBDOMAIN}.${DOMAIN}
      - N8N_EDITOR_BASE_URL=https://${N8N_SUBDOMAIN}.${DOMAIN}
      - WEBHOOK_URL=https://${N8N_WEBHOOK_SUBDOMAIN}.${DOMAIN}
      - NODE_ENV=production
      - N8N_ENFORCE_SETTINGS_FILE_PERMISSIONS=true
      - EXECUTIONS_MODE=queue
      - QUEUE_BULL_REDIS_HOST=redis-server
      - QUEUE_BULL_REDIS_DB=2
      - QUEUE_BULL_REDIS_PORT=6379
      # - QUEUE_BULL_REDIS_PASSWORD=REPLACE_PASSWORD
      - OFFLOAD_MANUAL_EXECUTIONS_TO_WORKERS=true
      - N8N_RUNNERS_ENABLED=true
      - N8N_SECURE_COOKIE=false
    deploy:
      mode: replicated
      replicas: 1
      placement:
        constraints:
          - node.role == manager
      labels:
        - traefik.enable=true
        - traefik.http.routers.n8n_webhook.rule=Host(\`${N8N_WEBHOOK_SUBDOMAIN}.${DOMAIN}\`)
        - traefik.http.routers.n8n_webhook.service=n8n_webhook
        - traefik.http.routers.n8n_webhook.entrypoints=websecure
        - traefik.http.routers.n8n_webhook.tls.certresolver=le
        - traefik.http.routers.n8n_webhook.tls=true
        - traefik.http.services.n8n_webhook.loadbalancer.server.port=5678
    volumes:
      - n8n_data:/home/node/.n8n
      - n8n_local-files:/files
    networks:
      - frontend
      - backend

  # EvoAPI
  evolution-api:
    container_name: evolution-api
    image: evoapicloud/evolution-api:latest
    restart: always
    deploy:
      mode: replicated
      replicas: 1
      restart_policy:
        condition: any
        delay: 5s
      update_config:
        parallelism: 1
        delay: 10s
        order: start-first
      labels:
        - "traefik.enable=true"
        - "traefik.http.routers.evolution-api.rule=Host(\`${EVOAPI_SUBDOMAIN}.${DOMAIN}\`)"
        - "traefik.http.routers.evolution-api.entrypoints=websecure"
        - "traefik.http.routers.evolution-api.tls=true"
        - "traefik.http.routers.evolution-api.tls.certresolver=le"
        - "traefik.http.services.evolution-api.loadbalancer.server.port=8080"
        - "traefik.docker.network=frontend"
    volumes:
      - evolution_instances:/evolution/instances
    networks:
      - frontend
      - backend
    environment:
      - SUBDOMAIN=${EVOAPI_SUBDOMAIN}
      - DOMAIN=${DOMAIN}
      - PASSWORD=${ADMIN_PASSWORD}
      - SECRET_KEY=${EVOAPI_SECRET_KEY}
      - SERVER_TYPE=http
      - SERVER_PORT=8080
      - SERVER_URL=https://${EVOAPI_SUBDOMAIN}.${DOMAIN}
      - CORS_ORIGIN=*
      - CORS_METHODS=GET,POST,PUT,DELETE
      - CORS_CREDENTIALS=true
      - LOG_LEVEL=ERROR,WARN,DEBUG,INFO,LOG,VERBOSE,DARK,WEBHOOKS,WEBSOCKET
      - LOG_COLOR=true
      - LOG_BAILEYS=error
      - EVENT_EMITTER_MAX_LISTENERS=50
      - DEL_INSTANCE=false
      - DATABASE_PROVIDER=postgresql
      - DATABASE_CONNECTION_URI=postgresql://postgres:${ADMIN_PASSWORD}@postgres-evoapi:5432/evolution2?schema=public
      - DATABASE_CONNECTION_CLIENT_NAME=evoapi
      - DATABASE_SAVE_DATA_INSTANCE=true
      - DATABASE_SAVE_DATA_NEW_MESSAGE=true
      - DATABASE_SAVE_MESSAGE_UPDATE=true
      - DATABASE_SAVE_DATA_CONTACTS=true
      - DATABASE_SAVE_DATA_CHATS=true
      - DATABASE_SAVE_DATA_LABELS=true
      - DATABASE_SAVE_DATA_HISTORIC=true
      - DATABASE_SAVE_IS_ON_WHATSAPP=true
      - DATABASE_SAVE_IS_ON_WHATSAPP_DAYS=7
      - DATABASE_DELETE_MESSAGE=true
      - RABBITMQ_ENABLED=true
      - RABBITMQ_URI=amqp://evo-rabbit:${ADMIN_PASSWORD}@rabbitmq:5672/default
      - RABBITMQ_EXCHANGE_NAME=evolution
      - RABBITMQ_ERLANG_COOKIE=${EVOAPI_RABBITMQ_ERLANG_COOKIE}
      - RABBITMQ_DEFAULT_VHOST=default
      - RABBITMQ_DEFAULT_USER=evo-rabbit
      - RABBITMQ_DEFAULT_PASS=${ADMIN_PASSWORD}
      - RABBITMQ_GLOBAL_ENABLED=false
      - SQS_ENABLED=false
      - WEBSOCKET_ENABLED=false
      - PUSHER_ENABLED=false
      - WA_BUSINESS_TOKEN_WEBHOOK=evolution
      - WA_BUSINESS_URL=https://graph.facebook.com
      - WA_BUSINESS_VERSION=v20.0
      - WA_BUSINESS_LANGUAGE=en_US
      - WEBHOOK_GLOBAL_ENABLED=false
      - WEBHOOK_GLOBAL_URL=\'\'
      - WEBHOOK_GLOBAL_WEBHOOK_BY_EVENTS=false
      - CONFIG_SESSION_PHONE_CLIENT=Evolution API
      - CONFIG_SESSION_PHONE_NAME=Chrome
      - CONFIG_SESSION_PHONE_VERSION=2.3000.1023204200
      - QRCODE_LIMIT=30
      - QRCODE_COLOR=\'#175197\'
      - TYPEBOT_ENABLED=true
      - TYPEBOT_API_VERSION=latest
      - CHATWOOT_ENABLED=true
      - CHATWOOT_MESSAGE_READ=true
      - CHATWOOT_MESSAGE_DELETE=true
      - CHATWOOT_BOT_CONTACT=true
      - CHATWOOT_IMPORT_DATABASE_CONNECTION_URI=\'postgresql://postgres:${ADMIN_PASSWORD}@chatwoot-postgres:5432/chatwoot?sslmode=disable\'
      - CHATWOOT_IMPORT_PLACEHOLDER_MEDIA_MESSAGE=true
      - OPENAI_ENABLED=false
      - DIFY_ENABLED=false
      - CACHE_REDIS_ENABLED=true
      - CACHE_REDIS_URI=redis://redis-server:6379/3
      - CACHE_REDIS_TTL=604800
      - CACHE_REDIS_PREFIX_KEY=evolution
      - CACHE_REDIS_SAVE_INSTANCES=false
      - CACHE_LOCAL_ENABLED=false
      - S3_ENABLED=false
      - AUTHENTICATION_API_KEY=${EVOAPI_AUTH_API_KEY}
      - AUTHENTICATION_EXPOSE_IN_FETCH_INSTANCES=true
      - LANGUAGE=es

  postgres-evoapi:
    image: postgres:15
    networks:
      - backend
    deploy:
      mode: replicated
      replicas: 1
      restart_policy:
        condition: any
        delay: 5s
    environment:
      - POSTGRES_DB=evolution2
      - POSTGRES_USER=postgres
      - POSTGRES_PASSWORD=${ADMIN_PASSWORD}
    volumes:
      - evolution_postgres_data:/var/lib/postgresql/data

  rabbitmq:
    image: rabbitmq:management
    entrypoint: docker-entrypoint.sh
    command: rabbitmq-server
    deploy:
      mode: replicated
      replicas: 1
      restart_policy:
        condition: any
        delay: 5s
      labels:
        - "traefik.enable=true"
        - "traefik.http.routers.rabbitmq.rule=Host(\`${RABBITMQ_SUBDOMAIN}.${DOMAIN}\`)"
        - "traefik.http.routers.rabbitmq.entrypoints=websecure"
        - "traefik.http.routers.rabbitmq.tls=true"
        - "traefik.http.routers.rabbitmq.tls.certresolver=le"
        - "traefik.http.services.rabbitmq.loadbalancer.server.port=15672"
        - "traefik.docker.network=frontend"
    volumes:
      - evolution_rabbitmq_data:/var/lib/rabbitmq/
    environment:
      - RABBITMQ_ERLANG_COOKIE=${EVOAPI_RABBITMQ_ERLANG_COOKIE}
      - RABBITMQ_DEFAULT_VHOST=default
      - RABBITMQ_DEFAULT_USER=evo-rabbit
      - RABBITMQ_DEFAULT_PASS=${ADMIN_PASSWORD}
    networks:
      - frontend
      - backend

  # Chatwoot
  chatwoot-rails:
    image: chatwoot/chatwoot:latest
    environment:
      - NODE_ENV=production
      - RAILS_ENV=production
      - INSTALLATION_ENV=docker
      - SECRET_KEY_BASE=${SECRET_KEY_BASE_CHATWOOT}
      - FRONTEND_URL=https://${CHATWOOT_SUBDOMAIN}.${DOMAIN}
      - WEBSOCKET_URL=wss://${CHATWOOT_SUBDOMAIN}.${DOMAIN}/cable
      - FORCE_SSL=true
      - ENABLE_ACCOUNT_SIGNUP=false
      - REDIS_URL=redis://redis-server:6379/4
      - POSTGRES_DATABASE=chatwoot
      - POSTGRES_HOST=chatwoot-postgres
      - POSTGRES_USERNAME=postgres
      - POSTGRES_PASSWORD=${ADMIN_PASSWORD}
      - RAILS_LOG_TO_STDOUT=true
      - LOG_LEVEL=info
    volumes:
      - chatwoot_storage:/app/storage
    entrypoint: docker/entrypoints/rails.sh
    command: ['bundle', 'exec', 'rails', 's', '-p', '3000', '-b', '0.0.0.0']
    deploy:
      replicas: 1
      restart_policy:
        condition: on-failure
      labels:
        - "traefik.enable=true"
        - "traefik.http.routers.chatwoot.rule=Host(\`${CHATWOOT_SUBDOMAIN}.${DOMAIN}\`)"
        - "traefik.http.routers.chatwoot.entrypoints=websecure"
        - "traefik.http.routers.chatwoot.tls=true"
        - "traefik.http.routers.chatwoot.tls.certresolver=le"
        - "traefik.http.services.chatwoot.loadbalancer.server.port=3000"
        - "traefik.http.middlewares.sslheader.headers.customrequestheaders.X-Forwarded-Proto=https"
        - "traefik.http.routers.chatwoot.middlewares=sslheader"
    networks:
      - frontend
      - backend

  chatwoot-sidekiq:
    image: chatwoot/chatwoot:latest
    environment:
      - NODE_ENV=production
      - RAILS_ENV=production
      - INSTALLATION_ENV=docker
      - SECRET_KEY_BASE=${SECRET_KEY_BASE_CHATWOOT}
      - FRONTEND_URL=https://${CHATWOOT_SUBDOMAIN}.${DOMAIN}
      - WEBSOCKET_URL=wss://${CHATWOOT_SUBDOMAIN}.${DOMAIN}/cable
      - FORCE_SSL=true
      - ENABLE_ACCOUNT_SIGNUP=false
      - REDIS_URL=redis://redis-server:6379/4
      - POSTGRES_DATABASE=chatwoot
      - POSTGRES_HOST=chatwoot-postgres
      - POSTGRES_USERNAME=postgres
      - POSTGRES_PASSWORD=${ADMIN_PASSWORD}
      - RAILS_LOG_TO_STDOUT=true
      - LOG_LEVEL=info
    volumes:
      - chatwoot_storage:/app/storage
    command: ['bundle', 'exec', 'sidekiq', '-C', 'config/sidekiq.yml']
    deploy:
      replicas: 1
      restart_policy:
        condition: on-failure
    networks:
      - backend

  chatwoot-postgres:
    image: pgvector/pgvector:pg16
    environment:
      - POSTGRES_DB=chatwoot
      - POSTGRES_USER=postgres
      - POSTGRES_PASSWORD=${ADMIN_PASSWORD}
    volumes:
      - chatwoot_postgres:/var/lib/postgresql/data
    deploy:
      replicas: 1
      restart_policy:
        condition: on-failure
    networks:
      - backend

networks:
  frontend:
    external: true
  backend:
    external: true

volumes:
  traefik_letsencrypt:
    driver: local
    driver_opts:
      type: none
      device: ${DATA_DIR}/traefik/letsencrypt
      o: bind
  portainer_data:
    driver: local
    driver_opts:
      type: none
      device: ${DATA_DIR}/portainer/portainer_data
      o: bind
  postgres_data:
    driver: local
    driver_opts:
      type: none
      device: ${DATA_DIR}/postgres/postgres_data
      o: bind
  redis_cache:
    driver: local
    driver_opts:
      type: none
      device: ${DATA_DIR}/redis/redis_cache
      o: bind
  redisinsight:
    driver: local
    driver_opts:
      type: none
      device: ${DATA_DIR}/redis/redisinsight
      o: bind
  n8n_db:
    driver: local
    driver_opts:
      type: none
      device: ${DATA_DIR}/n8n/db
      o: bind
  n8n_data:
    driver: local
    driver_opts:
      type: none
      device: ${DATA_DIR}/n8n/data
      o: bind
  n8n_local-files:
    driver: local
    driver_opts:
      type: none
      device: ${DATA_DIR}/n8n/local-files
      o: bind
  evolution_instances:
    driver: local
    driver_opts:
      type: none
      device: ${DATA_DIR}/evoapi/evolution_instances
      o: bind
  evolution_postgres_data:
    driver: local
    driver_opts:
      type: none
      device: ${DATA_DIR}/evoapi/evolution_postgres_data
      o: bind
  evolution_rabbitmq_data:
    driver: local
    driver_opts:
      type: none
      device: ${DATA_DIR}/evoapi/evolution_rabbitmq_data
      o: bind
  chatwoot_storage:
    driver: local
    driver_opts:
      type: none
      device: ${DATA_DIR}/chatwoot/chatwoot_storage
      o: bind
  chatwoot_postgres:
    driver: local
    driver_opts:
      type: none
      device: ${DATA_DIR}/chatwoot/postgres_data
      o: bind
EOF

show_message "Archivo docker-compose.yml creado en: ${COMPOSE_FILE}"

# 6) Ajustar configuración de Traefik si no se usa Let's Encrypt
if [ -z "$DOMAIN" ] || [ -z "$EMAIL" ]; then
  show_warning "Dominio o Email no proporcionados. Se ajustará Traefik para no usar Let\'s Encrypt y se usará un certificado auto-firmado."
  
  # Modificar traefik.yml para usar certificados auto-firmados
  cat > "${DATA_DIR}/traefik/traefik.yml" <<EOF
entryPoints:
  web:
    address: ":80"
  websecure:
    address: ":443"
providers:
  docker:
    exposedByDefault: false
    swarmMode: true
    network: frontend
log:
  level: INFO
api:
  dashboard: true
  insecure: false
tls:
  stores:
    default:
      defaultCertificate:
        certFile: /certs/self.crt
        keyFile: /certs/self.key
EOF

  # Crear certificado auto-firmado
  run_command "openssl req -x509 -nodes -days 3650 -newkey rsa:4096 -keyout ${DATA_DIR}/traefik/certs/self.key -out ${DATA_DIR}/traefik/certs/self.crt -subj \"/CN=localhost\"" "Generando certificado auto-firmado para Traefik..."
  
  # Ajustar docker-compose.yml para no usar certresolver y montar el certificado
  sed -i "s/traefik.http.routers.traefik.tls.certresolver=le/traefik.http.routers.traefik.tls=true/g" "${COMPOSE_FILE}"
  sed -i "s/traefik.http.routers.portainer.tls.certresolver=le/traefik.http.routers.portainer.tls=true/g" "${COMPOSE_FILE}"
  sed -i "s/traefik.http.routers.redisinsight.tls.certresolver=le/traefik.http.routers.redisinsight.tls=true/g" "${COMPOSE_FILE}"
  sed -i "s/traefik.http.routers.n8n_editor.tls.certresolver=le/traefik.http.routers.n8n_editor.tls=true/g" "${COMPOSE_FILE}"
  sed -i "s/traefik.http.routers.n8n_webhook.tls.certresolver=le/traefik.http.routers.n8n_webhook.tls=true/g" "${COMPOSE_FILE}"
  sed -i "s/traefik.http.routers.evolution-api.tls.certresolver=le/traefik.http.routers.evolution-api.tls=true/g" "${COMPOSE_FILE}"
  sed -i "s/traefik.http.routers.rabbitmq.tls.certresolver=le/traefik.http.routers.rabbitmq.tls=true/g" "${COMPOSE_FILE}"
  sed -i "s/traefik.http.routers.chatwoot.tls.certresolver=le/traefik.http.routers.chatwoot.tls=true/g" "${COMPOSE_FILE}"

  # Añadir volumen de certificados a Traefik
  sed -i "/      - traefik_letsencrypt:\/letsencrypt/a       - ${DATA_DIR}/traefik/certs:\/certs" "${COMPOSE_FILE}"

  # Eliminar líneas de email y httpchallenge de traefik.yml
  sed -i \'/      - "--certificatesresolvers.le.acme.email=${EMAIL}"/d' "${DATA_FILE}/traefik/traefik.yml"
  sed -i \'/      - "--certificatesresolvers.le.acme.httpchallenge=true"/d' "${DATA_FILE}/traefik/traefik.yml"
  sed -i \'/      - "--certificatesresolvers.le.acme.httpchallenge.entrypoint=web"/d' "${DATA_FILE}/traefik/traefik.yml"
  sed -i \'/      - "--certificatesresolvers.le.acme.storage=\/letsencrypt\/acme.json"/d' "${DATA_FILE}/traefik/traefik.yml"

else
  show_message "Configurando Traefik para usar Let\'s Encrypt con el email ${EMAIL}."
  # Crear un traefik.yml simple con configuración de Let's Encrypt
  cat > "${DATA_DIR}/traefik/traefik.yml" <<EOF
entryPoints:
  web:
    address: ":80"
  websecure:
    address: ":443"
providers:
  docker:
    exposedByDefault: false
    swarmMode: true
    network: frontend
log:
  level: INFO
api:
  dashboard: true
  insecure: false
certificatesResolvers:
  le:
    acme:
      email: ${EMAIL}
      storage: /letsencrypt/acme.json
      httpChallenge:
        entryPoint: web
EOF
fi

# Asegurar permisos para acme.json
run_command "touch ${DATA_DIR}/traefik/letsencrypt/acme.json && chmod 600 ${DATA_DIR}/traefik/letsencrypt/acme.json" "Ajustando permisos para acme.json..."

# 7) Desplegar stack Docker
show_message "Desplegando el stack Docker con todos los servicios..."
run_command "docker stack deploy -c \"${COMPOSE_FILE}\" queen-novedad" "Desplegando servicios Docker..."

show_message "Los contenedores se están levantando. Esto puede tardar unos minutos..."

# 8) Resumen final
cat <<EOF

=== Resumen de la Instalación ===
- Servicios desplegados: Traefik, Portainer, PostgreSQL (general y para n8n/evoapi/chatwoot), Redis, RedisInsight, n8n (editor, worker, webhook), EvoAPI, Chatwoot (rails, sidekiq, postgres)
- Redes Docker: frontend, backend (overlay)
- Directorio de datos base: ${DATA_DIR}
- Contraseña de Administrador (para servicios y Traefik Dashboard): ${ADMIN_PASSWORD}

Notas importantes:
- Si configuraste un dominio con Let\'s Encrypt, asegúrate de que el registro A de tu dominio (y los subdominios) apunte a la IP de este servidor y que los puertos 80 y 443 estén accesibles desde Internet.

URLs de acceso (si se configuró un dominio):
- Traefik Dashboard: https://${TRAEFIK_SUBDOMAIN}.${DOMAIN}
- Portainer: https://${PORTAINER_SUBDOMAIN}.${DOMAIN}
- RedisInsight: https://${REDISINSIGHT_SUBDOMAIN}.${DOMAIN}
- n8n Editor: https://${N8N_SUBDOMAIN}.${DOMAIN}
- n8n Webhook: https://${N8N_WEBHOOK_SUBDOMAIN}.${DOMAIN}
- EvoAPI: https://${EVOAPI_SUBDOMAIN}.${DOMAIN}
- Chatwoot: https://${CHATWOOT_SUBDOMAIN}.${DOMAIN}

URLs de acceso (si NO se configuró un dominio, usar IP del servidor):
- Traefik Dashboard: https://<IP_DEL_SERVIDOR>
- Portainer: https://<IP_DEL_SERVIDOR>:9000 (puede requerir mapeo de puertos manual o acceso directo si no hay Traefik)
- RedisInsight: https://<IP_DEL_SERVIDOR>:5540 (puede requerir mapeo de puertos manual o acceso directo si no hay Traefik)
- n8n Editor: https://<IP_DEL_SERVIDOR>:5678 (puede requerir mapeo de puertos manual o acceso directo si no hay Traefik)
- EvoAPI: https://<IP_DEL_SERVIDOR>:8080 (puede requerir mapeo de puertos manual o acceso directo si no hay Traefik)

Para ver logs de un servicio: docker service logs <nombre_del_servicio>
Para detener el stack: docker stack rm queen-novedad

=== Fin de la Instalación ===
EOF

show_success "Instalación finalizada. Revisa los logs si algún servicio tarda en levantarse."


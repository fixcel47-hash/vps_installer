#!/bin/bash

# ============================================
# Instalador Unificado de Herramientas Docker
# ============================================

# Colores
RED=\033[0;31m
GREEN=\033[0;32m
YELLOW=\033[0;33m
BLUE=\033[0;34m
NC=\033[0m # No Color

show_message() { echo -e "${BLUE}[INFO]${NC} $1"; }
show_error() { echo -e "${RED}[ERROR]${NC} $1"; }
show_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
show_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }

# Verificar permisos
if [ "$EUID" -ne 0 ]; then
    show_error "Por favor, ejecuta este script como root o con sudo."
    exit 1
fi

echo -e "\n${GREEN}===========================================${NC}"
echo -e "${GREEN}  🌸 Queen Novedad | Instalador Docker 🌸  ${NC}"
echo -e "${GREEN}===========================================${NC}\n"

show_message "Iniciando el instalador unificado..."




# Variables del instalador original
SCRIPT_VERSION="1.2.0"

# Lista de archivos temporales para limpiar
TEMP_FILES=()

declare -gA INSTALLED_COMPONENTS=(
    [dependencies]=false
    [security]=false
    [networks]=false
)

# Función de limpieza
cleanup() {
    local exit_code=$1
    local delete_stacks=${2:-false}  # Segundo parámetro opcional, por defecto false
    
    echo -e "${BLUE}[INFO]${NC} Realizando limpieza antes de salir..."
    
    # En caso de error, eliminar todos los archivos temporales y actualizar estado
    if [ $exit_code -ne 0 ]; then
        echo -e "${RED}[ERROR]${NC} Error detectado durante la instalación. Limpiando archivos temporales..."
        
        # Eliminar archivos temporales en caso de error
        if [ ${#TEMP_FILES[@]} -gt 0 ]; then
            for file in "${TEMP_FILES[@]}"; do
                if [ -f "$file" ]; then
                    rm -f "$file"
                fi
            done
        fi
    fi
    
    # Si se solicita, eliminar solo los archivos stack.yml (en caso de éxito)
    if [ "$delete_stacks" = true ]; then
        for tool_name in "${SELECTED_TOOLS[@]}"; do
            local stack_file="$DOCKER_DIR/$tool_name/$tool_name-stack.yml"
            if [ -f "$stack_file" ]; then
                rm -f "$stack_file"
            fi
        done
    fi
    
    # Crear un script de autodestrucción (tanto para error como para éxito)
    if [ $exit_code -ne 0 ] || [ "$delete_stacks" = true ]; then
        local self_destruct_script="/tmp/self_destruct_$$_$(date +%s).sh"
        cat > "$self_destruct_script" << EOF
#!/bin/bash
sleep 1
rm -f "$SCRIPT_PATH"
if [ -f "$SCRIPT_PATH" ]; then
  sudo rm -f "$SCRIPT_PATH"
fi
rm -f "\$0"
EOF

        chmod +x "$self_destruct_script"
        nohup "$self_destruct_script" >/dev/null 2>&1 &
    fi
    
    echo -e "${BLUE}[INFO]${NC} Limpieza completada"
    
    # Mostrar mensaje final de error si fue una limpieza por error
    if [ $exit_code -ne 0 ]; then
        echo -e "${RED}[ERROR]${NC} La instalación ha fallado. Revise los logs para más información."
    else
        echo -e "${GREEN}[SUCCESS]${NC} Instalación completada exitosamente"
    fi
}

# Configurar trampas para señales para limpiar antes de salir
trap 'cleanup 1 false; exit 1' SIGHUP SIGINT SIGQUIT SIGTERM
trap 'cleanup 1 false; exit 1' ERR

# Función para registrar un archivo temporal para limpieza posterior
register_temp_file() {
    local file_path=$1
    TEMP_FILES+=("$file_path")
    show_message "Registrado archivo temporal: $file_path"
}

# Función para recopilar información del sistema
collect_system_info() {
    HOSTNAME=$(hostname)
    OS_INFO=$(cat /etc/os-release | grep "PRETTY_NAME" | cut -d \" -f 2)
    CPU_INFO=$(grep "model name" /proc/cpuinfo | head -n 1 | cut -d : -f 2 | sed 's/^ //')
    MEM_TOTAL=$(free -h | grep "Mem:" | awk '{print $2}')
    # IP_ADDRESS=$(curl -s https://api.ipify.org)
}

# Función para registrar el inicio de la instalación (neutralizada)
register_installation_start() {
    show_message "Registrando instalación (funcionalidad API neutralizada)..."
    collect_system_info
    INSTALLATION_ID="mock_installation_id"
    return 0
}

# Función para actualizar el estado de la instalación (neutralizada)
update_installation_status() {
    return 0
}

# Función para completar la instalación (neutralizada)
complete_installation() {
    return 0
}

# Función para animación de espera
spinner() {
    local pid=$1
    local delay=0.1
    local spinstr=\'|/-\\\'
    
    echo -n "Procesando "
    while [ "$(ps a | awk \'{print $1}\' | grep $pid)" ]; do
        local temp=${spinstr#?}
        printf " [%c]  " "$spinstr"
        local spinstr=$temp${spinstr%\"$temp\"}
        sleep $delay
        printf "\b\b\b\b\b\b"
    done
    printf "    \b\b\b\b"
    echo -e "${GREEN}[COMPLETADO]${NC}"
}

# Función para ejecutar comandos mostrando animación de espera
run_command() {
    local cmd=$1
    local msg=$2
    
    show_message "$msg"
    eval "$cmd" > /dev/null 2>&1 &
    local cmd_pid=$!
    spinner $cmd_pid
    wait $cmd_pid
    local exit_status=$?
    
    if [ $exit_status -ne 0 ]; then
        show_error "Comando falló: $cmd"
        cleanup 1
        exit $exit_status
    fi
    
    return $exit_status
}

# Función para generar clave aleatoria de 32 caracteres
generate_random_key() {
    tr -dc \'A-Za-z0-9\' </dev/urandom | head -c 32
}

# Función para configurar tamaño de los logs de Docker
configure_docker_logs() {
    local config_file="/etc/docker/daemon.json"

    show_message "Configurando límites de logs en Docker..."

    cat > "$config_file" <<EOF
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  }
}
EOF

    run_command "systemctl restart docker" "Reiniciando Docker para aplicar configuración..."
}

# Función para configurar rkhunter
configure_rkhunter() {
    local config_file="/etc/rkhunter.conf"

    show_message "Configurando RKHunter..."

    run_command "sed -i \'s/^UPDATE_MIRRORS=.*/UPDATE_MIRRORS=1/\' \"$config_file\" && \
                sed -i \'s/^MIRRORS_MODE=.*/MIRRORS_MODE=0/\' \"$config_file\" && \
                sed -i \'s|^WEB_CMD=.*|WEB_CMD=\\\"\\\"|\' \"$config_file\"" \
                "Aplicando configuración de RKHunter..."
}

# Función para descargar archivos desde la API (neutralizada)
download_from_api() {
    local repo_path=$1
    local local_path=$2
    show_message "Simulando descarga de $repo_path (funcionalidad API neutralizada)..."
    touch "$local_path"
    register_temp_file "$local_path"
    return 0
}

# Función para validar el token (neutralizada)
validate_token() {
    return 0
}




# Función para escribir el archivo chatwoot-stack.yml
write_chatwoot_stack_yml() {
    local subdomain=$1
    local domain=$2
    local password=$3
    local secret_key=$4

    mkdir -p "$DOCKER_DIR/chatwoot"
    cat << EOF > "$DOCKER_DIR/chatwoot/chatwoot-stack.yml"
version: '3.8'

services:
  rails:
    image: chatwoot/chatwoot:latest
    environment:
      # Configuración Base
      - NODE_ENV=production
      - RAILS_ENV=production
      - INSTALLATION_ENV=docker
      - SECRET_KEY_BASE=$secret_key
      - FRONTEND_URL=https://$subdomain.$domain
      - WEBSOCKET_URL=wss://$subdomain.$domain/cable
      - FORCE_SSL=true
      
      # Autenticación y Registro
      - ENABLE_ACCOUNT_SIGNUP=false
      - DEFAULT_LOCALE=
      - HELPCENTER_URL=
      
      # Redis
      - REDIS_URL=redis://redis-server:6379/4
      - REDIS_PASSWORD=
      - REDIS_SENTINELS=
      - REDIS_SENTINEL_MASTER_NAME=
      - REDIS_SENTINEL_PASSWORD=
      - REDIS_OPENSSL_VERIFY_MODE=
      
      # PostgreSQL
      - POSTGRES_DATABASE=chatwoot
      - POSTGRES_HOST=chatwoot-postgres
      - POSTGRES_USERNAME=postgres
      - POSTGRES_PASSWORD=$password
      - POSTGRES_STATEMENT_TIMEOUT=14s
      - RAILS_MAX_THREADS=5
      
      # Email/SMTP
      - MAILER_SENDER_EMAIL=Chatwoot <correo@corporativo>
      - SMTP_DOMAIN=dominio-del-servidor-smtp
      - SMTP_ADDRESS=mail.dominio.com
      - SMTP_PORT=587
      - SMTP_USERNAME=email-del-smtp
      - SMTP_PASSWORD=$password
      - SMTP_AUTHENTICATION=plain
      - SMTP_ENABLE_STARTTLS_AUTO=true
      - SMTP_OPENSSL_VERIFY_MODE=peer
      - SMTP_TLS=
      - SMTP_SSL=
      
      # Almacenamiento
      - ACTIVE_STORAGE_SERVICE=local
      - S3_BUCKET_NAME=
      - AWS_ACCESS_KEY_ID=
      - AWS_SECRET_ACCESS_KEY=
      - AWS_REGION=
      
      - S3_ACCESS_KEY=key-de-minio
      - S3_SECRET_KEY=secret-de-minio
      - S3_BUCKET=chatwoot
      - S3_ENDPOINT=subdominioapi.minio.com #subdominio de la api de minio
      
      - DIRECT_UPLOADS_ENABLED=
      
      # Logs
      - RAILS_LOG_TO_STDOUT=true
      - LOG_LEVEL=info
      - LOG_SIZE=500
      - LOGRAGE_ENABLED=
      
      # Integraciones
      - FB_VERIFY_TOKEN=
      - FB_APP_SECRET=
      - FB_APP_ID=
      - IG_VERIFY_TOKEN=
      - TWITTER_APP_ID=
      - TWITTER_CONSUMER_KEY=
      - TWITTER_CONSUMER_SECRET=
      - TWITTER_ENVIRONMENT=
      - SLACK_CLIENT_ID=
      - SLACK_CLIENT_SECRET=
      - GOOGLE_OAUTH_CLIENT_ID=
      - GOOGLE_OAUTH_CLIENT_SECRET=
      - GOOGLE_OAUTH_CALLBACK_URL=
      - AZURE_APP_ID=
      - AZURE_APP_SECRET=
      
      # Mobile
      - IOS_APP_ID=L7YLMN4634.com.chatwoot.app
      - ANDROID_BUNDLE_ID=com.chatwoot.app
      - ANDROID_SHA256_CERT_FINGERPRINT=AC:73:8E:DE:EB:56:EA:CC:10:87:02:A7:65:37:7B:38:D4:5D:D4:53:F8:3B:FB:D3:C6:28:64:1D:AA:08:1E:D8
      - VAPID_PUBLIC_KEY=
      - VAPID_PRIVATE_KEY=
      - FCM_SERVER_KEY=
      
      # Seguridad
      - ENABLE_RACK_ATTACK=true
      - RACK_ATTACK_LIMIT=300
      - ENABLE_RACK_ATTACK_WIDGET_API=true
      
      # Monitoreo
      - SENTRY_DSN=
      - ELASTIC_APM_SERVER_URL=
      - ELASTIC_APM_SECRET_TOKEN=
      - SCOUT_KEY=
      - SCOUT_NAME=
      - SCOUT_MONITOR=
      - NEW_RELIC_LICENSE_KEY=
      - NEW_RELIC_APPLICATION_LOGGING_ENABLED=
      - DD_TRACE_AGENT_URL=
      
      # IA y características avanzadas
      - OPENAI_API_KEY=
      - REMOVE_STALE_CONTACT_INBOX_JOB_STATUS=false
      - IP_LOOKUP_API_KEY=
      - STRIPE_SECRET_KEY=
      - STRIPE_WEBHOOK_SECRET=
      
      # Webhooks Email
      - RAILS_INBOUND_EMAIL_SERVICE=
      - RAILS_INBOUND_EMAIL_PASSWORD=
      - MAILGUN_INGRESS_SIGNING_KEY=
      - MANDRILL_INGRESS_API_KEY=
      - MAILER_INBOUND_EMAIL_DOMAIN=correo-para recibir respuestas
      
      # Otros
      - ASSET_CDN_HOST=
      - CW_API_ONLY_SERVER=
      - ENABLE_PUSH_RELAY_SERVER=true
      - SIDEKIQ_CONCURRENCY=10
      
    volumes:
      - chatwoot_storage:/app/storage
      
    entrypoint: docker/entrypoints/rails.sh
    command: ["bundle", "exec", "rails", "s", "-p", "3000", "-b", "0.0.0.0"]
    
    deploy:
      replicas: 1
      restart_policy:
        condition: on-failure
        
      labels:
        - "traefik.enable=true"
        - "traefik.http.routers.chatwoot.rule=Host(`$subdomain.$domain`)"
        - "traefik.http.routers.chatwoot.entrypoints=websecure"
        - "traefik.http.routers.chatwoot.tls=true"
        - "traefik.http.routers.chatwoot.tls.certresolver=le"
        - "traefik.http.services.chatwoot.loadbalancer.server.port=3000"
        - "traefik.http.middlewares.sslheader.headers.customrequestheaders.X-Forwarded-Proto=https"
        - "traefik.http.routers.chatwoot.middlewares=sslheader"

    networks:
      - frontend
      - backend

  sidekiq:
    image: chatwoot/chatwoot:latest
    environment:
      # Configuración Base
      - NODE_ENV=production
      - RAILS_ENV=production
      - INSTALLATION_ENV=docker
      - SECRET_KEY_BASE=$secret_key
      - FRONTEND_URL=https://$subdomain.$domain
      - WEBSOCKET_URL=wss://$subdomain.$domain/cable
      - FORCE_SSL=true
      
      # Autenticación y Registro
      - ENABLE_ACCOUNT_SIGNUP=false
      - DEFAULT_LOCALE=
      - HELPCENTER_URL=
      
      # Redis
      - REDIS_URL=redis://redis-server:6379/4
      - REDIS_PASSWORD=
      - REDIS_SENTINELS=
      - REDIS_SENTINEL_MASTER_NAME=
      - REDIS_SENTINEL_PASSWORD=
      - REDIS_OPENSSL_VERIFY_MODE=
      
      # PostgreSQL
      - POSTGRES_DATABASE=chatwoot
      - POSTGRES_HOST=chatwoot-postgres
      - POSTGRES_USERNAME=postgres
      - POSTGRES_PASSWORD=$password
      - POSTGRES_STATEMENT_TIMEOUT=14s
      - RAILS_MAX_THREADS=5
      
      # Email/SMTP
      - MAILER_SENDER_EMAIL=Chatwoot <correo@corporativo>
      - SMTP_DOMAIN=dominio-del-servidor-smtp
      - SMTP_ADDRESS=mail.dominio.com
      - SMTP_PORT=587
      - SMTP_USERNAME=email-del-smtp
      - SMTP_PASSWORD=$password
      - SMTP_AUTHENTICATION=plain
      - SMTP_ENABLE_STARTTLS_AUTO=true
      - SMTP_OPENSSL_VERIFY_MODE=peer
      - SMTP_TLS=
      - SMTP_SSL=
      
      # Almacenamiento
      - ACTIVE_STORAGE_SERVICE=local
      - S3_BUCKET_NAME=
      - AWS_ACCESS_KEY_ID=
      - AWS_SECRET_ACCESS_KEY=
      - AWS_REGION=
      
      - S3_ACCESS_KEY=key-de-minio
      - S3_SECRET_KEY=secret-de-minio
      - S3_BUCKET=chatwoot
      - S3_ENDPOINT=subdominioapi.minio.com #subdominio de la api de minio
      
      - DIRECT_UPLOADS_ENABLED=
      
      # Logs
      - RAILS_LOG_TO_STDOUT=true
      - LOG_LEVEL=info
      - LOG_SIZE=500
      - LOGRAGE_ENABLED=
      
      # Integraciones
      - FB_VERIFY_TOKEN=
      - FB_APP_SECRET=
      - FB_APP_ID=
      - IG_VERIFY_TOKEN=
      - TWITTER_APP_ID=
      - TWITTER_CONSUMER_KEY=
      - TWITTER_CONSUMER_SECRET=
      - TWITTER_ENVIRONMENT=
      - SLACK_CLIENT_ID=
      - SLACK_CLIENT_SECRET=
      - GOOGLE_OAUTH_CLIENT_ID=
      - GOOGLE_OAUTH_CLIENT_SECRET=
      - GOOGLE_OAUTH_CALLBACK_URL=
      - AZURE_APP_ID=
      - AZURE_APP_SECRET=
      
      # Mobile
      - IOS_APP_ID=L7YLMN4634.com.chatwoot.app
      - ANDROID_BUNDLE_ID=com.chatwoot.app
      - ANDROID_SHA256_CERT_FINGERPRINT=AC:73:8E:DE:EB:56:EA:CC:10:87:02:A7:65:37:7B:38:D4:5D:D4:53:F8:3B:FB:D3:C6:28:64:1D:AA:08:1E:D8
      - VAPID_PUBLIC_KEY=
      - VAPID_PRIVATE_KEY=
      - FCM_SERVER_KEY=
      
      # Seguridad
      - ENABLE_RACK_ATTACK=true
      - RACK_ATTACK_LIMIT=300
      - ENABLE_RACK_ATTACK_WIDGET_API=true
      
      # Monitoreo
      - SENTRY_DSN=
      - ELASTIC_APM_SERVER_URL=
      - ELASTIC_APM_SECRET_TOKEN=
      - SCOUT_KEY=
      - SCOUT_NAME=
      - SCOUT_MONITOR=
      - NEW_RELIC_LICENSE_KEY=
      - NEW_RELIC_APPLICATION_LOGGING_ENABLED=
      - DD_TRACE_AGENT_URL=
      
      # IA y características avanzadas
      - OPENAI_API_KEY=
      - REMOVE_STALE_CONTACT_INBOX_JOB_STATUS=false
      - IP_LOOKUP_API_KEY=
      - STRIPE_SECRET_KEY=
      - STRIPE_WEBHOOK_SECRET=
      
      # Webhooks Email
      - RAILS_INBOUND_EMAIL_SERVICE=
      - RAILS_INBOUND_EMAIL_PASSWORD=
      - MAILGUN_INGRESS_SIGNING_KEY=
      - MANDRILL_INGRESS_API_KEY=
      - MAILER_INBOUND_EMAIL_DOMAIN=correo-para recibir respuestas
      
      # Otros
      - ASSET_CDN_HOST=
      - CW_API_ONLY_SERVER=
      - ENABLE_PUSH_RELAY_SERVER=true
      - SIDEKIQ_CONCURRENCY=10
    
    volumes:
      - chatwoot_storage:/app/storage
      
    command: ["bundle", "exec", "sidekiq", "-C", "config/sidekiq.yml"]
    
    deploy:
      replicas: 1
      restart_policy:
        condition: on-failure

    networks:
      - frontend
      - backend

  chatwoot-postgres:
    image: pgvector/pgvector:pg16
    environment:
      - POSTGRES_DB=chatwoot
      - POSTGRES_USER=postgres
      - POSTGRES_PASSWORD=$password
      
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
  chatwoot_storage:
    driver: local
    driver_opts:
      type: none
      device: /home/docker/chatwoot/chatwoot_storage
      o: bind
  chatwoot_postgres:
    driver: local
    driver_opts:
      type: none
      device: /home/docker/chatwoot/postgres_data
      o: bind
EOF
}



# Función para escribir el archivo evoapi-stack.yml
write_evoapi_stack_yml() {
    local subdomain=$1
    local domain=$2
    local password=$3
    local secret_key=$4

    mkdir -p "$DOCKER_DIR/evoapi"
    cat << EOF > "$DOCKER_DIR/evoapi/evoapi-stack.yml"
version: '3'

services:
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
        - "traefik.http.routers.evolution-api.rule=Host(`$subdomain.$domain`)"
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
      # Evolution API Configuration
      - SUBDOMAIN=$subdomain
      - DOMAIN=$domain
      - PASSWORD=$password
      - SECRET_KEY=$secret_key
      - SERVER_TYPE=http
      - SERVER_PORT=8080
      - SERVER_URL=https://$subdomain.$domain
      - SENTRY_DSN=
      # Cors Configuration
      - CORS_ORIGIN=*
      - CORS_METHODS=GET,POST,PUT,DELETE
      - CORS_CREDENTIALS=true
      # Logging Configuration
      - LOG_LEVEL=ERROR,WARN,DEBUG,INFO,LOG,VERBOSE,DARK,WEBHOOKS,WEBSOCKET
      - LOG_COLOR=true
      - LOG_BAILEYS=error
      - EVENT_EMITTER_MAX_LISTENERS=50
      - DEL_INSTANCE=false
      # Database Configuration
      - DATABASE_PROVIDER=postgresql
      - DATABASE_CONNECTION_URI=postgresql://postgres:$password@postgres-evoapi:5432/evolution2?schema=public
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
      # RabbitMQ Configuration
      - RABBITMQ_ENABLED=true
      - RABBITMQ_URI=amqp://evo-rabbit:$password@rabbitmq:5672/default
      - RABBITMQ_EXCHANGE_NAME=evolution
      - RABBITMQ_ERLANG_COOKIE=$password
      - RABBITMQ_DEFAULT_VHOST=default
      - RABBITMQ_DEFAULT_USER=evo-rabbit
      - RABBITMQ_DEFAULT_PASS=$password
      - RABBITMQ_GLOBAL_ENABLED=false
      - RABBITMQ_EVENTS_APPLICATION_STARTUP=false
      - RABBITMQ_EVENTS_INSTANCE_CREATE=false
      - RABBITMQ_EVENTS_INSTANCE_DELETE=false
      - RABBITMQ_EVENTS_QRCODE_UPDATED=false
      - RABBITMQ_EVENTS_MESSAGES_SET=false
      - RABBITMQ_EVENTS_MESSAGES_UPSERT=false
      - RABBITMQ_EVENTS_MESSAGES_EDITED=false
      - RABBITMQ_EVENTS_MESSAGES_UPDATE=false
      - RABBITMQ_EVENTS_MESSAGES_DELETE=false
      - RABBITMQ_EVENTS_SEND_MESSAGE=false
      - RABBITMQ_EVENTS_CONTACTS_SET=false
      - RABBITMQ_EVENTS_CONTACTS_UPSERT=false
      - RABBITMQ_EVENTS_CONTACTS_UPDATE=false
      - RABBITMQ_EVENTS_PRESENCE_UPDATE=false
      - RABBITMQ_EVENTS_CHATS_SET=false
      - RABBITMQ_EVENTS_CHATS_UPSERT=false
      - RABBITMQ_EVENTS_CHATS_UPDATE=false
      - RABBITMQ_EVENTS_CHATS_DELETE=false
      - RABBITMQ_EVENTS_GROUPS_UPSERT=false
      - RABBITMQ_EVENTS_GROUP_UPDATE=false
      - RABBITMQ_EVENTS_GROUP_PARTICIPANTS_UPDATE=false
      - RABBITMQ_EVENTS_CONNECTION_UPDATE=false
      - RABBITMQ_EVENTS_REMOVE_INSTANCE=false
      - RABBITMQ_EVENTS_LOGOUT_INSTANCE=false
      - RABBITMQ_EVENTS_CALL=false
      - RABBITMQ_EVENTS_TYPEBOT_START=false
      - RABBITMQ_EVENTS_TYPEBOT_CHANGE_STATUS=false
      # SQS Configuration
      - SQS_ENABLED=false
      - SQS_ACCESS_KEY_ID=
      - SQS_SECRET_ACCESS_KEY=
      - SQS_ACCOUNT_ID=
      - SQS_REGION=
      # Websocket Configuration
      - WEBSOCKET_ENABLED=false
      - WEBSOCKET_GLOBAL_EVENTS=false
      # Pusher Configuration
      - PUSHER_ENABLED=false
      - PUSHER_GLOBAL_ENABLED=false
      - PUSHER_GLOBAL_APP_ID=
      - PUSHER_GLOBAL_KEY=
      - PUSHER_GLOBAL_SECRET=
      - PUSHER_GLOBAL_CLUSTER=
      - PUSHER_GLOBAL_USE_TLS=true
      - PUSHER_EVENTS_APPLICATION_STARTUP=true
      - PUSHER_EVENTS_QRCODE_UPDATED=true
      - PUSHER_EVENTS_MESSAGES_SET=true
      - PUSHER_EVENTS_MESSAGES_UPSERT=true
      - PUSHER_EVENTS_MESSAGES_EDITED=true
      - PUSHER_EVENTS_MESSAGES_UPDATE=true
      - PUSHER_EVENTS_MESSAGES_DELETE=true
      - PUSHER_EVENTS_SEND_MESSAGE=true
      - PUSHER_EVENTS_CONTACTS_SET=true
      - PUSHER_EVENTS_CONTACTS_UPSERT=true
      - PUSHER_EVENTS_CONTACTS_UPDATE=true
      - PUSHER_EVENTS_PRESENCE_UPDATE=true
      - PUSHER_EVENTS_CHATS_SET=true
      - PUSHER_EVENTS_CHATS_UPSERT=true
      - PUSHER_EVENTS_CHATS_UPDATE=true
      - PUSHER_EVENTS_CHATS_DELETE=true
      - PUSHER_EVENTS_GROUPS_UPSERT=true
      - PUSHER_EVENTS_GROUPS_UPDATE=true
      - PUSHER_EVENTS_GROUP_PARTICIPANTS_UPDATE=true
      - PUSHER_EVENTS_CONNECTION_UPDATE=true
      - PUSHER_EVENTS_LABELS_EDIT=true
      - PUSHER_EVENTS_LABELS_ASSOCIATION=true
      - PUSHER_EVENTS_CALL=true
      - PUSHER_EVENTS_TYPEBOT_START=false
      - PUSHER_EVENTS_TYPEBOT_CHANGE_STATUS=false
      # WhatsApp Business API Configuration
      - WA_BUSINESS_TOKEN_WEBHOOK=evolution
      - WA_BUSINESS_URL=https://graph.facebook.com
      - WA_BUSINESS_VERSION=v20.0
      - WA_BUSINESS_LANGUAGE=en_US
      # Webhook Configuration
      - WEBHOOK_GLOBAL_ENABLED=false
      - WEBHOOK_GLOBAL_URL=''
      - WEBHOOK_GLOBAL_WEBHOOK_BY_EVENTS=false
      - WEBHOOK_EVENTS_APPLICATION_STARTUP=false
      - WEBHOOK_EVENTS_QRCODE_UPDATED=true
      - WEBHOOK_EVENTS_MESSAGES_SET=true
      - WEBHOOK_EVENTS_MESSAGES_UPSERT=true
      - WEBHOOK_EVENTS_MESSAGES_EDITED=true
      - WEBHOOK_EVENTS_MESSAGES_UPDATE=true
      - WEBHOOK_EVENTS_MESSAGES_DELETE=true
      - WEBHOOK_EVENTS_SEND_MESSAGE=true
      - WEBHOOK_EVENTS_CONTACTS_SET=true
      - WEBHOOK_EVENTS_CONTACTS_UPSERT=true
      - WEBHOOK_EVENTS_CONTACTS_UPDATE=true
      - WEBHOOK_EVENTS_PRESENCE_UPDATE=true
      - WEBHOOK_EVENTS_CHATS_SET=true
      - WEBHOOK_EVENTS_CHATS_UPSERT=true
      - WEBHOOK_EVENTS_CHATS_UPDATE=true
      - WEBHOOK_EVENTS_CHATS_DELETE=true
      - WEBHOOK_EVENTS_GROUPS_UPSERT=false
      - WEBHOOK_EVENTS_GROUPS_UPDATE=false
      - WEBHOOK_EVENTS_GROUP_PARTICIPANTS_UPDATE=false
      - WEBHOOK_EVENTS_CONNECTION_UPDATE=false
      - WEBHOOK_EVENTS_REMOVE_INSTANCE=false
      - WEBHOOK_EVENTS_LOGOUT_INSTANCE=false
      - WEBHOOK_EVENTS_LABELS_EDIT=true
      - WEBHOOK_EVENTS_LABELS_ASSOCIATION=true
      - WEBHOOK_EVENTS_CALL=true
      - WEBHOOK_EVENTS_TYPEBOT_START=false
      - WEBHOOK_EVENTS_TYPEBOT_CHANGE_STATUS=false
      - WEBHOOK_EVENTS_ERRORS=false
      - WEBHOOK_EVENTS_ERRORS_WEBHOOK=
      # Session Configuration
      - CONFIG_SESSION_PHONE_CLIENT=Evolution API
      - CONFIG_SESSION_PHONE_NAME=Chrome
      - CONFIG_SESSION_PHONE_VERSION=2.3000.1023204200
      # QR Code Configuration
      - QRCODE_LIMIT=30
      - QRCODE_COLOR='#175197'
      # Typebot Configuration
      - TYPEBOT_ENABLED=true
      - TYPEBOT_API_VERSION=latest
      # Chatwoot Configuration
      - CHATWOOT_ENABLED=true
      - CHATWOOT_MESSAGE_READ=true
      - CHATWOOT_MESSAGE_DELETE=true
      - CHATWOOT_BOT_CONTACT=true
      - CHATWOOT_IMPORT_DATABASE_CONNECTION_URI='postgresql://postgres:$password@chatwoot-postgres:5432/chatwoot?sslmode=disable'
      - CHATWOOT_IMPORT_PLACEHOLDER_MEDIA_MESSAGE=true
      # OpenAI Configuration
      - OPENAI_ENABLED=false
      # Dify Configuration
      - DIFY_ENABLED=false
      # Cache Configuration
      - CACHE_REDIS_ENABLED=true
      - CACHE_REDIS_URI=redis://redis-server:6379/3
      - CACHE_REDIS_TTL=604800
      - CACHE_REDIS_PREFIX_KEY=evolution
      - CACHE_REDIS_SAVE_INSTANCES=false
      - CACHE_LOCAL_ENABLED=false
      # S3 Configuration
      - S3_ENABLED=false
      - S3_ACCESS_KEY=
      - S3_SECRET_KEY=
      - S3_BUCKET=evolution
      - S3_PORT=443
      - S3_ENDPOINT=s3.domain.com
      - S3_REGION=eu-west-3
      - S3_USE_SSL=true
      # Authentication
      - AUTHENTICATION_API_KEY=$secret_key
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
      - POSTGRES_PASSWORD=$password
      
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
        - "traefik.http.routers.rabbitmq.rule=Host(`rabbitmq-$subdomain.$domain`)"
        - "traefik.http.routers.rabbitmq.entrypoints=websecure"
        - "traefik.http.routers.rabbitmq.tls=true"
        - "traefik.http.routers.rabbitmq.tls.certresolver=le"
        - "traefik.http.services.rabbitmq.loadbalancer.server.port=15672"
        - "traefik.docker.network=frontend"
        
    volumes:
      - evolution_rabbitmq_data:/var/lib/rabbitmq/
      
    environment:
      - RABBITMQ_ERLANG_COOKIE=$password
      - RABBITMQ_DEFAULT_VHOST=default
      - RABBITMQ_DEFAULT_USER=evo-rabbit
      - RABBITMQ_DEFAULT_PASS=$password
      
    networks:
      - frontend
      - backend

networks:
  frontend:
    external: true
  backend:
    external: true

volumes:
  evolution_instances:
    driver: local
    driver_opts:
      type: none
      device: /home/docker/evoapi/evolution_instances
      o: bind
  
  evolution_postgres_data:
    driver: local
    driver_opts:
      type: none
      device: /home/docker/evoapi/evolution_postgres_data
      o: bind
  
  evolution_rabbitmq_data:
    driver: local
    driver_opts:
      type: none
      device: /home/docker/evoapi/rabbitmq_data
      o: bind
EOF
}



# Función para escribir el archivo n8n-stack.yml
write_n8n_stack_yml() {
    local subdomain=$1
    local domain=$2
    local password=$3
    local secret_key=$4

    mkdir -p "$DOCKER_DIR/n8n"
    cat << EOF > "$DOCKER_DIR/n8n/n8n-stack.yml"
version: '3.8'

services:
  'n8n-db':
    image: postgres:16
    restart: always
    user: root

    environment:

      - POSTGRES_USER=postgres
      - POSTGRES_DB=n8n
      - POSTGRES_PASSWORD=$password

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
    #command: editor
    environment:
      - N8N_ENCRYPTION_KEY=$secret_key
      - DB_TYPE=postgresdb
      - DB_POSTGRESDB_HOST=n8n-db
      - DB_POSTGRESDB_PORT=5432
      - DB_POSTGRESDB_DATABASE=n8n
      - DB_POSTGRESDB_USER=postgres
      - DB_POSTGRESDB_PASSWORD=$password
      - N8N_PROTOCOL=https
      - N8N_HOST=$subdomain.$domain
      - N8N_EDITOR_BASE_URL=https://$subdomain.$domain
      - WEBHOOK_URL=https://webhook.$subdomain.$domain
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
        - traefik.http.routers.n8n_editor.rule=Host(`$subdomain.$domain`)
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
      - N8N_ENCRYPTION_KEY=$secret_key
      - DB_TYPE=postgresdb
      - DB_POSTGRESDB_HOST=n8n-db
      - DB_POSTGRESDB_PORT=5432
      - DB_POSTGRESDB_DATABASE=n8n
      - DB_POSTGRESDB_USER=postgres
      - DB_POSTGRESDB_PASSWORD=$password
      - N8N_PROTOCOL=https
      - N8N_HOST=$subdomain.$domain
      - N8N_EDITOR_BASE_URL=https://$subdomain.$domain
      - WEBHOOK_URL=https://webhook.$subdomain.$domain
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
      - N8N_ENCRYPTION_KEY=$secret_key
      - DB_TYPE=postgresdb
      - DB_POSTGRESDB_HOST=n8n-db
      - DB_POSTGRESDB_PORT=5432
      - DB_POSTGRESDB_DATABASE=n8n
      - DB_POSTGRESDB_USER=postgres
      - DB_POSTGRESDB_PASSWORD=$password
      - N8N_PROTOCOL=https
      - N8N_HOST=$subdomain.$domain
      - N8N_EDITOR_BASE_URL=https://$subdomain.$domain
      - WEBHOOK_URL=https://webhook.$subdomain.$domain
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
        - traefik.http.routers.n8n_webhook.rule=Host(`webhook.$subdomain.$domain`)
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
      
networks:
    frontend:
      external: true
    backend:
      external: true

volumes:
  n8n_db:
    driver: local
    driver_opts:
      type: none
      device: /home/docker/n8n/db
      o: bind

  n8n_data:
    driver: local
    driver_opts:
      type: none
      device: /home/docker/n8n/data
      o: bind

  n8n_local-files:
    driver: local
    driver_opts:
      type: none
      device: /home/docker/n8n/local-files
      o: bind
EOF
}



# Función para escribir el archivo portainer-stack.yml
write_portainer_stack_yml() {
    local subdomain=$1
    local domain=$2

    mkdir -p "$DOCKER_DIR/portainer"
    cat << EOF > "$DOCKER_DIR/portainer/portainer-stack.yml"
version: "3.7"
services:

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
        - "traefik.http.routers.portainer.rule=Host(`$subdomain.$domain`)" 
        - "traefik.http.services.portainer.loadbalancer.server.port=9000"
        - "traefik.http.routers.portainer.tls.certresolver=le"
        - "traefik.http.routers.portainer.service=portainer"
        - "traefik.docker.network=frontend"
        - "traefik.http.routers.portainer.entrypoints=websecure"
        - "traefik.http.routers.portainer.priority=1"

networks:
  frontend:
    external: true

volumes: 
  portainer_data:
    driver: local
    driver_opts:
      type: none
      device: /home/docker/portainer/portainer_data
      o: bind
EOF
}



# Función para escribir el archivo postgres-stack.yml
write_postgres_stack_yml() {
    local password=$1

    mkdir -p "$DOCKER_DIR/postgres"
    cat << EOF > "$DOCKER_DIR/postgres/postgres-stack.yml"
version: '3.8'

services:
  postgres-server:
    image: postgres:latest

    environment:
    
      POSTGRES_USER: postgres
      POSTGRES_PASSWORD: $password
      POSTGRES_DB: default_db

    deploy:
      mode: replicated
      replicas: 1
      
    volumes:
      - postgres_data:/var/lib/postgresql/data
      
    networks:
      - backend
      
    restart: unless-stopped
    
networks:
  backend:
    external: true

volumes:
  postgres_data:
    driver: local
    driver_opts:
      type: none
      device: /home/docker/postgres/postgres_data
      o: bind
EOF
}



# Función para escribir el archivo redis-stack.yml
write_redis_stack_yml() {
    local subdomain=$1
    local domain=$2

    mkdir -p "$DOCKER_DIR/redis"
    cat << EOF > "$DOCKER_DIR/redis/redis-stack.yml"
version: '3.7'

services:
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
       - "traefik.http.routers.redisinsight.rule=Host(`$subdomain.$domain`)"
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

networks:
  backend:
    external: true
  frontend:
    external: true

volumes:
  redis_cache:
    driver: local
    driver_opts:
      type: none
      device: /home/docker/redis/redis_cache
      o: bind
      
  redisinsight:
    driver: local
    driver_opts:
      type: none
      device: /home/docker/redis/redisinsight
      o: bind
EOF
}



# Función para escribir el archivo traefik-stack.yml
write_traefik_stack_yml() {
    local domain=$1
    local email=$2
    local enable_le=$3

    mkdir -p "$DOCKER_DIR/traefik"
    cat << EOF > "$DOCKER_DIR/traefik/traefik-stack.yml"
version: '3.8'

services:
  traefik:
    image: traefik:latest
    command:
      - --api.dashboard=true
      - --providers.docker=true
      - --providers.docker.exposedbydefault=false
      - --entrypoints.web.address=:80
      - --entrypoints.websecure.address=:443
      - --log.level=INFO
      - --accesslog=true
      # Redireccionar HTTP a HTTPS
      - --entrypoints.web.http.redirections.entrypoint.to=websecure
      - --entrypoints.web.http.redirections.entrypoint.schem=https

$(if [ "$enable_le" = true ]; then)
      # Configuración de Let's Encrypt
      - --certificatesresolvers.le.acme.email=$email
      - --certificatesresolvers.le.acme.storage=/etc/traefik/acme.json
      - --certificatesresolvers.le.acme.tlschallenge=true
      # - --certificatesresolvers.le.acme.caserver=https://acme-staging-v02.api.letsencrypt.org/directory # Descomentar para pruebas
$(fi)

    ports:
      - "80:80"
      - "443:443"
      # - "8080:8080" # Dashboard de Traefik, descomentar para acceder
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
      - traefik_data:/etc/traefik
    networks:
      - frontend
    deploy:
      mode: replicated
      replicas: 1
      placement:
        constraints:
          - node.role == manager
      labels:
        - "traefik.enable=true"
        - "traefik.http.routers.api.rule=Host(`traefik.$domain`)"
        - "traefik.http.routers.api.service=api@internal"
        - "traefik.http.routers.api.middlewares=auth"
        - "traefik.http.routers.api.entrypoints=websecure"
        - "traefik.http.routers.api.tls.certresolver=le"
        - "traefik.http.routers.api.tls=true"
        - "traefik.http.middlewares.auth.basicauth.users=admin:$$(htpasswd -nbB 0 admin REPLACE_PASSWORD | sed -e s/\$/\$\$/g)"

networks:
  frontend:
    external: true

volumes:
  traefik_data:
    driver: local
    driver_opts:
      type: none
      device: /home/docker/traefik/traefik_data
      o: bind
EOF
}



# Variables del instalador original (continuación)
SCRIPT_PATH=$(readlink -f "$0")

# Variables API (neutralizadas)
# API_URL=""
# API_TOKEN=""
INSTALLATION_ID=""

# Función para esperar a que un servicio esté disponible
wait_for_service() {
    local service_url=$1
    local timeout=${2:-300}  # timeout por defecto de 5 minutos
    
    show_message "Esperando a que $service_url esté disponible..."
    
    local counter=0
    while [ $counter -lt $timeout ]; do
        if curl -k -s --connect-timeout 5 "$service_url" >/dev/null 2>&1; then
            show_success "Servicio $service_url está disponible"
            return 0
        fi
        
        sleep 5
        counter=$((counter + 5))
        
        # Mostrar progreso cada 30 segundos
        if [ $((counter % 30)) -eq 0 ]; then
            show_message "Esperando... ($counter/$timeout segundos)"
        fi
    done
    
    show_error "Timeout esperando a que $service_url esté disponible"
    return 1
}

# Función para inicializar la base de datos de Chatwoot
initialize_chatwoot_database() {
    local tool_name="chatwoot"
    local subdomain=$1
    
    show_message "Inicializando base de datos de Chatwoot..."
    
    # Verificar que Redis esté disponible (por conexión real)
    show_message "Verificando disponibilidad de Redis..."
    local redis_ready=false
    local max_attempts=60
    local attempt=0

    # Obtener el ID del contenedor del servicio Redis
    local container_id=""
    while [ $attempt -lt $max_attempts ] && [ -z "$container_id" ]; do
        container_id=$(docker ps --filter "name=redis-server" --format "{{.ID}}" 2>/dev/null)
        if [ -z "$container_id" ]; then
            sleep 5
            attempt=$((attempt + 1))
            show_message "Esperando a que Redis inicie... ($((attempt * 5))/300 segundos)"
        fi
    done

    if [ -z "$container_id" ]; then
        show_error "Redis no está disponible después de 5 minutos"
        return 1
    fi

    attempt=0
    while [ $attempt -lt $max_attempts ] && [ "$redis_ready" = false ]; do
        if docker exec "$container_id" redis-cli ping 2>/dev/null | grep -q "PONG"; then
            redis_ready=true
            show_success "Redis está listo"
        else
            sleep 5
            attempt=$((attempt + 1))
            if [ $((attempt % 12)) -eq 0 ]; then
                show_message "Esperando Redis... ($((attempt * 5))/300 segundos)"
            fi
        fi
    done

    if [ "$redis_ready" = false ]; then
        show_error "Redis no está disponible después de 5 minutos"
        return 1
    fi
    
    # Crear un stack temporal solo para inicializar la base de datos
    show_message "Creando stack temporal para inicialización de base de datos..."
    
    local init_stack_file="/tmp/chatwoot-init-stack.yml"
    cat > "$init_stack_file" << EOF
version: '3.8'

services:
  chatwoot-postgres:
    image: pgvector/pgvector:pg16
    environment:
      - POSTGRES_DB=chatwoot
      - POSTGRES_USER=postgres
      - POSTGRES_PASSWORD=$COMMON_PASSWORD
      - POSTGRES_INITDB_ARGS=--encoding=UTF-8 --lc-collate=C --lc-ctype=C
      
    volumes:
      - chatwoot_postgres:/var/lib/postgresql/data
      
    deploy:
      replicas: 1
      restart_policy:
        condition: on-failure
        delay: 5s
        max_attempts: 3
        window: 120s
      placement:
        constraints:
          - node.role == manager
    networks:
      - backend

  chatwoot-init:
    image: chatwoot/chatwoot:latest
    command: ["bundle", "exec", "rails", "db:chatwoot_prepare"]
    environment:
      - POSTGRES_HOST=chatwoot-postgres
      - POSTGRES_PORT=5432
      - POSTGRES_DATABASE=chatwoot
      - POSTGRES_USERNAME=postgres
      - POSTGRES_PASSWORD=$COMMON_PASSWORD
      - REDIS_URL=redis://redis-server:6379/4
      - SECRET_KEY_BASE=$SECRET_KEY
      - RAILS_ENV=production
      - NODE_ENV=production
    networks:
      - backend
    depends_on:
      - chatwoot-postgres
    deploy:
      restart_policy:
        condition: none
      placement:
        constraints:
          - node.role == manager

networks:
  backend:
    external: true

volumes:
  chatwoot_postgres:
    driver: local
    driver_opts:
      type: none
      device: /home/docker/chatwoot/postgres_data
      o: bind
EOF
    
    register_temp_file "$init_stack_file"
    
    # Desplegar el stack de inicialización
    show_message "Desplegando stack de inicialización de Chatwoot..."
    if ! docker stack deploy -c "$init_stack_file" chatwoot-init >/dev/null 2>&1; then
        show_error "Error al desplegar el stack de inicialización"
        return 1
    fi

    show_success "Stack de inicialización desplegado"
    
    # Esperar a que el contenedor de PostgreSQL esté corriendo
    local postgres_container_id=""
    local postgres_attempt=0
    local max_postgres_attempt=30
    
    show_message "Esperando a que el contenedor de PostgreSQL inicie..."
    while [ $postgres_attempt -lt $max_postgres_attempt ] && [ -z "$postgres_container_id" ]; do
        postgres_container_id=$(docker ps -q --filter "name=chatwoot-init_chatwoot-postgres" 2>/dev/null)
        if [ -z "$postgres_container_id" ]; then
            sleep 5
            postgres_attempt=$((postgres_attempt + 1))
        fi
    done

    if [ -z "$postgres_container_id" ]; then
        show_error "No se pudo obtener el ID del contenedor PostgreSQL"
        docker stack rm chatwoot-init >/dev/null 2>&1
        return 1
    fi

    # Verificar conexión a PostgreSQL usando pg_isready
    show_message "Verificando disponibilidad de PostgreSQL..."
    local pg_ready=false
    local max_pg_wait=60
    local pg_attempt=0

    while [ $pg_attempt -lt $max_pg_wait ] && [ "$pg_ready" = false ]; do
        if docker exec "$postgres_container_id" pg_isready -U postgres -h localhost >/dev/null 2>&1; then
            pg_ready=true
            show_success "PostgreSQL está listo"
            # Espera adicional para asegurar estabilidad
            sleep 10
        else
            sleep 5
            pg_attempt=$((pg_attempt + 1))
            show_message "Esperando PostgreSQL... ($pg_attempt/$max_pg_wait intentos)"
        fi
    done

    if [ "$pg_ready" = false ]; then
        show_error "PostgreSQL no está disponible después de 5 minutos"
        docker stack rm chatwoot-init >/dev/null 2>&1
        return 1
    fi
        
    # Esperar a que termine la inicialización
    show_message "Esperando a que termine la inicialización de la base de datos..."
    local init_complete=false
    local max_wait=600  # 10 minutos máximo para la inicialización
    local wait_time=0
    
    while [ $wait_time -lt $max_wait ] && [ "$init_complete" = false ]; do
        # Verificar si el servicio ha terminado exitosamente
        local service_status=$(docker service ps chatwoot-init_chatwoot-init --format "{{.CurrentState}}" --no-trunc 2>/dev/null | head -1)
        
        if echo "$service_status" | grep -q "Complete"; then
            init_complete=true
            show_success "Inicialización de base de datos completada exitosamente"
        elif echo "$service_status" | grep -q "Failed"; then
            show_error "La inicialización de la base de datos falló"
            # Mostrar logs para diagnóstico
            show_message "Logs del servicio de inicialización:"
            docker service logs chatwoot-init_chatwoot-init 2>/dev/null | tail -20
            show_message "Logs de PostgreSQL:"
            docker service logs chatwoot-init_chatwoot-postgres 2>/dev/null | tail -20
            break
        fi
        
        sleep 10
        wait_time=$((wait_time + 10))
        
        # Mostrar progreso cada minuto
        if [ $((wait_time % 60)) -eq 0 ]; then
            show_message "Inicializando base de datos... ($wait_time/$max_wait segundos)"
            # Mostrar logs actuales cada minuto para debugging
            show_message "Estado actual de inicialización:"
            docker service logs chatwoot-init_chatwoot-init --tail 5 2>/dev/null | tail -3
        fi
    done
    
    # Limpiar el stack de inicialización
    show_message "Limpiando stack de inicialización..."
    docker stack rm chatwoot-init >/dev/null 2>&1
    
    # Esperar a que se limpie completamente
    sleep 15
    
    if [ "$init_complete" = true ]; then
        show_success "Base de datos de Chatwoot inicializada correctamente"
        return 0
    else
        show_error "La inicialización de la base de datos no se completó en el tiempo esperado"
        return 1
    fi
}

# Función para crear directorios para volúmenes de Docker
create_volume_directories() {
    local stack_file=$1
    local tool_name=$2
    local volume_path

    # Extraer rutas de volúmenes del archivo stack.yml
    # Busca líneas que definen volúmenes con 'device:' y extrae la ruta
    volume_paths=$(grep -E 'device: /home/docker/[^/]+/[^/]+' "$stack_file" | awk -F'device: ' '{print $2}' | tr -d ' ')

    if [ -n "$volume_paths" ]; then
        show_message "Creando directorios para volúmenes de $tool_name..."
        for volume_path in $volume_paths; do
            # Asegurarse de que la ruta sea absoluta y esté bajo /home/docker
            if [[ "$volume_path" == "/home/docker/$tool_name/"* ]]; then
                mkdir -p "$volume_path"
                if [ $? -eq 0 ]; then
                    show_message "Directorio de volumen creado: $volume_path"
                else
                    show_warning "No se pudo crear el directorio de volumen: $volume_path. Puede que ya exista o haya un problema de permisos."
                fi
            else
                show_warning "Ruta de volumen inesperada o fuera del directorio de la herramienta: $volume_path. Saltando creación de directorio."
            fi
        done
    else
        show_message "No se encontraron volúmenes específicos para $tool_name en $stack_file que requieran creación de directorio."
    fi
}

# Función para instalar una herramienta con Docker Swarm
install_docker_tool() {
    local tool_name=$1
    local default_subdomain=$2
    local tool_index=$3 # Se necesita para CUSTOM_SUBDOMAINS
    
    show_message "Configurando $tool_name..."
    local tool_dir="$DOCKER_DIR/$tool_name"
    mkdir -p "$tool_dir"
    cd "$tool_dir" || {
        show_error "No se pudo acceder al directorio $tool_dir"
        cleanup 1
        exit 1
    }
    
    # Solicitar subdominio
    read -p "Ingrese el subdominio para $tool_name [$default_subdomain]: " SUBDOMAIN
    SUBDOMAIN=${SUBDOMAIN:-$default_subdomain}

    # Guardar el subdominio personalizado en el array
    CUSTOM_SUBDOMAINS[$tool_index]=$SUBDOMAIN

    # Guardar el subdominio en un archivo para referencia futura
    local subdomain_file="$tool_dir/.subdomain"
    echo "$SUBDOMAIN" > "$subdomain_file"
    register_temp_file "$subdomain_file"
    
    show_message "Generando archivo de configuración para $tool_name..."
    local stack_file="$tool_dir/$tool_name-stack.yml"

    # Llamar a la función adecuada para escribir el archivo .yml
    case "$tool_name" in
        "traefik") write_traefik_stack_yml "$BASE_DOMAIN" "$LE_EMAIL" "$ENABLE_LE" ;;
        "portainer") write_portainer_stack_yml "$SUBDOMAIN" "$BASE_DOMAIN" ;;
        "redis") write_redis_stack_yml "$SUBDOMAIN" "$BASE_DOMAIN" ;;
        "postgres") write_postgres_stack_yml "$COMMON_PASSWORD" ;;
        "n8n") write_n8n_stack_yml "$SUBDOMAIN" "$BASE_DOMAIN" "$COMMON_PASSWORD" "$SECRET_KEY" ;;
        "evoapi") write_evoapi_stack_yml "$SUBDOMAIN" "$BASE_DOMAIN" "$COMMON_PASSWORD" "$SECRET_KEY" ;;
        "chatwoot") write_chatwoot_stack_yml "$SUBDOMAIN" "$BASE_DOMAIN" "$COMMON_PASSWORD" "$SECRET_KEY" ;;
        *)
            show_error "Herramienta desconocida: $tool_name"
            cleanup 1
            exit 1
            ;;
    esac

    # Crear directorios para volúmenes DESPUÉS de escribir el archivo
    create_volume_directories "$stack_file" "$tool_name"
    
    # Desplegar el stack
    run_command "docker stack deploy -c \"$stack_file\" $tool_name" "Desplegando stack $tool_name..."
    INSTALLED_COMPONENTS[$tool_name]=true

    # Tratamiento especial para Chatwoot
    if [ "$tool_name" = "chatwoot" ]; then
        initialize_chatwoot_database "$SUBDOMAIN"
        if [ $? -ne 0 ]; then
            show_error "Fallo en la inicialización de la base de datos de Chatwoot."
            cleanup 1
            exit 1
        fi
    fi

    # Volver al directorio principal
    cd "$DOCKER_DIR" || exit
}

# --- Lógica principal del instalador ---

# Crear directorio principal
DOCKER_DIR="/home/docker"
mkdir -p "$DOCKER_DIR"
cd "$DOCKER_DIR" || {
    show_error "No se pudo acceder al directorio $DOCKER_DIR"
    cleanup 1
    exit 1
}

# Lista de herramientas disponibles
AVAILABLE_TOOLS=("traefik" "portainer" "redis" "postgres" "n8n" "evoapi" "chatwoot")
DEFAULT_SUBDOMAINS=("proxy" "admin" "redis" "postgres" "n8" "evoapi" "chat")
SELECTED_TOOLS=()
CUSTOM_SUBDOMAINS=()

# Solicitar información al usuario
show_message "Configuración inicial"
read -p "Ingrese su dominio principal (ej. midominio.com): " BASE_DOMAIN
if [ -z "$BASE_DOMAIN" ]; then
    show_error "El dominio principal no puede estar vacío."
    cleanup 1
    exit 1
fi

read -p "¿Desea habilitar Let's Encrypt para certificados SSL (y HTTP a HTTPS)? (s/n): " ENABLE_LE_CHOICE
ENABLE_LE_CHOICE=${ENABLE_LE_CHOICE:-s}
ENABLE_LE=false
LE_EMAIL=""
if [[ "$ENABLE_LE_CHOICE" =~ ^[Ss]$ ]]; then
    ENABLE_LE=true
    read -p "Ingrese su dirección de correo electrónico para Let's Encrypt: " LE_EMAIL
    if [ -z "$LE_EMAIL" ]; then
        show_error "Se requiere un correo electrónico para Let's Encrypt si está habilitado."
        cleanup 1
        exit 1
    fi
fi

read -p "Ingrese la contraseña común para todas las herramientas: " COMMON_PASSWORD
if [ -z "$COMMON_PASSWORD" ]; then
    show_error "La contraseña no puede estar vacía"
    cleanup 1
    exit 1
fi

# Generar una clave secreta aleatoria para herramientas que la necesiten
SECRET_KEY=$(generate_random_key)

# Preguntar al usuario qué herramientas desea instalar
show_message "Seleccione las herramientas a instalar (separadas por espacios, ej: traefik portainer n8n):"
show_message "Disponibles: ${AVAILABLE_TOOLS[*]}"
read -p "Su selección: " USER_SELECTION

if [ -z "$USER_SELECTION" ]; then
    show_error "Debe seleccionar al menos una herramienta."
    cleanup 1
    exit 1
fi

# Validar selección del usuario
for tool in $USER_SELECTION; do
    found=false
    for available_tool in "${AVAILABLE_TOOLS[@]}"; do
        if [ "$tool" = "$available_tool" ]; then
            SELECTED_TOOLS+=("$tool")
            found=true
            break
        fi
    done
    if [ "$found" = false ]; then
        show_error "Herramienta no reconocida: $tool"
        cleanup 1
        exit 1
    fi
done

if [ ${#SELECTED_TOOLS[@]} -eq 0 ]; then
    show_error "No se seleccionaron herramientas válidas para instalar."
    cleanup 1
    exit 1
fi

# Instalar Docker y Docker Compose si no están instalados
show_message "Verificando instalación de Docker y Docker Compose..."
if ! command -v docker &> /dev/null; then
    show_message "Docker no encontrado. Instalando Docker..."
    run_command "curl -fsSL https://get.docker.com -o get-docker.sh && sh get-docker.sh" "Descargando e instalando Docker..."
    run_command "systemctl enable docker" "Habilitando Docker al inicio del sistema..."
    run_command "systemctl start docker" "Iniciando servicio Docker..."
    show_success "Docker instalado y funcionando."
else
    show_success "Docker ya está instalado."
fi

if ! command -v docker compose &> /dev/null; then
    show_message "Docker Compose no encontrado. Instalando Docker Compose..."
    # Docker Compose V2 se instala con Docker Engine ahora
    show_message "Docker Compose V2 se instala automáticamente con Docker Engine. Verificando..."
    if ! docker compose version &> /dev/null; then
        show_error "Docker Compose V2 no se instaló correctamente con Docker. Intente instalarlo manualmente."
        cleanup 1
        exit 1
    fi
    show_success "Docker Compose V2 está instalado."
else
    show_success "Docker Compose ya está instalado."
fi

# Inicializar Docker Swarm si no está inicializado
show_message "Verificando estado de Docker Swarm..."
if ! docker info | grep -q "Swarm: active"; then
    show_message "Docker Swarm no está inicializado. Inicializando..."
    run_command "docker swarm init" "Inicializando Docker Swarm..."
    show_success "Docker Swarm inicializado."
else
    show_success "Docker Swarm ya está activo."
fi

# Crear redes Docker si no existen
show_message "Creando redes Docker (frontend y backend) si no existen..."
if ! docker network ls | grep -q "frontend"; then
    run_command "docker network create --driver overlay frontend" "Creando red frontend..."
else
    show_message "Red frontend ya existe."
fi

if ! docker network ls | grep -q "backend"; then
    run_command "docker network create --driver overlay backend" "Creando red backend..."
else
    show_message "Red backend ya existe."
fi
show_success "Redes Docker configuradas."

# Instalar herramientas seleccionadas
for i in "${!SELECTED_TOOLS[@]}"; do
    tool_name="${SELECTED_TOOLS[$i]}"
    default_subdomain="${DEFAULT_SUBDOMAINS[$i]}"
    install_docker_tool "$tool_name" "$default_subdomain" "$i"
done

cleanup 0 true # Limpieza final y mensaje de éxito

exit 0


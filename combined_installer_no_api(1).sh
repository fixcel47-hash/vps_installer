#!/bin/bash

# ============================================
# Instalador Unificado de Herramientas Docker
# (Sin API ni Funcionalidad de Descarga Externa)
# ============================================

# Colores
RED=\'\033[0;31m\'
GREEN=\'\033[0;32m\'
YELLOW=\'\033[0;33m\'
BLUE=\'\033[0;34m\'
NC=\'\033[0m\' # No Color

# Funciones de mensaje
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

# Variables del instalador
SCRIPT_VERSION="1.2.0"
SCRIPT_PATH=$(readlink -f "$0")

# Lista de archivos temporales para limpiar
TEMP_FILES=()

declare -gA INSTALLED_COMPONENTS=(
    [dependencies]=false
    [security]=false
    [networks]=false
)

# Función de limpieza (adaptada de installer.sh)
cleanup() {
    local exit_code=$1
    local delete_stacks=${2:-false}
    
    echo -e "${BLUE}[INFO]${NC} Realizando limpieza antes de salir..."
    
    if [ $exit_code -ne 0 ]; then
        echo -e "${RED}[ERROR]${NC} Error detectado durante la instalación. Limpiando archivos temporales..."
        if [ ${#TEMP_FILES[@]} -gt 0 ]; then
            for file in "${TEMP_FILES[@]}"; do
                if [ -f "$file" ]; then
                    rm -f "$file"
                fi
            done
        fi
    fi
    
    if [ "$delete_stacks" = true ]; then
        for tool_name in "${SELECTED_TOOLS[@]}"; do
            local stack_file="$DOCKER_DIR/$tool_name/$tool_name-stack.yml"
            if [ -f "$stack_file" ]; then
                rm -f "$stack_file"
            fi
        done
    fi
    
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
    
    if [ $exit_code -ne 0 ]; then
        echo -e "${RED}[ERROR]${NC} La instalación ha fallado. Revise los logs para más información."
    else
        echo -e "${GREEN}[SUCCESS]${NC} Instalación completada exitosamente"
    fi
}

# Configurar trampas para señales para limpiar antes de salir
trap \'cleanup 1 false; exit 1\' SIGHUP SIGINT SIGQUIT SIGTERM
trap \'cleanup 1 false; exit 1\' ERR

# Función para registrar un archivo temporal para limpieza posterior
register_temp_file() {
    local file_path=$1
    TEMP_FILES+=("$file_path")
    show_message "Registrado archivo temporal: $file_path"
}

# Función para recopilar información del sistema (neutralizada IP_ADDRESS)
collect_system_info() {
    HOSTNAME=$(hostname)
    OS_INFO=$(cat /etc/os-release | grep "PRETTY_NAME" | cut -d \'"\' -f 2)
    CPU_INFO=$(grep "model name" /proc/cpuinfo | head -n 1 | cut -d : -f 2 | sed \'s/^ //\')
    MEM_TOTAL=$(free -h | grep "Mem:" | awk \'{print $2}\
')
}

# Funciones API (neutralizadas)
register_installation_start() {
    show_message "Registrando instalación (funcionalidad API neutralizada)..."
    collect_system_info
    INSTALLATION_ID="mock_installation_id"
    return 0
}

update_installation_status() {
    return 0
}

complete_installation() {
    return 0
}

# Función para animación de espera
spinner() {
    local pid=$1
    local delay=0.1
    local spinstr=\'|/-\\\\\'
    
    echo -n "Procesando "
    while [ "$(ps a | awk \'\'{print $1}\'\' | grep $pid)" ]; do
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

# Función para esperar a que un servicio esté disponible
wait_for_service() {
    local service_url=$1
    local timeout=${2:-300}
    
    show_message "Esperando a que $service_url esté disponible..."
    
    local counter=0
    while [ $counter -lt $timeout ]; do
        if curl -k -s --connect-timeout 5 "$service_url" >/dev/null 2>&1; then
            show_success "Servicio $service_url está disponible"
            return 0
        fi
        
        sleep 5
        counter=$((counter + 5))
        
        if [ $((counter % 30)) -eq 0 ]; then
            show_message "Esperando... ($counter/$timeout segundos)"
        fi
    done
    
    show_error "Timeout esperando a que $service_url esté disponible"
    return 1
}

# Función para crear directorios para volúmenes de Docker
create_volume_directories() {
    local stack_file=$1
    local tool_name=$2
    local volume_path

    volume_paths=$(grep -E \'device: /home/docker/[^/]+/[^/]+\' "$stack_file" | awk -F\'device: \' \'{print $2}\' | tr -d \' \')

    if [ -n "$volume_paths" ]; then
        show_message "Creando directorios para volúmenes de $tool_name..."
        for volume_path in $volume_paths; do
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

# Funciones para escribir archivos Docker Compose (heredoc)
# Estas funciones deben ser definidas con el contenido de los archivos .yml
# Como no se proporcionaron los .yml originales en esta solicitud, se usarán versiones genéricas o se omitirán.

# Placeholder para write_chatwoot_stack_yml
write_chatwoot_stack_yml() {
    local subdomain=$1
    local domain=$2
    local password=$3
    local secret_key=$4
    show_message "Generando chatwoot-stack.yml (contenido placeholder)"
    mkdir -p "$DOCKER_DIR/chatwoot"
    cat << EOF > "$DOCKER_DIR/chatwoot/chatwoot-stack.yml"
version: '3.8'
services:
  rails:
    image: chatwoot/chatwoot:latest
    environment:
      - FRONTEND_URL=https://$subdomain.$domain
      - SECRET_KEY_BASE=$secret_key
      - POSTGRES_PASSWORD=$password
      - SMTP_PASSWORD=$password
    networks:
      - frontend
      - backend
  sidekiq:
    image: chatwoot/chatwoot:latest
    environment:
      - FRONTEND_URL=https://$subdomain.$domain
      - SECRET_KEY_BASE=$secret_key
      - POSTGRES_PASSWORD=$password
      - SMTP_PASSWORD=$password
    networks:
      - backend
  chatwoot-postgres:
    image: pgvector/pgvector:pg16
    environment:
      - POSTGRES_PASSWORD=$password
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

# Placeholder para write_evoapi_stack_yml
write_evoapi_stack_yml() {
    local subdomain=$1
    local domain=$2
    local password=$3
    local secret_key=$4
    show_message "Generando evoapi-stack.yml (contenido placeholder)"
    mkdir -p "$DOCKER_DIR/evoapi"
    cat << EOF > "$DOCKER_DIR/evoapi/evoapi-stack.yml"
version: '3'
services:
  evolution-api:
    image: evoapicloud/evolution-api:latest
    environment:
      - SUBDOMAIN=$subdomain
      - DOMAIN=$domain
      - PASSWORD=$password
      - SECRET_KEY=$secret_key
      - DATABASE_CONNECTION_URI=postgresql://postgres:$password@postgres-evoapi:5432/evolution2?schema=public
      - RABBITMQ_URI=amqp://evo-rabbit:$password@rabbitmq:5672/default
      - RABBITMQ_ERLANG_COOKIE=$password
      - RABBITMQ_DEFAULT_PASS=$password
      - AUTHENTICATION_API_KEY=$secret_key
    networks:
      - frontend
      - backend
  postgres-evoapi:
    image: postgres:15
    environment:
      - POSTGRES_PASSWORD=$password
    networks:
      - backend
  rabbitmq:
    image: rabbitmq:management
    environment:
      - RABBITMQ_ERLANG_COOKIE=$password
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

# Placeholder para write_n8n_stack_yml
write_n8n_stack_yml() {
    local subdomain=$1
    local domain=$2
    local password=$3
    local secret_key=$4
    show_message "Generando n8n-stack.yml (contenido placeholder)"
    mkdir -p "$DOCKER_DIR/n8n"
    cat << EOF > "$DOCKER_DIR/n8n/n8n-stack.yml"
version: '3.8'
services:
  'n8n-db':
    image: postgres:16
    environment:
      - POSTGRES_PASSWORD=$password
    networks:
      - backend
  n8n_editor:
    image: n8nio/n8n:latest
    environment:
      - N8N_ENCRYPTION_KEY=$secret_key
      - DB_POSTGRESDB_PASSWORD=$password
      - N8N_HOST=$subdomain.$domain
      - N8N_EDITOR_BASE_URL=https://$subdomain.$domain
      - WEBHOOK_URL=https://webhook.$subdomain.$domain
    networks:
      - frontend
      - backend
  n8n_worker:
    image: n8nio/n8n:latest
    environment:
      - N8N_ENCRYPTION_KEY=$secret_key
      - DB_POSTGRESDB_PASSWORD=$password
      - N8N_HOST=$subdomain.$domain
      - N8N_EDITOR_BASE_URL=https://$subdomain.$domain
      - WEBHOOK_URL=https://webhook.$subdomain.$domain
    networks:
      - backend
  n8n_webhook:
    image: n8nio/n8n:latest
    environment:
      - N8N_ENCRYPTION_KEY=$secret_key
      - DB_POSTGRESDB_PASSWORD=$password
      - N8N_HOST=$subdomain.$domain
      - N8N_EDITOR_BASE_URL=https://$subdomain.$domain
      - WEBHOOK_URL=https://webhook.$subdomain.$domain
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

# Placeholder para write_portainer_stack_yml
write_portainer_stack_yml() {
    local subdomain=$1
    local domain=$2
    show_message "Generando portainer-stack.yml (contenido placeholder)"
    mkdir -p "$DOCKER_DIR/portainer"
    cat << EOF > "$DOCKER_DIR/portainer/portainer-stack.yml"
version: "3.7"
services:
  agent:
    image: portainer/agent:latest 
    networks:
      - frontend
  portainer:
    image: portainer/portainer-ce:latest 
    command: -H tcp://tasks.agent:9001 --tlsskipverify
    networks:
      - frontend
    labels:
      - "traefik.http.routers.portainer.rule=Host(`$subdomain.$domain`)" 
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

# Placeholder para write_postgres_stack_yml
write_postgres_stack_yml() {
    local password=$1
    show_message "Generando postgres-stack.yml (contenido placeholder)"
    mkdir -p "$DOCKER_DIR/postgres"
    cat << EOF > "$DOCKER_DIR/postgres/postgres-stack.yml"
version: '3.8'
services:
  postgres-server:
    image: postgres:latest
    environment:
      - POSTGRES_PASSWORD=$password
    networks:
      - backend
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

# Placeholder para write_redis_stack_yml
write_redis_stack_yml() {
    local subdomain=$1
    local domain=$2
    show_message "Generando redis-stack.yml (contenido placeholder)"
    mkdir -p "$DOCKER_DIR/redis"
    cat << EOF > "$DOCKER_DIR/redis/redis-stack.yml"
version: '3.7'
services:
  redis-server:
    image: redis:latest
    networks:
      - backend
  redisinsight:
    image: redislabs/redisinsight:latest
    networks:
      - backend
      - frontend
    labels:
      - "traefik.http.routers.redisinsight.rule=Host(`$subdomain.$domain`)"
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

# Placeholder para write_traefik_stack_yml
write_traefik_stack_yml() {
    local domain=$1
    local email=$2
    local enable_le=$3
    show_message "Generando traefik-stack.yml (contenido placeholder)"
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
      - --entrypoints.web.http.redirections.entrypoint.to=websecure
      - --entrypoints.web.http.redirections.entrypoint.schem=https
$(if [ "$enable_le" = true ]; then)
      - --certificatesresolvers.le.acme.email=$email
      - --certificatesresolvers.le.acme.storage=/etc/traefik/acme.json
      - --certificatesresolvers.le.acme.tlschallenge=true
$(fi)
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
      - traefik_data:/etc/traefik
    networks:
      - frontend
    labels:
      - "traefik.http.routers.api.rule=Host(`traefik.$domain`)"
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

# Función para inicializar la base de datos de Chatwoot
initialize_chatwoot_database() {
    local tool_name="chatwoot"
    local subdomain=$1
    
    show_message "Inicializando base de datos de Chatwoot..."
    
    show_message "Verificando disponibilidad de Redis..."
    local redis_ready=false
    local max_attempts=60
    local attempt=0

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
    
    show_message "Desplegando stack de inicialización de Chatwoot..."
    if ! docker stack deploy -c "$init_stack_file" chatwoot-init >/dev/null 2>&1; then
        show_error "Error al desplegar el stack de inicialización"
        return 1
    fi

    show_success "Stack de inicialización desplegado"
    
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

    show_message "Verificando disponibilidad de PostgreSQL..."
    local pg_ready=false
    local max_pg_wait=60
    local pg_attempt=0

    while [ $pg_attempt -lt $max_pg_wait ] && [ "$pg_ready" = false ]; do
        if docker exec "$postgres_container_id" pg_isready -U postgres -h localhost >/dev/null 2>&1; then
            pg_ready=true
            show_success "PostgreSQL está listo"
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
        
    show_message "Esperando a que termine la inicialización de la base de datos..."
    local init_complete=false
    local max_wait=600
    local wait_time=0
    
    while [ $wait_time -lt $max_wait ] && [ "$init_complete" = false ]; do
        local service_status=$(docker service ps chatwoot-init_chatwoot-init --format "{{.CurrentState}}" --no-trunc 2>/dev/null | head -1)
        
        if echo "$service_status" | grep -q "Complete"; then
            init_complete=true
            show_success "Inicialización de base de datos completada exitosamente"
        elif echo "$service_status" | grep -q "Failed"; then
            show_error "La inicialización de la base de datos falló"
            show_message "Logs del servicio de inicialización:"
            docker service logs chatwoot-init_chatwoot-init 2>/dev/null | tail -20
            show_message "Logs de PostgreSQL:"
            docker service logs chatwoot-init_chatwoot-postgres 2>/dev/null | tail -20
            break
        fi
        
        sleep 10
        wait_time=$((wait_time + 10))
        
        if [ $((wait_time % 60)) -eq 0 ]; then
            show_message "Inicializando base de datos... ($wait_time/$max_wait segundos)"
            show_message "Estado actual de inicialización:"
            docker service logs chatwoot-init_chatwoot-init --tail 5 2>/dev/null | tail -3
        fi
    done
    
    show_message "Limpiando stack de inicialización..."
    docker stack rm chatwoot-init >/dev/null 2>&1
    
    sleep 15
    
    if [ "$init_complete" = true ]; then
        show_success "Base de datos de Chatwoot inicializada correctamente"
        return 0
    else
        show_error "La inicialización de la base de datos no se completó en el tiempo esperado"
        return 1
    fi
}

# Función para instalar una herramienta con Docker Swarm
install_docker_tool() {
    local tool_name=$1
    local default_subdomain=$2
    local tool_index=$3
    
    show_message "Configurando $tool_name..."
    local tool_dir="$DOCKER_DIR/$tool_name"
    mkdir -p "$tool_dir"
    cd "$tool_dir" || {
        show_error "No se pudo acceder al directorio $tool_dir"
        cleanup 1
        exit 1
    }
    
    local SUBDOMAIN="${DEFAULT_SUBDOMAINS[$tool_index]}"

    CUSTOM_SUBDOMAINS[$tool_index]=$SUBDOMAIN

    local subdomain_file="$tool_dir/.subdomain"
    echo "$SUBDOMAIN" > "$subdomain_file"
    register_temp_file "$subdomain_file"
    
    show_message "Generando archivo de configuración para $tool_name..."
    local stack_file="$tool_dir/$tool_name-stack.yml"

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

    create_volume_directories "$stack_file" "$tool_name"
    
    run_command "docker stack deploy -c \"$stack_file\" $tool_name" "Desplegando stack $tool_name..."
    INSTALLED_COMPONENTS[$tool_name]=true

    if [ "$tool_name" = "chatwoot" ]; then
        initialize_chatwoot_database "$SUBDOMAIN"
        if [ $? -ne 0 ]; then
            show_error "Fallo en la inicialización de la base de datos de Chatwoot."
            cleanup 1
            exit 1
        fi
    fi

    cd "$DOCKER_DIR" || exit
}

# --- Lógica principal del instalador ---

# Variables para argumentos de línea de comandos
BASE_DOMAIN=""
LE_EMAIL=""
COMMON_PASSWORD=""
USER_SELECTION=""
ENABLE_LE=false

# Procesar parámetros de línea de comandos
while [[ $# -gt 0 ]]; do
    key="$1"
    case $key in
        --domain)
            BASE_DOMAIN="$2"
            shift 2
            ;;
        --email)
            LE_EMAIL="$2"
            ENABLE_LE=true
            shift 2
            ;;
        --password)
            COMMON_PASSWORD="$2"
            shift 2
            ;;
        --tools)
            USER_SELECTION="$2"
            shift 2
            ;;
        --enable-le)
            ENABLE_LE=true
            shift
            ;;
        *)
            show_warning "Argumento desconocido o malformado: $1"
            shift
            ;;
    esac
done

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

show_message "Configuración inicial"

# Obtener o solicitar dominio principal
if [ -z "$BASE_DOMAIN" ]; then
    read -p "Ingrese su dominio principal (ej. midominio.com): " BASE_DOMAIN
    if [ -z "$BASE_DOMAIN" ]; then
        show_error "El dominio principal no puede estar vacío."
        cleanup 1
        exit 1
    fi
fi

# Obtener o solicitar correo electrónico para Let\'s Encrypt
if [ "$ENABLE_LE" = true ] && [ -z "$LE_EMAIL" ]; then
    read -p "Ingrese su dirección de correo electrónico para Let\'s Encrypt: " LE_EMAIL
    if [ -z "$LE_EMAIL" ]; then
        show_error "Se requiere un correo electrónico para Let\'s Encrypt si está habilitado."
        cleanup 1
        exit 1
    fi
elif [ "$ENABLE_LE" = false ]; then
    read -p "¿Desea habilitar Let\'s Encrypt para certificados SSL (y HTTP a HTTPS)? (s/n): " ENABLE_LE_CHOICE
    ENABLE_LE_CHOICE=${ENABLE_LE_CHOICE:-s}
    if [[ "$ENABLE_LE_CHOICE" =~ ^[Ss]$ ]]; then
        ENABLE_LE=true
        read -p "Ingrese su dirección de correo electrónico para Let\'s Encrypt: " LE_EMAIL
        if [ -z "$LE_EMAIL" ]; then
            show_error "Se requiere un correo electrónico para Let\'s Encrypt si está habilitado."
            cleanup 1
            exit 1
        fi
    fi
fi

# Obtener o solicitar contraseña común
if [ -z "$COMMON_PASSWORD" ]; then
    read -p "Ingrese la contraseña común para todas las herramientas: " COMMON_PASSWORD
    if [ -z "$COMMON_PASSWORD" ]; then
        show_error "La contraseña no puede estar vacía"
        cleanup 1
        exit 1
    fi
fi

# Generar una clave secreta aleatoria para herramientas que la necesiten
SECRET_KEY=$(generate_random_key)

# Obtener o solicitar selección de herramientas
if [ -z "$USER_SELECTION" ]; then
    show_message "Seleccione las herramientas a instalar (separadas por espacios, ej: traefik portainer n8n):"
    show_message "Disponibles: ${AVAILABLE_TOOLS[*]}"
    read -p "Su selección: " USER_SELECTION
    if [ -z "$USER_SELECTION" ]; then
        show_error "Debe seleccionar al menos una herramienta."
        cleanup 1
        exit 1
    fi
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

cleanup 0 true

exit 0


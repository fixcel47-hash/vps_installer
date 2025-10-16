#!/bin/bash

# ============================================
# Instalador Docker Todo-en-Uno
# Sin necesidad de archivos externos
# ============================================

SCRIPT_VERSION="2.0.0"

# Colores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuración
DOCKER_DIR="/home/docker"
TEMP_FILES=()

show_message() { echo -e "${BLUE}[INFO]${NC} $1"; }
show_error() { echo -e "${RED}[ERROR]${NC} $1"; }
show_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
show_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }

# Limpieza
cleanup() {
    local exit_code=$1
    show_message "Realizando limpieza..."
    
    if [ $exit_code -ne 0 ]; then
        show_error "Error detectado. Limpiando archivos temporales..."
        for file in "${TEMP_FILES[@]}"; do
            [ -f "$file" ] && rm -f "$file"
        done
    else
        find "$DOCKER_DIR" -name "*-stack.yml" -type f -delete 2>/dev/null
    fi
    
    [ $exit_code -eq 0 ] && show_success "Instalación completada" || show_error "La instalación ha fallado"
}

trap 'cleanup 1; exit 1' SIGHUP SIGINT SIGQUIT SIGTERM ERR

register_temp_file() { TEMP_FILES+=("$1"); }

generate_random_key() {
    tr -dc 'A-Za-z0-9' </dev/urandom | head -c 32
}

run_command() {
    local cmd=$1
    local msg=$2
    
    show_message "$msg"
    eval "$cmd" > /dev/null 2>&1 &
    
    local cmd_pid=$!
    local spinstr='|/-\'
    
    while kill -0 $cmd_pid 2>/dev/null; do
        local temp=${spinstr#?}
        printf " [%c]  " "$spinstr"
        spinstr=$temp${spinstr%"$temp"}
        sleep 0.1
        printf "\b\b\b\b\b\b"
    done
    
    wait $cmd_pid
    local exit_status=$?
    
    if [ $exit_status -ne 0 ]; then
        show_error "Comando falló: $cmd"
        cleanup 1
        exit $exit_status
    fi
    
    printf "    \b\b\b\b"
    echo -e "${GREEN}[✓]${NC}"
    return 0
}

configure_docker_logs() {
    show_message "Configurando límites de logs en Docker..."
    cat > "/etc/docker/daemon.json" <<'EOF'
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  }
}
EOF
    run_command "systemctl restart docker" "Reiniciando Docker..."
}

install_dependencies() {
    show_message "Instalando dependencias del sistema..."
    run_command "apt-get update" "Actualizando repositorios..."
    
    if ! command -v docker &> /dev/null; then
        show_message "Instalando Docker..."
        apt-get install -y ca-certificates curl gnupg
        install -m 0755 -d /etc/apt/keyrings
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
        chmod a+r /etc/apt/keyrings/docker.asc
        
        echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
        tee /etc/apt/sources.list.d/docker.list > /dev/null
        
        apt-get update
        apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
        systemctl enable docker
        systemctl start docker
        configure_docker_logs
    fi
    
    apt-get install -y git curl wget
    show_success "Dependencias instaladas"
}

initialize_docker_swarm() {
    show_message "Verificando Docker Swarm..."
    
    if ! docker info 2>/dev/null | grep -q "Swarm: active"; then
        local ip_addr=$(hostname -I | awk '{print $1}')
        run_command "docker swarm init --advertise-addr $ip_addr" "Inicializando Docker Swarm..."
        show_success "Docker Swarm inicializado"
    else
        show_message "Docker Swarm ya está activo"
    fi
}

install_security_tools() {
    show_message "Instalando herramientas de seguridad..."
    run_command "apt-get install -y fail2ban && systemctl enable fail2ban && systemctl start fail2ban" "Instalando Fail2Ban..."
    
    show_message "Configurando UFW..."
    apt-get install -y ufw
    ufw --force allow ssh
    ufw --force allow http
    ufw --force allow https
    echo "y" | ufw enable
    
    show_success "Herramientas de seguridad instaladas"
}

create_docker_networks() {
    show_message "Creando redes Docker..."
    
    if ! docker network ls 2>/dev/null | grep -q "frontend"; then
        run_command "docker network create --driver overlay --attachable frontend" "Creando red frontend..."
    fi
    
    if ! docker network ls 2>/dev/null | grep -q "backend"; then
        run_command "docker network create --driver overlay --attachable backend" "Creando red backend..."
    fi
    
    show_success "Redes Docker creadas"
}

create_traefik_stack() {
    cat > "$1" <<'EOF'
version: '3.8'

services:
  traefik:
    image: traefik:v2.10
    command:
      - "--api.dashboard=true"
      - "--providers.docker.swarmMode=true"
      - "--providers.docker.exposedbydefault=false"
      - "--entrypoints.web.address=:80"
      - "--entrypoints.websecure.address=:443"
      - "--certificatesresolvers.letsencrypt.acme.httpchallenge=true"
      - "--certificatesresolvers.letsencrypt.acme.httpchallenge.entrypoint=web"
      - "--certificatesresolvers.letsencrypt.acme.email=admin@REPLACE_DOMAIN"
      - "--certificatesresolvers.letsencrypt.acme.storage=/letsencrypt/acme.json"
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
      - traefik_certs:/letsencrypt
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
        - "traefik.http.routers.dashboard.rule=Host(\`REPLACE_SUBDOMAIN.REPLACE_DOMAIN\`)"
        - "traefik.http.routers.dashboard.entrypoints=websecure"
        - "traefik.http.routers.dashboard.tls.certresolver=letsencrypt"
        - "traefik.http.routers.dashboard.service=api@internal"
        - "traefik.http.services.dashboard.loadbalancer.server.port=8080"
        - "traefik.http.routers.dashboard.middlewares=auth"
        - "traefik.http.middlewares.auth.basicauth.users=admin:REPLACE_PASSWORD_HASH"

networks:
  frontend:
    external: true

volumes:
  traefik_certs:
    driver: local
    driver_opts:
      type: none
      device: /home/docker/traefik/certs
      o: bind
EOF
}

create_portainer_stack() {
    cat > "$1" <<'EOF'
version: '3.8'

services:
  portainer:
    image: portainer/portainer-ce:latest
    command: -H unix:///var/run/docker.sock
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - portainer_data:/data
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
        - "traefik.http.routers.portainer.rule=Host(\`REPLACE_SUBDOMAIN.REPLACE_DOMAIN\`)"
        - "traefik.http.routers.portainer.entrypoints=websecure"
        - "traefik.http.routers.portainer.tls.certresolver=letsencrypt"
        - "traefik.http.services.portainer.loadbalancer.server.port=9000"

networks:
  frontend:
    external: true

volumes:
  portainer_data:
    driver: local
    driver_opts:
      type: none
      device: /home/docker/portainer/data
      o: bind
EOF
}

create_redis_stack() {
    cat > "$1" <<'EOF'
version: '3.8'

services:
  redis:
    image: redis:7-alpine
    command: redis-server --requirepass REPLACE_PASSWORD
    volumes:
      - redis_data:/data
    networks:
      - backend
    deploy:
      mode: replicated
      replicas: 1
      restart_policy:
        condition: on-failure
      placement:
        constraints:
          - node.role == manager

networks:
  backend:
    external: true

volumes:
  redis_data:
    driver: local
    driver_opts:
      type: none
      device: /home/docker/redis/data
      o: bind
EOF
}

create_postgres_stack() {
    cat > "$1" <<'EOF'
version: '3.8'

services:
  postgres:
    image: postgres:15-alpine
    environment:
      POSTGRES_USER: postgres
      POSTGRES_PASSWORD: REPLACE_PASSWORD
      POSTGRES_DB: postgres
      PGDATA: /var/lib/postgresql/data/pgdata
    volumes:
      - postgres_data:/var/lib/postgresql/data
    networks:
      - backend
    deploy:
      mode: replicated
      replicas: 1
      restart_policy:
        condition: on-failure
      placement:
        constraints:
          - node.role == manager

networks:
  backend:
    external: true

volumes:
  postgres_data:
    driver: local
    driver_opts:
      type: none
      device: /home/docker/postgres/data
      o: bind
EOF
}

create_n8n_stack() {
    cat > "$1" <<'EOF'
version: '3.8'

services:
  n8n:
    image: n8nio/n8n:latest
    environment:
      - N8N_HOST=REPLACE_SUBDOMAIN.REPLACE_DOMAIN
      - N8N_PORT=5678
      - N8N_PROTOCOL=https
      - NODE_ENV=production
      - WEBHOOK_URL=https://REPLACE_SUBDOMAIN.REPLACE_DOMAIN/
      - GENERIC_TIMEZONE=America/Mexico_City
      - N8N_BASIC_AUTH_ACTIVE=true
      - N8N_BASIC_AUTH_USER=admin
      - N8N_BASIC_AUTH_PASSWORD=REPLACE_PASSWORD
      - N8N_ENCRYPTION_KEY=REPLACE_SECRET_KEY
      - DB_TYPE=postgresdb
      - DB_POSTGRESDB_HOST=postgres_postgres
      - DB_POSTGRESDB_PORT=5432
      - DB_POSTGRESDB_DATABASE=n8n
      - DB_POSTGRESDB_USER=postgres
      - DB_POSTGRESDB_PASSWORD=REPLACE_PASSWORD
    volumes:
      - n8n_data:/home/node/.n8n
    networks:
      - frontend
      - backend
    deploy:
      mode: replicated
      replicas: 1
      restart_policy:
        condition: on-failure
      placement:
        constraints:
          - node.role == manager
      labels:
        - "traefik.enable=true"
        - "traefik.http.routers.n8n.rule=Host(\`REPLACE_SUBDOMAIN.REPLACE_DOMAIN\`)"
        - "traefik.http.routers.n8n.entrypoints=websecure"
        - "traefik.http.routers.n8n.tls.certresolver=letsencrypt"
        - "traefik.http.services.n8n.loadbalancer.server.port=5678"

networks:
  frontend:
    external: true
  backend:
    external: true

volumes:
  n8n_data:
    driver: local
    driver_opts:
      type: none
      device: /home/docker/n8n/data
      o: bind
EOF
}

create_volume_directories() {
    local stack_file=$1
    local volume_paths=$(grep -oP "device: \K/[^\s]+" "$stack_file" | sort | uniq)
    
    for path in $volume_paths; do
        mkdir -p "$path"
    done
}

install_docker_tool() {
    local tool_name=$1
    local default_subdomain=$2
    local create_stack_func=$3
    
    show_message "Configurando $tool_name..."
    
    local tool_dir="$DOCKER_DIR/$tool_name"
    mkdir -p "$tool_dir"
    cd "$tool_dir" || exit 1
    
    read -p "Subdominio para $tool_name [$default_subdomain]: " SUBDOMAIN
    SUBDOMAIN=${SUBDOMAIN:-$default_subdomain}
    
    echo "$SUBDOMAIN" > "$tool_dir/.subdomain"
    
    local stack_file="$tool_dir/$tool_name-stack.yml"
    $create_stack_func "$stack_file"
    register_temp_file "$stack_file"
    
    local deploy_file="$tool_dir/$tool_name-deploy.yml"
    cp "$stack_file" "$deploy_file"
    register_temp_file "$deploy_file"
    
    # Generar hash de contraseña para Traefik
    local password_hash=""
    if [ "$tool_name" = "traefik" ]; then
        password_hash=$(openssl passwd -apr1 "$COMMON_PASSWORD")
        # Escapar caracteres especiales para sed
        password_hash=$(echo "$password_hash" | sed 's/[\/&$]/\\&/g' | sed 's/\$/\\$/g')
    fi
    
    sed -i "s|REPLACE_PASSWORD_HASH|$password_hash|g" "$deploy_file"
    sed -i "s|REPLACE_PASSWORD|$COMMON_PASSWORD|g" "$deploy_file"
    sed -i "s|REPLACE_SUBDOMAIN|$SUBDOMAIN|g" "$deploy_file"
    sed -i "s|REPLACE_DOMAIN|$BASE_DOMAIN|g" "$deploy_file"
    sed -i "s|REPLACE_SECRET_KEY|$SECRET_KEY|g" "$deploy_file"
    
    create_volume_directories "$deploy_file"
    
    run_command "docker stack deploy -c \"$deploy_file\" $tool_name" "Desplegando $tool_name..."
    show_success "$tool_name instalado correctamente"
    
    cd "$DOCKER_DIR" || exit 1
}

# Crear base de datos para n8n
create_n8n_database() {
    show_message "Creando base de datos para n8n..."
    sleep 10
    
    local postgres_container=$(docker ps --filter "name=postgres_postgres" --format "{{.ID}}" | head -1)
    
    if [ -n "$postgres_container" ]; then
        docker exec "$postgres_container" psql -U postgres -c "CREATE DATABASE n8n;" 2>/dev/null || true
        show_success "Base de datos n8n creada"
    fi
}

main() {
    echo -e "\n${GREEN}===========================================${NC}"
    echo -e "${GREEN}  🐳 Instalador Docker Completo 🐳       ${NC}"
    echo -e "${GREEN}  Versión: $SCRIPT_VERSION                ${NC}"
    echo -e "${GREEN}===========================================${NC}\n"
    
    if [ "$EUID" -ne 0 ]; then
        show_error "Este script debe ejecutarse como root"
        exit 1
    fi
    
    mkdir -p "$DOCKER_DIR"
    cd "$DOCKER_DIR" || exit 1
    
    show_message "Configuración inicial"
    read -p "Contraseña común para todas las herramientas: " COMMON_PASSWORD
    [ -z "$COMMON_PASSWORD" ] && { show_error "La contraseña no puede estar vacía"; exit 1; }
    
    read -p "Dominio base (ej: midominio.com): " BASE_DOMAIN
    [ -z "$BASE_DOMAIN" ] && { show_error "El dominio no puede estar vacío"; exit 1; }
    
    DEFAULT_SECRET_KEY=$(generate_random_key)
    read -p "Clave secreta de 32 caracteres [Enter para auto-generar]: " SECRET_KEY
    SECRET_KEY=${SECRET_KEY:-$DEFAULT_SECRET_KEY}
    
    if [ ${#SECRET_KEY} -ne 32 ]; then
        show_warning "Usando clave generada automáticamente"
        SECRET_KEY=$DEFAULT_SECRET_KEY
    fi
    
    show_success "Clave secreta: $SECRET_KEY"
    
    cat > "$DOCKER_DIR/.env.global" <<EOL
COMMON_PASSWORD=$COMMON_PASSWORD
BASE_DOMAIN=$BASE_DOMAIN
SECRET_KEY=$SECRET_KEY
EOL
    
    install_dependencies
    initialize_docker_swarm
    install_security_tools
    create_docker_networks
    
    install_docker_tool "traefik" "proxy" "create_traefik_stack"
    sleep 10
    
    install_docker_tool "portainer" "admin" "create_portainer_stack"
    install_docker_tool "redis" "redis" "create_redis_stack"
    sleep 15
    
    install_docker_tool "postgres" "postgres" "create_postgres_stack"
    sleep 15
    
    create_n8n_database
    install_docker_tool "n8n" "n8" "create_n8n_stack"
    
    cleanup 0
    
    echo -e "\n${GREEN}===========================================${NC}"
    echo -e "${GREEN}  ✅ Instalación Completada               ${NC}"
    echo -e "${GREEN}===========================================${NC}\n"
    
    echo "Accede a tus servicios:"
    for tool in traefik portainer redis postgres n8n; do
        subdomain_file="$DOCKER_DIR/$tool/.subdomain"
        if [ -f "$subdomain_file" ]; then
            subdomain=$(cat "$subdomain_file")
            echo "- ${tool^}: https://$subdomain.$BASE_DOMAIN"
        fi
    done
    
    echo -e "\n📋 Credenciales:"
    echo "   Usuario: admin"
    echo "   Contraseña: $COMMON_PASSWORD"
    echo "   Clave secreta: $SECRET_KEY"
    echo -e "\n📄 Guardado en: $DOCKER_DIR/.env.global"
}

main

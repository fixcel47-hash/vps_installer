#!/usr/bin/env bash
# =================================================================================
# UNIFIED INSTALLER SCRIPT (v5.0.0-MAJOR)
# - Fusión final y corrección de bugs:
# - run_command CORREGIDO: Sin spinner, muestra output de forma nativa.
# - Lógica de SUDO, Detección OS, Instalación Docker.
# - Lógica de Swarm, Seguridad (UFW, Fail2Ban, RKHunter), Redes.
# - Lógica de Descarga y Sanitización de YAMLs.
# - Inicialización robusta de Chatwoot DB.
# =================================================================================

set -euo pipefail

SCRIPT_VERSION="5.0.0-MAJOR"

# Colores para mensajes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Variables de entorno
SUDO=""
OS=""
DOCKER_DIR="/home/docker"
SCRIPT_PATH=$(readlink -f "$0")
TEMP_FILES=()
DOWNLOAD_TIMEOUT=30

# -------------------------------
# Configuración de URLs para descarga de Stacks (URLs del archivo combined_installer_v_2.sh)
# -------------------------------
declare -gA STACK_URLS=(
    [chatwoot]="https://github.com/user-attachments/files/22956465/chatwoot-stack.yml"
    [evoapi]="https://github.com/user-attachments/files/22956481/evoapi-stack.yml"
    [n8n]="https://github.com/user-attachments/files/22956487/n8n-stack.yml"
    [portainer]="https://github.com/user-attachments/files/22956492/portainer-stack.yml"
    [postgres]="https://github.com/user-attachments/files/22956495/postgres-stack.yml"
    [redis]="https://github.com/user-attachments/files/22956503/redis-stack.yml"
    [traefik]="https://github.com/user-attachments/files/22956506/traefik-stack.yml"
)

# Lista de herramientas para el flujo interactivo
AVAILABLE_TOOLS=("traefik" "portainer" "redis" "postgres" "n8n" "evoapi" "chatwoot")
SELECTED_TOOLS=("traefik" "portainer" "redis" "postgres" "n8n" "evoapi" "chatwoot")
DEFAULT_SUBDOMAINS=("proxy" "admin" "redis" "postgres" "n8" "evoapi" "chat")
declare -a CUSTOM_SUBDOMAINS

# -------------------------------
# Funciones de Mensajes y Utilidades
# -------------------------------

show_message() { echo -e "${BLUE}[INFO]${NC} $1"; }
show_error() { echo -e "${RED}[ERROR]${NC} $1"; }
show_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
show_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
register_temp_file() { TEMP_FILES+=("$1"); }
generate_random_key() { tr -dc 'A-Za-z0-9' </dev/urandom | head -c 32; }

# Función de ejecución de comandos simplificada y transparente (CORREGIDA)
run_command() {
    local cmd="$1"
    local msg="$2"
    
    show_message "$msg"
    
    local full_cmd
    # Se usa sudo solo para comandos del sistema que requieren privilegios
    if [ -n "$SUDO" ] && [[ "$cmd" != docker* ]] && [[ "$cmd" != *"$SUDO"* ]]; then
        full_cmd="$SUDO $cmd"
    else
        full_cmd="$cmd"
    fi
    
    echo -e "  -> Ejecutando: \033[0;33m$full_cmd\033[0m"

    # Ejecuta el comando directamente, mostrando el output de forma nativa.
    if $full_cmd; then
        show_success "Completado: $msg"
        return 0
    else
        local exit_status=$?
        show_error "Comando falló con código $exit_status: $full_cmd"
        return $exit_status
    fi
}

# Función de limpieza
cleanup() {
    local exit_code=$1
    local delete_stacks=${2:-false} 
    
    show_message "Realizando limpieza antes de salir..."
    
    if [ $exit_code -ne 0 ]; then
        show_error "Error detectado durante la instalación. Limpiando archivos temporales..."
    fi
    
    if [ ${#TEMP_FILES[@]} -gt 0 ]; then
        for file in "${TEMP_FILES[@]}"; do
            if [ -f "$file" ]; then
                $SUDO rm -f "$file"
            fi
        done
    fi
    
    if [ "$delete_stacks" = true ]; then
        show_message "Eliminando archivos de despliegue y configuración temporal..."
        for tool_name in "${SELECTED_TOOLS[@]}"; do
            local tool_dir="$DOCKER_DIR/$tool_name"
            $SUDO rm -f "$tool_dir/."subdomain
            $SUDO rm -f "$tool_dir/$tool_name-deploy.yml"
            $SUDO rm -f "$tool_dir/$tool_name-stack.yml"
            $SUDO rm -f "$tool_dir/$tool_name-stack.yml.raw"
            $SUDO rm -f "$tool_dir/$tool_name-stack.sanitized.yml"
        done
        $SUDO rm -f "$DOCKER_DIR/.env.global"
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
    
    show_message "Limpieza completada"
    
    if [ $exit_code -ne 0 ]; then
        show_error "La instalación ha fallado. Revise los logs para más información."
    else
        show_success "Instalación completada exitosamente"
    fi
}

# Configurar trampas para señales para limpiar antes de salir
trap 'cleanup 1 false; exit 1' SIGHUP SIGINT SIGQUIT SIGTERM
trap 'cleanup 1 false; exit 1' ERR

# -------------------------------
# Funciones de Instalación de Dependencias, Seguridad y Redes
# -------------------------------

configure_docker_logs() {
    local config_file="/etc/docker/daemon.json"
    show_message "Configurando límites de logs en Docker..."
    # Se usa $SUDO para escribir en /etc
    $SUDO cat > "$config_file" <<EOF
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

install_dependencies() {
    show_message "Verificando e instalando dependencias (curl, wget, jo, perl, Docker)..."
    
    run_command "apt-get update -y" "Actualizando lista de paquetes..."
    # Instalación de paquetes necesarios
    run_command "apt-get install -y ca-certificates curl gnupg lsb-release apt-transport-https software-properties-common jo perl" "Instalando utilidades y requisitos..."

    if ! command -v docker &> /dev/null; then
        echo "🐳 Instalando Docker..."
        
        # Uso de $SUDO para comandos que escriben en /etc
        $SUDO install -m 0755 -d /etc/apt/keyrings
        run_command "curl -fsSL https://download.docker.com/linux/$OS/gpg | $SUDO gpg --dearmor -o /etc/apt/keyrings/docker.gpg" "Descargando clave GPG de Docker..."
        
        # Configurar repositorio de Docker
        echo \
"deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/$OS \
$(lsb_release -cs) stable" | $SUDO tee /etc/apt/sources.list.d/docker.list > /dev/null
        
        run_command "apt-get update -y && apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin" "Instalando paquetes de Docker..."
    else
        show_success "Docker ya está instalado."
    fi

    # Iniciar y habilitar Docker (usando SUDO si es necesario)
    run_command "systemctl enable docker" "Habilitando servicio Docker..."
    run_command "systemctl start docker" "Iniciando servicio Docker..."
    
    configure_docker_logs
    
    show_success "Dependencias instaladas/verificadas."
}

initialize_docker_swarm() {
    show_message "Verificando estado de Docker Swarm..."
    if ! docker info 2>/dev/null | grep -q "Swarm: active"; then
        show_message "Iniciando Docker Swarm..."
        run_command "docker swarm init --advertise-addr \$(hostname -I | awk '{print \$1}')" "Inicializando Docker Swarm..."
        show_success "Docker Swarm inicializado correctamente"
    else
        show_message "Docker Swarm ya está activo"
    fi
}

install_server_tools() {
    show_message "Instalando herramientas de seguridad en el servidor..."
    
    run_command "apt-get install -y fail2ban && systemctl enable fail2ban && systemctl start fail2ban" "Instalando y activando Fail2Ban..."
    
    show_message "Instalando RKHunter..."
    run_command "echo 'postfix postfix/main_mailer_type select No configuration' | debconf-set-selections && apt-get install -y rkhunter" "Instalando RKHunter..."
    
    local config_file="/etc/rkhunter.conf"
    show_message "Configurando RKHunter..."
    run_command "$SUDO sed -i 's/^UPDATE_MIRRORS=.*/UPDATE_MIRRORS=1/' \"$config_file\" && \
                $SUDO sed -i 's/^MIRRORS_MODE=.*/MIRRORS_MODE=0/' \"$config_file\" && \
                $SUDO sed -i 's|^WEB_CMD=.*|WEB_CMD=\"\"|' \"$config_file\"" \
                "Aplicando configuración de RKHunter..."
    run_command "rkhunter --update" "Actualizando RKHunter..."
    run_command "rkhunter --propupd" "Actualizando base de datos de propiedades de RKHunter..."
    
    run_command "apt-get install -y chkrootkit" "Instalando CHKRootkit..."
    
    show_message "Configurando UFW Firewall..."
    run_command "apt-get install -y ufw" "Instalando UFW..."
    run_command "ufw allow ssh && ufw allow http && ufw allow https && echo 'y' | ufw enable" "Configurando y activando reglas básicas de UFW..."
    
    show_success "Herramientas de seguridad instaladas correctamente"
}

create_docker_networks() {
    show_message "Creando redes Docker para Swarm..."
    
    if ! docker network ls 2>/dev/null | grep -q "frontend"; then
        run_command "docker network create --driver overlay --attachable frontend" "Creando red frontend..."
        show_success "Red 'frontend' creada"
    else
        show_warning "La red 'frontend' ya existe"
    fi
    
    if ! docker network ls 2>/dev/null | grep -q "backend"; then
        run_command "docker network create --driver overlay --attachable backend" "Creando red backend..."
        show_success "Red 'backend' creada"
    else
        show_warning "La red 'backend' ya existe"
    fi
}

# -------------------------------
# Funciones de Descarga y Sanitización
# -------------------------------

download_file() {
    local url="$1" file="$2"
    if [[ -z "$url" ]]; then show_warning "URL vacía para $file"; return 1; fi
    show_message "Descargando $url -> $file"
    
    local download_cmd
    if command -v curl >/dev/null 2>&1; then
        download_cmd="curl --fail --location --max-time ${DOWNLOAD_TIMEOUT} -sS '$url' -o '$file'"
    elif command -v wget >/dev/null 2>&1; then
        download_cmd="wget -q --timeout=${DOWNLOAD_TIMEOUT} -O '$file' '$url'"
    else
        show_error "Ni curl ni wget están disponibles para la descarga."; return 3
    fi
    
    if ! eval "$download_cmd"; then
        show_error "Fallo al descargar $url"; return 2
    fi
    show_success "Descargado: $file"
    return 0
}

SENSITIVE_PATTERNS=(
  "API_TOKEN" "API_KEY" "SECRET" "PASSWORD" "DB_PASSWORD"
  "JWT" "ACCESS_TOKEN" "AUTH_TOKEN" "TOKEN:" "token:"
)

sanitize_yaml() {
    local infile="$1" outfile="$2"
    
    cp -f "$infile" "${infile}.raw"
    cp -f "$infile" "$outfile"
    
    show_message "Saneando $outfile de secretos evidentes..."

    # Reemplazar valores después de patrones sensibles (YAML y ENV style)
    for pat in "${SENSITIVE_PATTERNS[@]}"; do
        local escaped_pat=$(echo "$pat" | sed 's/[][\/.^$*+?(){}|-]/\\&/g')
        # YAML style: KEY: valor
        perl -0777 -pi -e "s/(${escaped_pat}\s*[:=]\s*)(\S+)/\1<REPLACE_ME>/ig" "$outfile" || true
        # ENV style: KEY=valor
        perl -0777 -pe "s/(${escaped_pat})=(\S+)/\1=<REPLACE_ME>/ig" -i "$outfile" || true
    done

    # Reemplazar cadenas largas de 32 o más caracteres que se parecen a claves
    perl -0777 -pi -e 's/([A-Z_]+)\s*[:=]\s*([A-Za-z0-9_\-\.\/]{32,})/\1: <REPLACE_ME>/g' "$outfile" || true

    show_success "Saneado: $outfile (copia original en ${infile}.raw)"
}

create_volume_directories() {
    local stack_file=$1
    local tool_name=$2

    show_message "Creando directorios para volúmenes de $tool_name..."

    # Patrón: device: /ruta/de/carpeta
    local volume_paths=$(grep -oP "device: \K/[^\s]+" "$stack_file" | sort | uniq)

    if [ -z "$volume_paths" ]; then
        show_message "No se encontraron rutas de volúmenes para $tool_name"
        return
    fi

    for path in $volume_paths; do
        run_command "mkdir -p \"$path\"" "Creando directorio $path..."
    done
}

initialize_chatwoot_database() {
    local tool_name="chatwoot"
    local subdomain=$1
    
    show_message "Inicializando base de datos de Chatwoot..."
    
    # 1. Crear el stack temporal de inicialización
    local init_stack_file="/tmp/chatwoot-init-stack.yml"
    
    cat > "$init_stack_file" << EOF
version: '3.8'

services:
  # Servicio PostgreSQL Temporal (usa el volumen del servicio final)
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
      placement:
        constraints:
          - node.role == manager
    networks:
      - backend

  # Servicio de Inicialización que ejecuta las migraciones
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
    
    # 2. Desplegar stack temporal
    run_command "docker stack deploy -c \"$init_stack_file\" chatwoot-init" "Desplegando stack temporal para inicializar DB..."
    
    show_message "Esperando a que el contenedor de inicialización de Chatwoot termine (máximo 5 minutos)..."
    
    local init_service_name="chatwoot-init_chatwoot-init"
    local max_wait=300
    local waited=0
    local init_status=""

    # 3. Monitorear el estado del servicio temporal de inicialización
    while [ $waited -lt $max_wait ]; do
        init_status=$(docker service ps -q "$init_service_name" --filter "desired-state=shutdown" --format "{{.CurrentState}}" 2>/dev/null | head -n 1)
        
        if [[ "$init_status" == *"Complete"* ]]; then
            show_success "Contenedor de inicialización de Chatwoot finalizado exitosamente."
            break
        fi

        if [[ "$init_status" == *"Failed"* ]]; then
            show_error "La inicialización de la DB de Chatwoot falló. Verifique logs."
            docker service logs "$init_service_name" 2>/dev/null | tail -20
            docker stack rm chatwoot-init >/dev/null 2>&1
            sleep 15
            return 1
        fi
        
        sleep 10
        waited=$((waited + 10))
        
        if [ $((waited % 60)) -eq 0 ]; then
            show_message "Inicializando DB... ($waited/$max_wait segundos)"
        fi
    done

    if [ $waited -ge $max_wait ]; then
        show_error "Timeout: El contenedor de inicialización de la base de datos de Chatwoot no terminó a tiempo."
        docker service logs "$init_service_name" 2>/dev/null | tail -20
        docker stack rm chatwoot-init >/dev/null 2>&1
        sleep 15
        return 1
    fi

    # 4. Limpiar stack
    show_message "Limpiando stack de inicialización..."
    docker stack rm chatwoot-init >/dev/null 2>&1
    sleep 15
    
    show_success "Base de datos de Chatwoot inicializada correctamente"
    return 0
}

install_docker_tool() {
    local tool_name=$1
    local default_subdomain=$2
    local tool_index=$3

    show_message "Configurando $tool_name..."
    local tool_dir="$DOCKER_DIR/$tool_name"
    run_command "mkdir -p \"$tool_dir\"" "Creando directorio de la herramienta..."
    
    # CRÍTICO: Entrar al directorio DESPUÉS de crearlo
    cd "$tool_dir" || {
        show_error "No se pudo acceder al directorio $tool_dir"
        exit 1
    }
    
    # Preguntas interactivas
    read -p "Ingrese el subdominio para $tool_name [$default_subdomain]: " SUBDOMAIN
    SUBDOMAIN=${SUBDOMAIN:-$default_subdomain}
    
    CUSTOM_SUBDOMAINS[$tool_index]=$SUBDOMAIN
    
    local subdomain_file="$tool_dir/.subdomain"
    echo "$SUBDOMAIN" > "$subdomain_file"
    register_temp_file "$subdomain_file"
    
    local stack_url="${STACK_URLS[$tool_name]}"
    local stack_file="$tool_dir/$tool_name-stack.yml"
    local deploy_file="$tool_dir/$tool_name-deploy.yml"

    # Descarga y Sanitización
    if ! download_file "$stack_url" "$stack_file"; then
        show_error "No se pudo descargar el archivo de stack para $tool_name"
        exit 1
    fi

    sanitize_yaml "$stack_file" "$deploy_file"
    register_temp_file "$deploy_file"
    
    # Reemplazo de variables
    sed -i "s|<REPLACE_ME>|$COMMON_PASSWORD|g" "$deploy_file"
    sed -i "s|REPLACE_PASSWORD|$COMMON_PASSWORD|g" "$deploy_file"
    sed -i "s|REPLACE_SUBDOMAIN|$SUBDOMAIN|g" "$deploy_file"
    sed -i "s|REPLACE_DOMAIN|$BASE_DOMAIN|g" "$deploy_file"
    sed -i "s|REPLACE_SECRET_KEY|$SECRET_KEY|g" "$deploy_file"

    create_volume_directories "$deploy_file" "$tool_name"
    
    # Inicialización especial de Chatwoot
    if [ "$tool_name" = "chatwoot" ]; then
        show_message "Chatwoot detectado - se requiere inicialización de base de datos"
        if ! initialize_chatwoot_database "$SUBDOMAIN"; then
            show_error "Error al inicializar la base de datos de Chatwoot"
            exit 1
        fi
    fi
    
    show_message "Desplegando $tool_name en Docker Swarm..."
    run_command "docker stack deploy -c \"$deploy_file\" $tool_name" "Desplegando $tool_name..."
    
    # Regresar al directorio principal
    cd "$DOCKER_DIR" || {
        show_error "No se pudo volver al directorio principal $DOCKER_DIR"
        exit 1
    }
}

# -------------------------------
# Flujo Principal 
# -------------------------------

# Bloque de chequeo inicial
echo "=== Instalador Universal v$SCRIPT_VERSION ==="
echo "Iniciando verificación del entorno..."

# 1. Detectar SUDO y permisos
if [ "$(id -u)" -ne 0 ]; then
    if ! command -v sudo >/dev/null 2>&1; then
        show_error "❌ No eres root y 'sudo' no está instalado. Instálalo o ejecuta como root."
        exit 1
    fi
    SUDO="sudo"
    show_message "➡️ Ejecutando con sudo..."
else
    SUDO=""
    show_message "➡️ Ejecutando como root..."
fi

# 2. Verificar conexión a internet
if ! curl -s --head --request GET -m 5 https://google.com >/dev/null 2>&1; then
    show_error "❌ No hay conexión a Internet. Revisa tu red antes de continuar."
    exit 1
fi

# 3. Detección de OS
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$ID
    show_message "Sistema detectado: $PRETTY_NAME"
else
    show_error "❌ No se pudo detectar el sistema operativo."
    exit 1
fi


main() {
    show_message "Iniciando la instalación automatizada de herramientas Docker (v$SCRIPT_VERSION)..."
    
    # 1. Crear directorio y entrar
    run_command "mkdir -p \"$DOCKER_DIR\"" "Creando directorio principal de Docker..."
    cd "$DOCKER_DIR" || { 
        show_error "No se pudo acceder al directorio $DOCKER_DIR. Por favor, asegúrese de que el sistema de archivos es accesible."
        exit 1
    }

    show_message "Configuración de credenciales"
    read -p "Ingrese la contraseña común para todas las herramientas: " COMMON_PASSWORD
    if [ -z "$COMMON_PASSWORD" ]; then show_error "La contraseña no puede estar vacía"; exit 1; fi

    read -p "Ingrese el dominio base (ejemplo: midominio.com): " BASE_DOMAIN
    if [ -z "$BASE_DOMAIN" ]; then show_error "El dominio no puede estar vacío"; exit 1; fi

    DEFAULT_SECRET_KEY=$(generate_random_key)
    read -p "Ingrese una clave secreta de 32 caracteres (Enter para usar una generada): " SECRET_KEY
    SECRET_KEY=${SECRET_KEY:-$DEFAULT_SECRET_KEY}

    if [ ${#SECRET_KEY} -ne 32 ]; then
        show_warning "La clave proporcionada no tiene 32 caracteres. Se utilizará una clave generada automáticamente."
        SECRET_KEY=$DEFAULT_SECRET_KEY
    fi

    show_message "Se utilizará la clave secreta: $SECRET_KEY"

    # Guardar variables globales
    env_global_file="$DOCKER_DIR/.env.global"
    $SUDO cat > "$env_global_file" << EOL
COMMON_PASSWORD=$COMMON_PASSWORD
BASE_DOMAIN=$BASE_DOMAIN
SECRET_KEY=$SECRET_KEY
EOL
    register_temp_file "$env_global_file"

    # 2. Instalación de dependencias, Swarm, Seguridad y Redes
    install_dependencies
    initialize_docker_swarm
    install_server_tools
    create_docker_networks

    # 3. Instalar herramientas
    for i in "${!SELECTED_TOOLS[@]}"; do CUSTOM_SUBDOMAINS[$i]=""; done

    show_message "Instalando servicios en orden de dependencias..."
    
    INSTALL_ORDER=("traefik" "redis" "postgres" "portainer" "n8n" "evoapi" "chatwoot")
    
    for tool_name in "${INSTALL_ORDER[@]}"; do
        default_subdomain=""
        tool_index=-1
        for j in "${!AVAILABLE_TOOLS[@]}"; do
            if [ "${AVAILABLE_TOOLS[$j]}" = "$tool_name" ]; then
                default_subdomain="${DEFAULT_SUBDOMAINS[$j]}"
                tool_index=$j
                break
            fi
        done
        
        if [ $tool_index -ge 0 ]; then
            install_docker_tool "$tool_name" "$default_subdomain" "$tool_index"
            
            # Pausa entre instalaciones
            if [ "$tool_name" = "postgres" ] || [ "$tool_name" = "redis" ]; then
                show_message "Esperando a que $tool_name se estabilice (15 segundos)..."
                sleep 15
            fi
        fi
    done

    # 4. Mostrar URLs y finalizar
    show_success "¡Instalación completada!"
    echo ""
    echo "Accede a tus servicios en los siguientes URLs (usando HTTPS si Traefik está configurado correctamente):"
    
    for i in "${!SELECTED_TOOLS[@]}"; do
        tool_name="${SELECTED_TOOLS[$i]}"
        tool_index=-1
        for j in "${!AVAILABLE_TOOLS[@]}"; do
            if [ "${AVAILABLE_TOOLS[$j]}" = "$tool_name" ]; then
                tool_index=$j
                break
            fi
        done

        if [ $tool_index -ge 0 ]; then
            local subdomain="${CUSTOM_SUBDOMAINS[$tool_index]}"
            echo "- ${tool_name^}: https://$subdomain.$BASE_DOMAIN"
        fi
    done
    
    echo ""
    echo "Información de credenciales:"
    echo "- Contraseña común: $COMMON_PASSWORD"
    echo "- Clave secreta: $SECRET_KEY"
    echo ""
    echo "Esta información se ha guardado en: $DOCKER_DIR/.env.global"

    cleanup 0 true
}

# Ejecutar función principal
main "$@"

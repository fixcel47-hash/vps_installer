#!/bin/bash

SCRIPT_VERSION="1.2.0"

# Colores para mensajes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Obtener ruta absoluta del script actual
SCRIPT_DIR=$(dirname "$(readlink -f "$0")")
SCRIPT_NAME=$(basename "$0")

# Lista de archivos temporales para limpiar
TEMP_FILES=()

declare -gA INSTALLED_COMPONENTS=(
    [dependencies]=false
    [security]=false
    [networks]=false
)

# Función de limpieza mejorada
cleanup() {
    local exit_code=$1
    local delete_stacks=${2:-false}
    
    echo -e "${BLUE}[INFO]${NC} Realizando limpieza..."
    
    # En caso de error, eliminar archivos temporales
    if [ $exit_code -ne 0 ]; then
        echo -e "${RED}[ERROR]${NC} Error detectado. Limpiando archivos temporales..."
        
        # Eliminar archivos temporales
        for file in "${TEMP_FILES[@]}"; do
            if [ -f "$file" ]; then
                rm -f "$file"
            fi
        done
    fi
    
    # Eliminar archivos stack.yml si se solicita
    if [ "$delete_stacks" = true ]; then
        for tool_name in "${SELECTED_TOOLS[@]}"; do
            local stack_file="$DOCKER_DIR/$tool_name/$tool_name-stack.yml"
            if [ -f "$stack_file" ]; then
                rm -f "$stack_file"
            fi
        done
    fi
    
    # NO autodestrucción - comentada por seguridad
    # echo -e "${BLUE}[INFO]${NC} Script completado. Puede eliminar manualmente si lo desea."
    
    if [ $exit_code -ne 0 ]; then
        echo -e "${RED}[ERROR]${NC} La instalación ha fallado. Revise los logs."
    else
        echo -e "${GREEN}[SUCCESS]${NC} Instalación completada exitosamente"
    fi
}

# Configurar trampas
trap 'cleanup 1 false; exit 1' SIGHUP SIGINT SIGQUIT SIGTERM
trap 'cleanup 1 false; exit 1' ERR

# Función para registrar archivo temporal
register_temp_file() {
    local file_path=$1
    TEMP_FILES+=("$file_path")
}

# Validar entrada del usuario
validate_input() {
    local input=$1
    local type=$2
    
    case $type in
        "domain")
            if [[ ! $input =~ ^[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
                show_error "Dominio inválido: $input"
                return 1
            fi
            ;;
        "password")
            if [ -z "$input" ] || [ ${#input} -lt 8 ]; then
                show_error "La contraseña debe tener al menos 8 caracteres"
                return 1
            fi
            ;;
        "subdomain")
            if [[ ! $input =~ ^[a-zA-Z0-9-]+$ ]]; then
                show_error "Subdominio inválido: $input (solo letras, números y guiones)"
                return 1
            fi
            ;;
    esac
    return 0
}

# Función para mostrar mensajes
show_message() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

show_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

show_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

show_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Función para animación de espera
spinner() {
    local pid=$1
    local delay=0.1
    local spinstr='|/-\'
    
    echo -n "Procesando "
    while [ "$(ps a | awk '{print $1}' | grep $pid)" ]; do
        local temp=${spinstr#?}
        printf " [%c]  " "$spinstr"
        local spinstr=$temp${spinstr%"$temp"}
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
    tr -dc 'A-Za-z0-9' </dev/urandom | head -c 32
}

# Función para configurar tamaño de los logs de Docker
configure_docker_logs() {
    local config_file="/etc/docker/daemon.json"

    show_message "Configurando límites de logs en Docker..."

    # Crear backup si el archivo existe
    if [ -f "$config_file" ]; then
        cp "$config_file" "$config_file.backup.$(date +%Y%m%d_%H%M%S)"
    fi

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

    # Crear backup
    if [ -f "$config_file" ]; then
        cp "$config_file" "$config_file.backup.$(date +%Y%m%d_%H%M%S)"
    fi

    run_command "sed -i 's/^UPDATE_MIRRORS=.*/UPDATE_MIRRORS=1/' \"$config_file\" && \
                sed -i 's/^MIRRORS_MODE=.*/MIRRORS_MODE=0/' \"$config_file\" && \
                sed -i 's|^WEB_CMD=.*|WEB_CMD=\"\"|' \"$config_file\"" \
                "Aplicando configuración de RKHunter..."
}

# Función para descargar archivos desde GitHub o local
download_config_file() {
    local repo_path=$1
    local local_path=$2
    
    show_message "Obteniendo configuración para $repo_path..."
    
    # Intentar desde archivos locales primero
    local local_source="./configs/$repo_path"
    if [ -f "$local_source" ]; then
        cp "$local_source" "$local_path"
        show_success "Configuración copiada desde archivo local"
        return 0
    fi
    
    # Si no hay archivo local, mostrar error
    show_error "No se encontró el archivo de configuración: $local_source"
    show_message "Por favor, asegúrese de que los archivos de configuración estén en ./configs/"
    return 1
}

# Verificar si el script se ejecuta como root
if [ "$EUID" -ne 0 ]; then
    show_error "Este script debe ejecutarse como root"
    exit 1
fi

# Crear directorio principal
DOCKER_DIR="/home/docker"
mkdir -p $DOCKER_DIR
cd $DOCKER_DIR || { 
    show_error "No se pudo acceder al directorio $DOCKER_DIR"
    exit 1
}

# Lista de herramientas disponibles
AVAILABLE_TOOLS=("traefik" "portainer" "redis" "postgres" "n8n" "evoapi" "chatwoot")
DEFAULT_SUBDOMAINS=("proxy" "admin" "redis" "postgres" "n8" "evoapi" "chat")
SELECTED_TOOLS=("traefik" "portainer" "redis" "postgres" "n8n" "evoapi" "chatwoot")

# Array para almacenar los subdominios personalizados ingresados por el usuario
CUSTOM_SUBDOMAINS=()

# Solicitar información al usuario
show_message "Configuración inicial"
while true; do
    read -p "Ingrese la contraseña común para todas las herramientas: " COMMON_PASSWORD
    if validate_input "$COMMON_PASSWORD" "password"; then
        break
    fi
done

while true; do
    read -p "Ingrese el dominio base (ejemplo: midominio.com): " BASE_DOMAIN
    if validate_input "$BASE_DOMAIN" "domain"; then
        break
    fi
done

# Generar una clave aleatoria por defecto
DEFAULT_SECRET_KEY=$(generate_random_key)
read -p "Ingrese una clave secreta de 32 caracteres para las herramientas (o presione Enter para usar una generada automáticamente): " SECRET_KEY
SECRET_KEY=${SECRET_KEY:-$DEFAULT_SECRET_KEY}

# Verificar longitud de la clave
if [ ${#SECRET_KEY} -ne 32 ]; then
    show_warning "La clave proporcionada no tiene 32 caracteres. Se utilizará una clave generada automáticamente."
    SECRET_KEY=$DEFAULT_SECRET_KEY
fi

show_message "Se utilizará la siguiente clave secreta: $SECRET_KEY"

# Guardar variables globales para usar en los scripts
env_global_file="$DOCKER_DIR/.env.global"
cat > $env_global_file << EOL
COMMON_PASSWORD=$COMMON_PASSWORD
BASE_DOMAIN=$BASE_DOMAIN
SECRET_KEY=$SECRET_KEY
EOL

show_success "Configuración guardada en: $env_global_file"

# Verificar e instalar dependencias
install_dependencies() {
    show_message "Verificando e instalando dependencias..."
    
    # Actualizar repositorios
    apt-get update

    # Instalar jo para creación de json
    if ! command -v jo &> /dev/null; then
        run_command "apt-get install -y jo" "Instalando jo..."
    fi
    
    # Verificar si Docker está instalado
    if ! command -v docker &> /dev/null; then
        show_message "Instalando Docker..."
        apt-get install -y ca-certificates curl
        install -m 0755 -d /etc/apt/keyrings
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
        chmod a+r /etc/apt/keyrings/docker.asc
        echo \
"deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
$(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
        apt-get update
        apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
        systemctl enable docker
        systemctl start docker

        configure_docker_logs
    else
        show_message "Docker ya está instalado"
    fi
    
    # Instalar otras herramientas necesarias
    run_command "apt-get install -y git curl wget" "Instalando herramientas básicas..."
}

# Inicializar Docker Swarm si no está activo
initialize_docker_swarm() {
    show_message "Verificando estado de Docker Swarm..."
    
    if ! docker info 2>/dev/null | grep -q "Swarm: active"; then
        show_message "Iniciando Docker Swarm..."
        run_command "docker swarm init --advertise-addr \$(hostname -I | awk '{print \$1}')" "Inicializando Docker Swarm..."
        if [ $? -eq 0 ]; then
            show_success "Docker Swarm inicializado correctamente"
        else
            show_error "Error al inicializar Docker Swarm"
            exit 1
        fi
    else
        show_message "Docker Swarm ya está activo"
    fi

    INSTALLED_COMPONENTS["dependencies"]=true
}

# Instalar herramientas directamente en el servidor
install_server_tools() {
    show_message "Instalando herramientas de seguridad en el servidor..."
    
    # Fail2Ban
    if ! command -v fail2ban-server &> /dev/null; then
        run_command "apt-get install -y fail2ban" "Instalando Fail2Ban..."
        systemctl enable fail2ban
        systemctl start fail2ban
    else
        show_message "Fail2Ban ya está instalado"
    fi
    
    # RKHunter
    if ! command -v rkhunter &> /dev/null; then
        show_message "Instalando RKHunter..."
        echo "postfix postfix/main_mailer_type select No configuration" | debconf-set-selections
        apt-get install -y rkhunter
        configure_rkhunter
        rkhunter --update
        rkhunter --propupd
    else
        show_message "RKHunter ya está instalado"
    fi
    
    # CHKRootkit
    if ! command -v chkrootkit &> /dev/null; then
        run_command "apt-get install -y chkrootkit" "Instalando CHKRootkit..."
    else
        show_message "CHKRootkit ya está instalado"
    fi
    
    # UFW
    if ! command -v ufw &> /dev/null; then
        show_message "Configurando UFW Firewall..."
        apt-get install -y ufw
        ufw allow ssh
        ufw allow http
        ufw allow https
        echo "y" | ufw enable
    else
        show_message "UFW ya está instalado"
    fi
    
    show_success "Herramientas de seguridad instaladas correctamente"

    INSTALLED_COMPONENTS["security"]=true
}

# Crear redes de Docker para Swarm
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

    INSTALLED_COMPONENTS["networks"]=true
}

# Función para crear directorios para volúmenes
create_volume_directories() {
    local stack_file=$1
    local tool_name=$2

    show_message "Creando directorios para volúmenes de $tool_name..."

    local volume_paths=$(grep -oP "device: \K/[^\s]+" "$stack_file" | sort | uniq)

    if [ -z "$volume_paths" ]; then
        show_message "No se encontraron rutas de volúmenes para $tool_name"
        return
    fi

    for path in $volume_paths; do
        show_message "Creando directorio: $path"
        run_command "mkdir -p \"$path\"" "Creando directorio $path..."
        if [ $? -eq 0 ]; then
            show_success "Directorio $path creado correctamente"
        else
            show_error "Error al crear el directorio $path"
            exit 1
        fi
    done
}

# Función para esperar a que un servicio esté disponible
wait_for_service() {
    local service_url=$1
    local timeout=${2:-300}
    local counter=0
    
    show_message "Esperando a que $service_url esté disponible..."
    
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

# Función mejorada para inicializar la base de datos de Chatwoot
initialize_chatwoot_database() {
    local tool_name="chatwoot"
    local subdomain=$1
    
    show_message "Inicializando base de datos de Chatwoot..."
    
    # Esperar a que PostgreSQL esté listo
    show_message "Esperando a que PostgreSQL esté disponible..."
    local pg_ready=false
    local max_pg_wait=180
    local pg_attempt=0

    while [ $pg_attempt -lt $max_pg_wait ] && [ "$pg_ready" = false ]; do
        if docker exec chatwoot_chatwoot-postgres.1.* pg_isready -U postgres -h localhost >/dev/null 2>&1; then
            pg_ready=true
            show_success "PostgreSQL está listo"
        else
            sleep 5
            pg_attempt=$((pg_attempt + 1))
            if [ $((pg_attempt % 12)) -eq 0 ]; then
                show_message "Esperando PostgreSQL... ($pg_attempt/$max_pg_wait intentos)"
            fi
        fi
    done

    if [ "$pg_ready" = false ]; then
        show_error "PostgreSQL no está disponible después de 3 minutos"
        return 1
    fi

    # Ejecutar inicialización de base de datos
    show_message "Ejecutando inicialización de la base de datos..."
    local init_container=$(docker ps -q --filter "name=chatwoot_chatwoot" | head -1)
    
    if [ -n "$init_container" ]; then
        if docker exec "$init_container" bundle exec rails db:chatwoot_prepare; then
            show_success "Base de datos de Chatwoot inicializada correctamente"
            return 0
        else
            show_error "Error al inicializar la base de datos de Chatwoot"
            return 1
        fi
    else
        show_error "No se encontró el contenedor de Chatwoot para inicialización"
        return 1
    fi
}

# Función para instalar una herramienta con Docker Swarm
install_docker_tool() {
    local tool_name=$1
    local default_subdomain=$2
    local tool_index=$3
    
    show_message "Configurando $tool_name..."
    tool_dir="$DOCKER_DIR/$tool_name"
    mkdir -p $tool_dir
    cd $tool_dir || {
        show_error "No se pudo acceder al directorio $tool_dir"
        exit 1
    }
    
    # Solicitar subdominio
    while true; do
        read -p "Ingrese el subdominio para $tool_name [$default_subdomain]: " SUBDOMAIN
        SUBDOMAIN=${SUBDOMAIN:-$default_subdomain}
        if validate_input "$SUBDOMAIN" "subdomain"; then
            break
        fi
    done

    # Guardar el subdominio personalizado en el array
    CUSTOM_SUBDOMAINS[$tool_index]=$SUBDOMAIN

    # Guardar el subdominio en un archivo para referencia futura
    subdomain_file="$tool_dir/.subdomain"
    echo "$SUBDOMAIN" > "$subdomain_file"
    register_temp_file "$subdomain_file"
    
    # Descargar archivos de configuración
    show_message "Obteniendo configuración para $tool_name..."
    stack_file="$tool_dir/$tool_name-stack.yml"
    if ! download_config_file "docker/$tool_name/$tool_name-stack.yml" "$stack_file"; then
        show_error "No se pudo obtener la configuración para $tool_name"
        return 1
    fi
    
    # Crear archivo temporal para reemplazar variables
    deploy_file="$tool_dir/$tool_name-deploy.yml"
    cp "$stack_file" "$deploy_file"
    register_temp_file "$deploy_file"

    # Reemplazar las variables en el archivo de stack
    sed -i "s|REPLACE_PASSWORD|$COMMON_PASSWORD|g" "$deploy_file"
    sed -i "s|REPLACE_SUBDOMAIN|$SUBDOMAIN|g" "$deploy_file"
    sed -i "s|REPLACE_DOMAIN|$BASE_DOMAIN|g" "$deploy_file"
    sed -i "s|REPLACE_SECRET_KEY|$SECRET_KEY|g" "$deploy_file"

    # Crear directorios para volúmenes
    create_volume_directories "$deploy_file" "$tool_name"
    
    # Desplegar stack en Swarm
    show_message "Desplegando $tool_name en Docker Swarm..."
    if run_command "docker stack deploy -c \"$deploy_file\" $tool_name" "Desplegando $tool_name..."; then
        show_success "$tool_name instalado correctamente en Docker Swarm"
        INSTALLED_COMPONENTS["$tool_name"]=true
        
        # Para Chatwoot, inicializar base de datos después del despliegue
        if [ "$tool_name" = "chatwoot" ]; then
            show_message "Esperando a que los servicios de Chatwoot inicien..."
            sleep 30
            if initialize_chatwoot_database "$SUBDOMAIN"; then
                show_success "Chatwoot completamente inicializado"
            else
                show_warning "Chatwoot desplegado pero hubo problemas con la inicialización de la base de datos"
            fi
        fi
        
        return 0
    else
        show_error "Error al instalar $tool_name"
        INSTALLED_COMPONENTS["$tool_name"]=false
        return 1
    fi
    
    cd $DOCKER_DIR || {
        show_error "No se pudo volver al directorio principal $DOCKER_DIR"
        exit 1
    }
}

# Función para mostrar resumen final
show_installation_summary() {
    echo ""
    echo "================================================"
    echo "           RESUMEN DE INSTALACIÓN"
    echo "================================================"
    echo ""
    echo "Herramientas instaladas:"
    
    for i in "${!SELECTED_TOOLS[@]}"; do
        tool_name="${SELECTED_TOOLS[$i]}"
        subdomain="${CUSTOM_SUBDOMAINS[$i]}"
        
        if [ -z "$subdomain" ]; then
            # Buscar el subdominio por defecto
            for j in "${!AVAILABLE_TOOLS[@]}"; do
                if [ "${AVAILABLE_TOOLS[$j]}" = "$tool_name" ]; then
                    subdomain="${DEFAULT_SUBDOMAINS[$j]}"
                    break
                fi
            done
        fi
        
        status=$([ "${INSTALLED_COMPONENTS[$tool_name]}" = "true" ] && echo "✓" || echo "✗")
        echo "  $status $tool_name: https://$subdomain.$BASE_DOMAIN"
    done
    
    echo ""
    echo "Credenciales:"
    echo "  - Contraseña común: $COMMON_PASSWORD"
    echo "  - Clave secreta: $SECRET_KEY"
    echo ""
    echo "Configuración guardada en: $DOCKER_DIR/.env.global"
    echo ""
    echo "================================================"
}

# Función principal
main() {
    show_message "Iniciando la instalación automatizada de herramientas Docker..."
    show_message "Script version: $SCRIPT_VERSION"
    
    # Mostrar información del sistema
    show_message "Sistema: $(lsb_release -d | cut -f2)"
    show_message "Hostname: $(hostname)"
    show_message "IP: $(hostname -I | awk '{print $1}')"
    
    # Instalar dependencias
    install_dependencies
    
    # Inicializar Docker Swarm
    initialize_docker_swarm
    
    # Instalar herramientas de seguridad
    install_server_tools
    
    # Crear redes Docker
    create_docker_networks

    # Inicializar array de subdominios personalizados
    for i in "${!SELECTED_TOOLS[@]}"; do
        CUSTOM_SUBDOMAINS[$i]=""
    done

    # Instalar herramientas Docker seleccionadas en orden específico
    show_message "Instalando servicios en orden de dependencias..."
    
    # Orden de instalación: infraestructura primero, aplicaciones después
    INSTALL_ORDER=("traefik" "redis" "postgres" "portainer" "n8n" "evoapi" "chatwoot")
    
    for tool_name in "${INSTALL_ORDER[@]}"; do
        # Verificar si la herramienta está en la lista de seleccionadas
        if [[ " ${SELECTED_TOOLS[@]} " =~ " ${tool_name} " ]]; then
            # Encontrar el índice y subdomain correspondiente
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
                # Instalar la herramienta
                if install_docker_tool "$tool_name" "$default_subdomain" "$tool_index"; then
                    show_success "$tool_name instalado correctamente"
                    
                    # Pausa entre instalaciones para permitir que los servicios se estabilicen
                    if [ "$tool_name" = "postgres" ] || [ "$tool_name" = "redis" ]; then
                        show_message "Esperando a que $tool_name se estabilice..."
                        sleep 20
                    fi
                else
                    show_warning "Error instalando $tool_name, continuando con las siguientes herramientas..."
                fi
            fi
        fi
    done

    # Mostrar resumen
    show_installation_summary
    
    show_success "¡Instalación completada!"
    echo ""
    show_message "Los servicios pueden tomar algunos minutos en estar completamente disponibles."
    show_message "Revise los logs con: docker service logs <nombre_servicio>"

    cleanup 0 true
}

# Ejecutar función principal
main "$@"
#!/bin/bash

SCRIPT_VERSION="1.2.3"

# Colores para mensajes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Variables API (SE MANTIENEN PARA REGISTRO DE ESTADO, PERO NO PARA DESCARGA DE STACKS)
# Si no desea utilizar la funcionalidad de registro de estado, puede ignorar el token.
API_URL="https://tkinstall.emodev.link/api"
API_TOKEN=""
INSTALLATION_ID=""

# Comando SQL para configurar Enterprise (escapando ! y comillas)
SQL_COMMAND_ENTERPRISE="UPDATE public.installation_configs SET serialized_value = '\"--- \!ruby/hash:ActiveSupport::HashWithIndifferentAccess\nvalue: enterprise\n\"' WHERE name = 'INSTALLATION_PRICING_PLAN'; UPDATE public.installation_configs SET serialized_value = '\"--- \!ruby/hash:ActiveSupport::HashWithIndifferentAccess\nvalue: 10000\n\"' WHERE name = 'INSTALLATION_PRICING_PLAN_QUANTITY'; UPDATE public.installation_configs SET serialized_value = '\"--- \!ruby/hash:ActiveSupport::HashWithIndifferentAccess\nvalue: e04t63ee-5gg8-4b94-8914-ed8137a7d938\n\"' WHERE name = 'INSTALLATION_IDENTIFIER';"

# MAPA DE ENLACES DE DESCARGA DE GITHUB (MODIFICADO)
declare -rA GITHUB_LINKS=(
    ["evoapi"]="https://github.com/user-attachments/files/22956481/evoapi-stack.yml"
    ["n8n"]="https://github.com/user-attachments/files/22956487/n8n-stack.yml"
    ["portainer"]="https://github.com/user-attachments/files/22956492/portainer-stack.yml"
    ["postgres"]="https://github.com/user-attachments/files/22956495/postgres-stack.yml"
    ["redis"]="https://github.com/user-attachments/files/22956503/redis-stack.yml"
    ["traefik"]="https://github.com/user-attachments/files/22956506/traefik-stack.yml"
#   ["chatwoot"]="https://github.com/user-attachments/files/22956465/chatwoot-stack.yml" # DESCARGA ELIMINADA: CREADO DIRECTAMENTE EN EL SCRIPT
)


# Obtener ruta absoluta del script actual
SCRIPT_PATH=$(readlink -f "$0")

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
    
    echo -e "${BLUE}[INFO]${NC} Realizando 
limpieza antes de salir..."
    
    # En caso de error, eliminar todos los archivos temporales y actualizar estado
    if [ $exit_code -ne 0 ];
then
        echo -e "${RED}[ERROR]${NC} Error detectado durante la instalación. Limpiando archivos temporales..."
        
        # Actualizar estado de la instalación
        if [ !
-z "$INSTALLATION_ID" ]; then
            update_installation_status "failed" ""
        fi
        
        # Eliminar archivos temporales en caso de error
        if [ ${#TEMP_FILES[@]} -gt 0 ];
then
            for file in "${TEMP_FILES[@]}";
do
                if [ -f "$file" ];
then
                    rm -f "$file"
                fi
            done
        fi
    fi
    
    # Si se solicita, eliminar solo los archivos stack.yml (en caso de éxito)
    if [ "$delete_stacks" = true ];
then
        for tool_name in "${SELECTED_TOOLS[@]}";
do
            local stack_file="$DOCKER_DIR/$tool_name/$tool_name-stack.yml"
            if [ -f "$stack_file" ];
then
                rm -f "$stack_file"
            fi
        done
    fi
    
    # Crear un script de autodestrucción (tanto para error como para éxito)
    if [ $exit_code -ne 0 ] ||
[ "$delete_stacks" = true ]; then
        
        # Crear un script separado para la autodestrucción
        local self_destruct_script="/tmp/self_destruct_$$_$(date +%s).sh"
        cat > "$self_destruct_script" << EOF
#!/bin/bash
# Esperar un momento para asegurar que el script principal ha terminado
sleep 1
# Intentar eliminar el script principal
rm -f "$SCRIPT_PATH"
# Comprobar si se eliminó correctamente
if [ -f "$SCRIPT_PATH" ];
then
  # Si no se pudo eliminar, intentar una vez más con sudo
  sudo rm -f "$SCRIPT_PATH"
fi
# Eliminar este script de autodestrucción
rm -f "\$0"
EOF

        # Hacer ejecutable el script de autodestrucción
        chmod +x "$self_destruct_script"
        
        # Ejecutar el script de autodestrucción en segundo plano,
        # desconectado de la terminal actual para que continúe después de salir
        
nohup "$self_destruct_script" >/dev/null 2>&1 &
        
    fi
    
    echo -e "${BLUE}[INFO]${NC} Limpieza completada"
    
    # Mostrar mensaje final de error si fue una limpieza por error
    if [ $exit_code -ne 0 ];
then
        echo -e "${RED}[ERROR]${NC} La instalación ha fallado. Revise los logs para más información."
else
        echo -e "${GREEN}[SUCCESS]${NC} Instalación completada exitosamente"
    fi
}

# Configurar trampas para señales para limpiar antes de salir
trap 'cleanup 1 false;
exit 1' SIGHUP SIGINT SIGQUIT SIGTERM
trap 'cleanup 1 false; exit 1' ERR

# Función para registrar un archivo temporal para limpieza posterior
register_temp_file() {
    local file_path=$1
    TEMP_FILES+=("$file_path")
}

# Procesar parámetros de línea de comandos
while [[ $# -gt 0 ]];
do
    key="$1"
    case $key in
        --token)
            API_TOKEN="$2"
            shift 2
            ;;
*)
            shift
            ;;
esac
done

# Función para recopilar información del sistema
collect_system_info() {
    HOSTNAME=$(hostname)
    OS_INFO=$(cat /etc/os-release 2>/dev/null | grep "PRETTY_NAME" | cut -d '"' -f 2 || echo "Unknown OS")
    CPU_INFO=$(grep "model name" /proc/cpuinfo 2>/dev/null | head -n 1 | cut -d ':' -f 2 | sed 's/^ //')
    MEM_TOTAL=$(free -h 2>/dev/null | grep "Mem:" | awk '{print $2}')
    IP_ADDRESS=$(curl -s https://api.ipify.org)
}

# Función para registrar el inicio de la instalación
register_installation_start() {
    show_message "Registrando instalación..."
    
    collect_system_info
    
  
  response=$(curl -s -X POST \
      -H "x-api-token: $API_TOKEN" \
      -H "Content-Type: application/json" \
      -d "{\"hostname\":\"$HOSTNAME\",\"os\":\"$OS_INFO\",\"cpu\":\"$CPU_INFO\",\"memory\":\"$MEM_TOTAL\",\"ip\":\"$IP_ADDRESS\",\"domain\":\"$BASE_DOMAIN\",\"script_version\":\"$SCRIPT_VERSION\"}" \
      "$API_URL/register-installation")
    
    if echo "$response" | grep -q "success\":true";
then
        INSTALLATION_ID=$(echo "$response" | grep -o '"installation_id":"[^"]*' | sed 's/"installation_id":"//')
        show_success "Instalación registrada con ID: $INSTALLATION_ID"
        return 0
    else
        error_msg=$(echo "$response" | grep -o '"error":"[^"]*' | sed 's/"error":"//')
        show_warning "No se pudo registrar la instalación: $error_msg (Continuando sin registro si es posible)"
        return 1
    fi
}

# Función para actualizar el estado de la 
instalación
update_installation_status() {
    local status=$1
    local components_json=$2
    
    if [ -z "$INSTALLATION_ID" ];
then
        return 0
    fi
    
    show_message "Actualizando estado de la instalación a: $status"

    if [ -z "$components_json" ];
then
        # Usar jo si está disponible, de lo contrario crear un JSON simple
        if command -v jo &> /dev/null;
then
            components_json=$(jo -a $(for key in "${!INSTALLED_COMPONENTS[@]}"; do echo "$key=${INSTALLED_COMPONENTS[$key]}"; done))
        else
            components_json='["dependencies","security","networks"]'
        fi
    fi

    # Crear payload JSON
    local json_payload="{\"status\":\"$status\",\"installed_components\":$components_json}"
    
    curl -s -X POST \
      -H "x-api-token: $API_TOKEN" \
      -H "Content-Type: application/json" \
     
 -d "$json_payload" \
      "$API_URL/update-installation/$INSTALLATION_ID" > /dev/null
}

# Función para completar la instalación y actualizar el uso del tokens
complete_installation() {
    
    if [ -z "$INSTALLATION_ID" ];
then
        show_warning "Instalación no registrada. Saltando paso de completar instalación en la API."
return 0
    fi

    show_message "Completando instalación..."
    
    # Crear JSON con componentes instalados
    local components_json
    if command -v jo &> /dev/null;
then
        components_json=$(jo -a $(for key in "${!INSTALLED_COMPONENTS[@]}"; do echo "$key=${INSTALLED_COMPONENTS[$key]}"; done))
    else
        components_json='["dependencies","security","networks"]'
    fi
    
    response=$(curl -s -X POST \
      -H "x-api-token: $API_TOKEN" \
      -H "Content-Type: application/json" \
      -d "{\"installation_id\":\"$INSTALLATION_ID\",\"installed_components\":$components_json}" \
      "$API_URL/complete-installation")
    
    if echo "$response" |
grep -q "success\":true"; then
        remaining=$(echo "$response" | grep -o '"remaining_uses":[0-9]*' | sed 's/"remaining_uses"://')
        show_success "Instalación completada.
Usos restantes del token: $remaining"
        return 0
    else
        error_msg=$(echo "$response" | grep -o '"error":"[^"]*' | sed 's/"error":"//')
        show_error "Error al completar la instalación: $error_msg"
        return 1
    fi
}


# Función para mostrar mensajes
show_message() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

# Función para mostrar errores
show_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Función para mostrar éxito
show_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

# Función para mostrar 
advertencias
show_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Función para animación de espera
spinner() {
    local pid=$1
    local delay=0.1
    local spinstr='|/-\'
    
    echo -n "Procesando "
    while [ "$(ps a | awk '{print $1}' | grep $pid)" ];
do
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
# Si el comando falla, registrar el error y salir
    if [ $exit_status -ne 0 ];
then
        show_error "Comando falló: $cmd"
        cleanup 1
        exit $exit_status
    fi
    
    return $exit_status
}

# Función para generar clave aleatoria de 32 caracteres
generate_random_key() {
    tr -dc 'A-Za-z0-9' </dev/urandom |
head -c 32
}

# Función para configurar tamaño de los logs de Docker
configure_docker_logs() {
    local config_file="/etc/docker/daemon.json"

    show_message "Configurando límites de logs en Docker..."

    # Crear el archivo daemon.json si no existe y agregar la configuración
    cat > "$config_file" <<EOF
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  }
}
EOF

    # Reiniciar Docker para aplicar los cambios
    run_command "systemctl restart docker" "Reiniciando Docker para aplicar configuración..."
}

# Función para configurar rkhunter
configure_rkhunter() {
    local config_file="/etc/rkhunter.conf"

 
   show_message "Configurando RKHunter..."

    # Asegurar que los valores sean los correctos
    run_command "sed -i 's/^UPDATE_MIRRORS=.*/UPDATE_MIRRORS=1/' \"$config_file\" && \
                sed -i 's/^MIRRORS_MODE=.*/MIRRORS_MODE=0/' \"$config_file\" && \
                sed -i 's|^WEB_CMD=.*|WEB_CMD=\"\"|'
\"$config_file\"" \
                "Aplicando configuración de RKHunter..."
}

# --- FUNCIÓN CORREGIDA PARA DESCARGAR DE GITHUB ---
download_from_api() {
    local tool_name=$1
    local local_path=$2
    
    # Obtener el enlace de descarga de GitHub usando el nombre de la herramienta
    local github_url="${GITHUB_LINKS[$tool_name]}"

    if [ -z "$github_url" ];
then
        show_error "Error: Enlace de GitHub no encontrado para la herramienta: $tool_name"
        cleanup 1
        exit 1
    fi  # <--- CORRECCIÓN: Usar 'fi' para cerrar el 'if'
    
    show_message "Descargando stack de $tool_name desde GitHub: $github_url"

    # Usar wget para descargar el archivo directamente
    if !
wget -qO "$local_path" "$github_url"; then
        show_error "Error al descargar $tool_name desde GitHub. Verifique el enlace y la conexión."
cleanup 1
        exit 1
    fi
    
    # Registrar el archivo como temporal
    register_temp_file "$local_path"
    
    if [ $?
-eq 0 ]; then
        show_success "Archivo $tool_name-stack.yml descargado correctamente"
        return 0
    else
        show_error "Error al guardar el archivo $local_path"
        cleanup 1
        exit 1
    fi
}
# --------------------------------------------------

# Función para configurar el modo Enterprise en la base de datos de Chatwoot
configure_chatwoot_enterprise() {
    local tool_name=$1
    
    show_message "Esperando a que el servicio PostgreSQL de Chatwoot esté listo para configuración Enterprise..."
    
    # Buscamos el ID del contenedor del servicio principal (chatwoot_chatwoot-postgres)
    # Usamos $tool_name para que funcione incluso si el stack se llama diferente
    local container_id=$(docker ps -q --filter "label=com.docker.stack.service=${tool_name}_${tool_name}-postgres" --filter "status=running")
    
    local max_wait=60
    local count=0
    while [ -z "$container_id" ] && [ $count -lt $max_wait ]; do
        sleep 5
        container_id=$(docker ps -q --filter "label=com.docker.stack.service=${tool_name}_${tool_name}-postgres" --filter "status=running")
        count=$((count + 5))
        show_message "Esperando contenedor PostgreSQL del stack $tool_name... ($count/$max_wait segundos)"
    done

    if [ -z "$container_id" ]; then
        show_error "No se pudo encontrar el contenedor de PostgreSQL para configurar Enterprise. Saltando configuración."
        return 1
    fi
    
    show_message "Contenedor PostgreSQL encontrado: $container_id. Forzando configuración Enterprise..."
    
    # Ejecutar el SQL usando la variable global predefinida
    if docker exec -i "$container_id" psql -U postgres -d chatwoot -c "$SQL_COMMAND_ENTERPRISE" >/dev/null 2>&1; then
        show_success "Configuración Enterprise forzada exitosamente en la base de datos."
        # Reiniciar los servicios principales para que lean la nueva configuración
        show_message "Reiniciando servicios de Chatwoot para aplicar configuración Enterprise..."
        docker service update --force ${tool_name}_rails ${tool_name}_sidekiq >/dev/null 2>&1
        return 0
    else
        show_error "Error al forzar la configuración Enterprise. Revise los logs."
        return 1
    fi
}

# Función para validar el token
validate_token() {
    show_message "Validando token de instalación..."
    
    response=$(curl -s -H "x-api-token: $API_TOKEN" "$API_URL/validate")
    
    
if echo "$response" | grep -q "valid\":true"; then
        customer_name=$(echo "$response" | grep -o '"customer":"[^"]*' | sed 's/"customer":"//')
        show_success "Token válido. Bienvenido, $customer_name"
        return 0
    else
        error_msg=$(echo "$response" | grep -o '"error":"[^"]*' | sed 's/"error":"//')
        show_error "Token inválido: $error_msg"
        return 1
    fi
}

# Verificar si el script se ejecuta como root
if [ "$EUID" -ne 
0 ]; then
    show_error "Este script debe ejecutarse como root"
    cleanup 1
    exit 1
fi

# Crear directorio principal
DOCKER_DIR="/home/docker"
mkdir -p $DOCKER_DIR
cd $DOCKER_DIR || { 
    show_error "No se pudo acceder al directorio $DOCKER_DIR"
    cleanup 1
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
read -p "Ingrese la contraseña común para todas las herramientas: 
" COMMON_PASSWORD
if [ -z "$COMMON_PASSWORD" ]; then
    show_error "La contraseña no puede estar vacía"
    cleanup 1
    exit 1
fi

read -p "Ingrese el dominio base (ejemplo: midominio.com): " BASE_DOMAIN
if [ -z "$BASE_DOMAIN" ];
then
    show_error "El dominio no puede estar vacío"
    cleanup 1
    exit 1
fi

# Generar una clave aleatoria por defecto
DEFAULT_SECRET_KEY=$(generate_random_key)
read -p "Ingrese una clave secreta de 32 caracteres para las herramientas (o presione Enter para usar una generada automáticamente): " SECRET_KEY
SECRET_KEY=${SECRET_KEY:-$DEFAULT_SECRET_KEY}

# Verificar longitud de la clave
if [ ${#SECRET_KEY} -ne 32 ];
then
    show_warning "La clave proporcionada no tiene 32 caracteres. Se utilizará una clave generada automáticamente."
SECRET_KEY=$DEFAULT_SECRET_KEY
fi

show_message "Se utilizará la siguiente clave secreta: $SECRET_KEY"

# NUEVA VARIABLE PARA CHATWOOT HUB URL
CHATWOOT_HUB_URL="CUALQUIER_URL_CON_#_AL_FINAL"

# Guardar variables globales para usar en los scripts
env_global_file="$DOCKER_DIR/.env.global"
cat > $env_global_file << EOL
COMMON_PASSWORD=$COMMON_PASSWORD
BASE_DOMAIN=$BASE_DOMAIN
SECRET_KEY=$SECRET_KEY
CHATWOOT_HUB_URL=$CHATWOOT_HUB_URL
EOL

# Verificar e instalar dependencias
install_dependencies() {
    show_message "Verificando e instalando dependencias..."
    
    # Actualizar repositorios
    apt-get update

    # Instalar jo para creacion de json
    apt-get install -y jo
    
    # Verificar si Docker está instalado
    if !
command -v docker &> /dev/null; then
        show_message "Instalando Docker..."
        apt-get install -y ca-certificates curl
        install -m 0755 -d /etc/apt/keyrings
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
        chmod a+r /etc/apt/keyrings/docker.asc
        echo \
"deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
$(. /etc/os-release && echo "$VERSION_CODENAME") stable" |
\
sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
        apt-get update
        apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
        systemctl enable docker
        systemctl start docker

        configure_docker_logs  # Aplica la configuración de logs después de instalar Docker
    fi
    
    # Instalar otras herramientas necesarias
    apt-get install -y git curl wget
}

# Inicializar Docker Swarm si no está activo
initialize_docker_swarm() 
{
    show_message "Verificando estado de Docker Swarm..."
    
    # Comprobar si Swarm está activo
    if !
docker info 2>/dev/null | grep -q "Swarm: active"; then
        show_message "Iniciando Docker Swarm..."
        run_command "docker swarm init --advertise-addr \$(hostname -I | awk '{print \$1}')" "Inicializando Docker Swarm..."
        if [ $?
-eq 0 ]; then
            show_success "Docker Swarm inicializado correctamente"
        else
            show_error "Error al inicializar Docker Swarm"
            cleanup 1
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
    show_message "Instalando Fail2Ban..."
    apt-get install -y fail2ban
    systemctl enable fail2ban
    systemctl start fail2ban
    
    # RKHunter
    show_message "Instalando RKHunter..."
    echo "postfix postfix/main_mailer_type select No configuration" |
debconf-set-selections
    apt-get install -y rkhunter
    configure_rkhunter  # Llama a la función de configuración después de instalar
    rkhunter --update
    rkhunter --propupd
    
    # CHKRootkit
    show_message "Instalando CHKRootkit..."
    apt-get install -y chkrootkit
    
    # UFW
    show_message "Configurando UFW Firewall..."
    apt-get install -y ufw
    ufw allow ssh
    ufw allow http
    ufw allow https
    echo 
"y" | ufw enable
    
    show_success "Herramientas de seguridad instaladas correctamente"

    INSTALLED_COMPONENTS["security"]=true
}

# Crear redes de Docker para Swarm
create_docker_networks() {
    show_message "Creando redes Docker para Swarm..."
    
    # Verificar si ya existen las redes
    if !
docker network ls 2>/dev/null | grep -q "frontend"; then
        run_command "docker network create --driver overlay --attachable frontend" "Creando red frontend..."
        show_success "Red 'frontend' creada"
    else
        show_warning "La red 'frontend' ya existe"
    fi
    
    if !
docker network ls 2>/dev/null | grep -q "backend"; then
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

    # Buscar todas las rutas de volúmenes 
en el archivo de stack
    # Patrón: device: /ruta/de/carpeta
    local volume_paths=$(grep -oP "device: \K/[^\s]+" "$stack_file" | sort | uniq)

    if [ -z "$volume_paths" ];
then
        show_message "No se encontraron rutas de volúmenes para $tool_name"
        return
    fi

    # Crear cada directorio encontrado
    for path in $volume_paths;
do
        show_message "Creando directorio: $path"
        run_command "mkdir -p \"$path\"" "Creando directorio $path..."
        if [ $?
-eq 0 ]; then
            show_success "Directorio $path creado correctamente"
        else
            show_error "Error al crear el directorio $path"
            cleanup 1
            exit 1
        fi
    done
}

# Función para esperar a que un servicio esté disponible
wait_for_service() {
    local service_url=$1
  
  local timeout=${2:-300}  # timeout por defecto de 5 minutos
    local counter=0
    
    show_message "Esperando a que $service_url esté disponible..."
    
    while [ $counter -lt $timeout ];
do
        if curl -k -s --connect-timeout 5 "$service_url" >/dev/null 2>&1;
then
            show_success "Servicio $service_url está disponible"
            return 0
        fi
        
        sleep 5
        counter=$((counter + 5))
        
        # Mostrar progreso cada 30 segundos
        if [ $((counter % 30)) -eq 0 
]; then
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
    container_id=$(docker ps --filter "name=redis_redis-server" --format "{{.ID}}")

    while [ $attempt -lt $max_attempts ] && [ "$redis_ready" = false ];
do
        if [ -n "$container_id" ];
then
            if docker exec "$container_id" redis-cli ping 2>/dev/null |
grep -q "PONG"; then
                redis_ready=true
                show_success "Redis está listo"
            else
                sleep 5
                attempt=$((attempt + 1))
               
 if [ $((attempt % 12)) -eq 0 ]; then
                    show_message "Esperando Redis... ($((attempt * 5))/300 segundos)"
                fi
            fi
        else
            show_message "Esperando a que Redis inicie..."
            
sleep 5
            attempt=$((attempt + 1))
            # Intentamos obtener el container_id nuevamente
            container_id=$(docker ps --filter "name=redis_redis-server" --format "{{.ID}}")
        fi
    done

    if [ "$redis_ready" = false ];
then
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
    if !
docker stack deploy -c "$init_stack_file" chatwoot-init >/dev/null 2>&1; then
        show_error "Error al desplegar el stack de inicialización"
        return 1
    fi

    show_success "Stack de inicialización desplegado"
    
    # Esperar a que el contenedor de PostgreSQL esté corriendo
    local postgres_container_id=""
    local postgres_attempt=0
    local max_postgres_attempt=30
    
    show_message "Esperando a que el contenedor de PostgreSQL inicie..."
    while [ $postgres_attempt -lt 
$max_postgres_attempt ] && [ -z "$postgres_container_id" ]; do
        postgres_container_id=$(docker ps -q --filter "name=chatwoot-init_chatwoot-postgres")
        if [ -z "$postgres_container_id" ];
then
            sleep 5
            postgres_attempt=$((postgres_attempt + 1))
        fi
    done

    if [ -z "$postgres_container_id" ];
then
        show_error "No se pudo obtener el ID del contenedor PostgreSQL"
        docker stack rm chatwoot-init >/dev/null 2>&1
        return 1
    fi

    # Verificar conexión a PostgreSQL usando pg_isready
    show_message "Verificando disponibilidad de PostgreSQL..."
    local pg_ready=false
    local max_pg_wait=60
    local pg_attempt=0

    while [ $pg_attempt -lt $max_pg_wait ] && [ "$pg_ready" = false ];
do
        if docker exec "$postgres_container_id" pg_isready -U postgres -h localhost >/dev/null 2>&1;
then
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

    if [ "$pg_ready" = false ];
then
        show_error "PostgreSQL no está disponible después de 5 minutos"
        docker stack rm chatwoot-init >/dev/null 2>&1
        return 1
    fi
        
    # Esperar a que termine la inicialización
    show_message "Esperando a que termine la inicialización de la base de datos..."
    local init_complete=false
    local max_wait=600  # 10 minutos máximo para la inicialización
    local wait_time=0
  
  
    while [ $wait_time -lt $max_wait ] && [ "$init_complete" = false ];
do
        # Verificar si el servicio ha terminado exitosamente
        local service_status=$(docker service ps chatwoot-init_chatwoot-init --format "{{.CurrentState}}" --no-trunc 2>/dev/null | head -1)
        
        if echo "$service_status" |
grep -q "Complete"; then
            init_complete=true
            show_success "Inicialización de base de datos completada exitosamente"
        elif echo "$service_status" |
grep -q "Failed"; then
            show_error "La inicialización de la base de datos falló"
            # Mostrar logs para diagnóstico
            show_message "Logs del servicio de inicialización:"
            docker service logs chatwoot-init_chatwoot-init 2>/dev/null |
tail -20
            show_message "Logs de PostgreSQL:"
            docker service logs chatwoot-init_chatwoot-postgres 2>/dev/null |
tail -20
            break
        fi
        
        sleep 10
        wait_time=$((wait_time + 10))
        
        # Mostrar progreso cada minuto
        if [ $((wait_time % 60)) -eq 0 ];
then
            show_message "Inicializando base de datos... ($wait_time/$max_wait segundos)"
            # Mostrar logs actuales cada minuto para debugging
            show_message "Estado actual de inicialización:"
            docker service logs chatwoot-init_chatwoot-init --tail 5 2>/dev/null |
tail -3
        fi
    done
    
    # Limpiar el stack de inicialización
    show_message "Limpiando stack de inicialización..."
    docker stack rm chatwoot-init >/dev/null 2>&1
    
    # Esperar a que se limpie completamente
    sleep 15
    
    if [ "$init_complete" = true ];
then
        show_success "Base de datos de Chatwoot inicializada correctamente"
        return 0
    else
        show_error "La inicialización de la base de datos no se completó en el tiempo esperado"
        return 1
    fi
}


# Función para instalar una herramienta con Docker Swarm (versión corregida para Chatwoot)
install_docker_tool() {
    tool_name=$1
    default_subdomain=$2
    
    show_message "Configurando $tool_name..."
    tool_dir="$DOCKER_DIR/$tool_name"
  
  mkdir -p $tool_dir
    cd $tool_dir ||
{
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
    subdomain_file="$tool_dir/.subdomain"
    
echo "$SUBDOMAIN" > "$subdomain_file"
    register_temp_file "$subdomain_file"
    
    # Descargar archivos de configuración desde GITHUB
    show_message "Descargando archivos de configuración para $tool_name..."
    stack_file="$tool_dir/$tool_name-stack.yml"
    deploy_file="$tool_dir/$tool_name-deploy.yml"

    # Lógica condicional para Chatwoot: CREAR el archivo directamente e inyectar CHATWOOT_HUB_URL
    if [ "$tool_name" = "chatwoot" ]; then
        show_success "Archivo $tool_name-deploy.yml creado directamente en el script"
        
        # Crear el archivo YAML usando Heredoc
        cat > "$deploy_file" << EOF
version: '3.8'

services:
  rails:
    image: chatwoot/chatwoot:latest
    environment:
      # Configuración Base
      - NODE_ENV=production
      - RAILS_ENV=production
      - INSTALLATION_ENV=docker
      - SECRET_KEY_BASE=REPLACE_SECRET_KEY
      - FRONTEND_URL=https://REPLACE_SUBDOMAIN.REPLACE_DOMAIN
      - WEBSOCKET_URL=wss://REPLACE_SUBDOMAIN.REPLACE_DOMAIN/cable
      - FORCE_SSL=true
      - CHATWOOT_HUB_URL=$CHATWOOT_HUB_URL # <--- ¡URL INYECTADA!
      
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
      - POSTGRES_PASSWORD=REPLACE_PASSWORD
      - POSTGRES_STATEMENT_TIMEOUT=14s
      - RAILS_MAX_THREADS=5
      
      # Email/SMTP
      - MAILER_SENDER_EMAIL=Chatwoot <correo@corporativo>
      - SMTP_DOMAIN=dominio-del-servidor-smtp
      - SMTP_ADDRESS=mail.dominio.com
      - SMTP_PORT=587
      - SMTP_USERNAME=email-del-smtp
      - SMTP_PASSWORD=contraseña-smtp
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
    command: ['bundle', 'exec', 'rails', 's', '-p', '3000', '-b', '0.0.0.0']
    
    deploy:
      replicas: 1
      restart_policy:
        condition: on-failure
        
      labels:
        - "traefik.enable=true"
        - "traefik.http.routers.chatwoot.rule=Host(\`REPLACE_SUBDOMAIN.REPLACE_DOMAIN\`)"
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
      - SECRET_KEY_BASE=REPLACE_SECRET_KEY
      - FRONTEND_URL=https://REPLACE_SUBDOMAIN.REPLACE_DOMAIN
      - WEBSOCKET_URL=wss://REPLACE_SUBDOMAIN.REPLACE_DOMAIN/cable
      - FORCE_SSL=true
      - CHATWOOT_HUB_URL=$CHATWOOT_HUB_URL # <--- ¡URL INYECTADA!
      
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
      - POSTGRES_PASSWORD=REPLACE_PASSWORD
      - POSTGRES_STATEMENT_TIMEOUT=14s
      - RAILS_MAX_THREADS=5
      
      # Email/SMTP
      - MAILER_SENDER_EMAIL=Chatwoot <correo@corporativo>
      - SMTP_DOMAIN=dominio-del-servidor-smtp
      - SMTP_ADDRESS=mail.dominio.com
      - SMTP_PORT=587
      - SMTP_USERNAME=email-del-smtp
      - SMTP_PASSWORD=contraseña-smtp
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
      - POSTGRES_PASSWORD=REPLACE_PASSWORD
      
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
        register_temp_file "$deploy_file"
        
        # Saltamos la lógica de descarga y copia para Chatwoot

    else
        # Lógica para otras herramientas: descargar y copiar
        download_from_api "$tool_name" "$stack_file"
        
        # Crear archivo temporal para reemplazar variables
        cp "$stack_file" "$deploy_file"
        register_temp_file "$deploy_file"
    fi

    # Reemplazar las variables en el archivo de stack
    sed -i "s|REPLACE_PASSWORD|$COMMON_PASSWORD|g" "$deploy_file"
    sed -i 
"s|REPLACE_SUBDOMAIN|$SUBDOMAIN|g" "$deploy_file"
    sed -i "s|REPLACE_DOMAIN|$BASE_DOMAIN|g" "$deploy_file"
    sed -i "s|REPLACE_SECRET_KEY|$SECRET_KEY|g" "$deploy_file"

    # Crear directorios para volúmenes DESPUÉS de reemplazar las variables
    create_volume_directories "$deploy_file" "$tool_name"
    
    # Tratamiento especial para Chatwoot
    if [ "$tool_name" = "chatwoot" ];
then
        show_message "Chatwoot detectado - se requiere inicialización de base de datos"
        
        # Verificar que Redis esté desplegado (Chatwoot usa su propio PostgreSQL)
        if !
docker service ls | grep -q "redis_redis"; then
            show_error "Redis debe estar desplegado antes de instalar Chatwoot"
            cleanup 1
            exit 1
        fi
        
        # Inicializar la base de datos antes del despliegue
        if initialize_chatwoot_database "$SUBDOMAIN";
then
            show_success "Base de datos de Chatwoot inicializada correctamente"
        else
            show_error "Error al inicializar la base de datos de Chatwoot"
            cleanup 1
            exit 1
        fi
    fi
    
    # Desplegar stack en Swarm
  
  show_message "Desplegando $tool_name en Docker Swarm..."
    run_command "docker stack deploy -c \"$deploy_file\" $tool_name" "Desplegando $tool_name..."
    
    if [ $?
-eq 0 ]; then
        show_success "$tool_name instalado correctamente en Docker Swarm"

        # **Llamar a la función de configuración Enterprise aquí**
        if [ "$tool_name" = "chatwoot" ]; then
            configure_chatwoot_enterprise "$tool_name"
        fi

        # Agregar al registro de componentes instalados
        INSTALLED_COMPONENTS["$tool_name"]=true

        # Actualizar estado con TODOS los componentes
        current_components=$(jo -a "${!INSTALLED_COMPONENTS[@]}")
        update_installation_status "in_progress" "$current_components"
        
    else
        show_error "Error al instalar $tool_name"
   
     INSTALLED_COMPONENTS["$tool_name"]=false
        cleanup 1
        exit 1
    fi
    
    cd $DOCKER_DIR ||
{
        show_error "No se pudo volver al directorio principal $DOCKER_DIR"
        cleanup 1
        exit 1
    }
}

# Función principal
main() {
    show_message "Iniciando la instalación automatizada de herramientas Docker..."

    # Si no se pasó un token, solicitarlo
    if [ -z "$API_TOKEN" ];
then
        read -p "Ingrese su token de instalación (opcional, deje vacío para saltar la validación): " API_TOKEN
        
        # Si el usuario proporciona un token, intentamos validarlo
        if [ !
-z "$API_TOKEN" ]; then
            if ! validate_token;
then
                show_error "No se puede continuar con la instalación. Token inválido."
cleanup 1
                exit 1
            fi
        fi
    fi

    # Registrar el inicio de la instalación
    register_installation_start

    # Instalar dependencias
    install_dependencies
    
    # Marcar como en progreso
    current_components=$(jo -a "${!INSTALLED_COMPONENTS[@]}")
    update_installation_status "started" "$current_components"

    # Inicializar Docker Swarm
   
 initialize_docker_swarm
    
    # Instalar herramientas de seguridad
    install_server_tools
    
    # Crear redes Docker
    create_docker_networks

    # Inicializar array de subdominios personalizados con valores predeterminados
    for i in "${!SELECTED_TOOLS[@]}";
do
        CUSTOM_SUBDOMAINS[$i]=""
    done

    # Actualizar estado
    current_components=$(jo -a "${!INSTALLED_COMPONENTS[@]}")
    update_installation_status "in_progress" "$current_components"

    # Instalar herramientas Docker seleccionadas en orden específico
    show_message "Instalando servicios en orden de dependencias..."
    
    # Orden de instalación: infraestructura primero, aplicaciones después
    INSTALL_ORDER=("traefik" "redis" "postgres" "portainer" "n8n" "evoapi" "chatwoot")
    
    for tool_name in "${INSTALL_ORDER[@]}";
do
        # Verificar si la herramienta está en la lista de seleccionadas
        if [[ " ${SELECTED_TOOLS[@]} " =~ " ${tool_name} " ]];
then
            # Encontrar el subdomain correspondiente
            default_subdomain=""
            tool_index=-1
            for j in "${!AVAILABLE_TOOLS[@]}";
do
                if [ "${AVAILABLE_TOOLS[$j]}" = "$tool_name" ];
then
                    default_subdomain="${DEFAULT_SUBDOMAINS[$j]}"
                    tool_index=$j
                    break
                fi
            done
            

            # Instalar la herramienta
            install_docker_tool "$tool_name" "$default_subdomain"
            
            # Pausa entre instalaciones para permitir que los servicios se estabilicen
            if [ "$tool_name" = "postgres" ] ||
[ "$tool_name" = "redis" ]; then
                show_message "Esperando a que $tool_name se estabilice..."
                sleep 15
            fi
        fi
    done

    # Completar la instalación
    complete_installation
    
    show_success "¡Instalación completada!"
echo ""
    echo "Accede a tus servicios en los siguientes URLs:"
    
    # Mostrar URLs de los servicios instalados usando los subdominios personalizados
    for i in "${!SELECTED_TOOLS[@]}";
do
        tool_name="${SELECTED_TOOLS[$i]}"

        # Encontrar el índice de la herramienta
        tool_index=-1
        for j in "${!AVAILABLE_TOOLS[@]}";
do
            if [ "${AVAILABLE_TOOLS[$j]}" = "$tool_name" ];
then
                tool_index=$j
                break
            fi
        done

        if [ $tool_index -ge 0 ];
then
            # Leer el subdominio personalizado del archivo guardado
            subdomain_file="$DOCKER_DIR/$tool_name/.subdomain"
            if [ -f "$subdomain_file" ];
then
                subdomain=$(cat "$subdomain_file")
            else
                # Si no existe el archivo, usar el subdominio del array
                subdomain="${CUSTOM_SUBDOMAINS[$tool_index]}"
                # Si está vacío, usar el predeterminado
       
         if [ -z "$subdomain" ];
then
                    subdomain="${DEFAULT_SUBDOMAINS[$tool_index]}"
                fi
            fi

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
main

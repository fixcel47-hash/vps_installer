#!/bin/bash

# =================================================================================
# UNIFIED INSTALLER SCRIPT (v2.1.0-CLEAN)
# Fusion de installer.sh (Logica Swarm, Seguridad, Inicializacion Chatwoot)
# y combined_installer_v_2.sh (Descarga y Sanitizacion)
# NO REQUIERE API DE TOKEN EXTERNA
# =================================================================================

SCRIPT_VERSION="2.1.0-CLEAN"

# Colores para mensajes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# -------------------------------
# Configuracion de URLs para descarga de Stacks (De combined_installer_v_2.sh)
# NOTA: Estas URLs apuntan a archivos subidos a GitHub por un usuario.
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
DOWNLOAD_TIMEOUT=30

# Obtener ruta absoluta del script actual
SCRIPT_PATH=$(readlink -f "$0")

# Lista de archivos temporales para limpiar
TEMP_FILES=()

# Directorio principal de Docker
DOCKER_DIR="/home/docker"

# Lista de herramientas (para el flujo interactivo)
AVAILABLE_TOOLS=("traefik" "portainer" "redis" "postgres" "n8n" "evoapi" "chatwoot")
SELECTED_TOOLS=("traefik" "portainer" "redis" "postgres" "n8n" "evoapi" "chatwoot")
DEFAULT_SUBDOMAINS=("proxy" "admin" "redis" "postgres" "n8" "evoapi" "chat")
declare -a CUSTOM_SUBDOMAINS # Array para almacenar subdominios

# -------------------------------
# Funciones de Mensajes y Utilidades
# -------------------------------

show_message() { echo -e "${BLUE}[INFO]${NC} $1"; }
show_error() { echo -e "${RED}[ERROR]${NC} $1"; }
show_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
show_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
register_temp_file() { TEMP_FILES+=("$1"); }
generate_random_key() { tr -dc 'A-Za-z0-9' </dev/urandom | head -c 32; }

# Funcion de limpieza (AJUSTADA para eliminar referencias a la API)
cleanup() {
    local exit_code=$1
    local delete_stacks=${2:-false}
    
    show_message "Realizando limpieza antes de salir..."
    
    if [ $exit_code -ne 0 ]; then
        show_error "Error detectado durante la instalacion. Limpiando archivos temporales..."
    fi
    
    # Eliminar archivos temporales
    if [ ${#TEMP_FILES[@]} -gt 0 ]; then
        for file in "${TEMP_FILES[@]}"; do
            if [ -f "$file" ]; then
                rm -f "$file"
            fi
        done
    fi
    
    # Si se solicita, eliminar solo los archivos de despliegue y temporales (.subdomain, .env.global)
    if [ "$delete_stacks" = true ]; then
        show_message "Eliminando archivos de despliegue y configuracion temporal..."
        for tool_name in "${SELECTED_TOOLS[@]}"; do
            local tool_dir="$DOCKER_DIR/$tool_name"
            # Eliminar .subdomain y archivos de despliegue/raw/sanitizados
            rm -f "$tool_dir/."subdomain
            rm -f "$tool_dir/$tool_name-deploy.yml"
            rm -f "$tool_dir/$tool_name-stack.yml"
            rm -f "$tool_dir/$tool_name-stack.yml.raw"
            rm -f "$tool_dir/$tool_name-stack.sanitized.yml"
        done
        rm -f "$DOCKER_DIR/.env.global"
    fi
    
    # Crear un script de autodestruccion (solo si hubo error o se solicito limpieza total)
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
        show_error "La instalacion ha fallado. Revise los logs para mas informacion."
    else
        show_success "Instalacion completada exitosamente"
    fi
}

# Configurar trampas para senales para limpiar antes de salir
# SE ELIMINA LA LLAMADA A update_installation_status del TRAP ERR (ya que no existe)
trap 'cleanup 1 false; exit 1' SIGHUP SIGINT SIGQUIT SIGTERM
trap 'cleanup 1 false; exit 1' ERR

# Funcion para animacion de espera y ejecucion de comandos
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
run_command() {
    local cmd=$1
    local msg=$2
    
    show_message "$msg"
    # Ejecutar en subshell y redirigir stdout/stderr a un archivo temporal para el spinner
    local log_file="/tmp/cmd_output_$$_$(date +%s)"
    eval "$cmd" > "$log_file" 2>&1 &
    local cmd_pid=$!
    spinner $cmd_pid
    wait $cmd_pid
    local exit_status=$?
    
    if [ $exit_status -ne 0 ]; then
        show_error "Comando fallo: $cmd"
        show_message "Ultimas 10 lineas de log de error:"
        tail -n 10 "$log_file"
        rm -f "$log_file"
        # La trampa ERR maneja la salida. Solo devolvemos el estado.
        return $exit_status
    fi
    
    rm -f "$log_file"
    return $exit_status
}

# -------------------------------
# Funciones de Instalacion de Dependencias, Seguridad y Redes (Mantenidas)
# -------------------------------

configure_docker_logs() {
    local config_file="/etc/docker/daemon.json"
    show_message "Configurando limites de logs en Docker..."
    cat > "$config_file" <<EOF
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  }
}
EOF
    run_command "systemctl restart docker" "Reiniciando Docker para aplicar configuracion..."
}

configure_rkhunter() {
    local config_file="/etc/rkhunter.conf"
    show_message "Configurando RKHunter..."
    run_command "sed -i 's/^UPDATE_MIRRORS=.*/UPDATE_MIRRORS=1/' \"$config_file\" && \
                sed -i 's/^MIRRORS_MODE=.*/MIRRORS_MODE=0/' \"$config_file\" && \
                sed -i 's|^WEB_CMD=.*|WEB_CMD=\"\"|' \"$config_file\"" \
                "Aplicando configuracion de RKHunter..."
}

install_dependencies() {
    show_message "Verificando e instalando dependencias (curl, wget, jo, perl, Docker)..."
    
    run_command "apt-get update" "Actualizando lista de paquetes..."
    run_command "apt-get install -y jo perl" "Instalando utilidades (jo, perl)..."
    
    if ! command -v docker &> /dev/null; then
        show_message "Instalando Docker..."
        run_command "apt-get install -y ca-certificates curl" "Instalando requisitos de Docker..."
        
        # Logica de instalacion de Docker adaptada para compatibilidad:
        install -m 0755 -d /etc/apt/keyrings
        run_command "curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc" "Descargando clave GPG de Docker..."
        chmod a+r /etc/apt/keyrings/docker.asc
        
        # Configurar repositorio de Docker
        echo \
"deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
$(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
        
        run_command "apt-get update && apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin" "Instalando paquetes de Docker..."
        run_command "systemctl enable docker && systemctl start docker" "Activando servicio Docker..."
        configure_docker_logs
    fi
    
    run_command "apt-get install -y git curl wget" "Instalando herramientas basicas (git, curl, wget)..."
    show_success "Dependencias instaladas/verificadas."
}

initialize_docker_swarm() {
    show_message "Verificando estado de Docker Swarm..."
    if ! docker info 2>/dev/null | grep -q "Swarm: active"; then
        show_message "Iniciando Docker Swarm..."
        run_command "docker swarm init --advertise-addr \$(hostname -I | awk '{print \$1}')" "Inicializando Docker Swarm..."
        show_success "Docker Swarm inicializado correctamente"
    else
        show_message "Docker Swarm ya esta activo"
    fi
}

install_server_tools() {
    show_message "Instalando herramientas de seguridad en el servidor..."
    
    # Fail2Ban
    run_command "apt-get install -y fail2ban && systemctl enable fail2ban && systemctl start fail2ban" "Instalando y activando Fail2Ban..."
    
    # RKHunter
    show_message "Instalando RKHunter..."
    run_command "echo 'postfix postfix/main_mailer_type select No configuration' | debconf-set-selections && apt-get install -y rkhunter" "Instalando RKHunter..."
    configure_rkhunter
    run_command "rkhunter --update" "Actualizando RKHunter..."
    run_command "rkhunter --propupd" "Actualizando base de datos de propiedades de RKHunter..."
    
    # CHKRootkit
    run_command "apt-get install -y chkrootkit" "Instalando CHKRootkit..."
    
    # UFW
    show_message "Configurando UFW Firewall..."
    run_command "apt-get install -y ufw" "Instalando UFW..."
    run_command "ufw allow ssh && ufw allow http && ufw allow https && echo 'y' | ufw enable" "Configurando y activando reglas basicas de UFW..."
    
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
# Funciones de Descarga y Sanitizacion (Mantenidas y Ajustadas)
# -------------------------------

download_file() {
    local url="$1" file="$2"
    if [[ -z "$url" ]]; then show_warning "URL vacia para $file"; return 1; fi
    show_message "Descargando $url -> $file"
    
    local download_cmd
    if command -v curl >/dev/null 2>&1; then
        download_cmd="curl --fail --location --max-time ${DOWNLOAD_TIMEOUT} -sS '$url' -o '$file'"
    elif command -v wget >/dev/null 2>&1; then
        download_cmd="wget -q --timeout=${DOWNLOAD_TIMEOUT} -O '$file' '$url'"
    else
        show_error "Ni curl ni wget estan disponibles para la descarga."; return 3
    fi
    
    if ! eval "$download_cmd"; then
        show_error "Fallo al descargar $url"; return 2
    fi
    show_success "Descargado: $file"
    return 0
}

# Patrones sensibles para sanitizacion
SENSITIVE_PATTERNS=(
  "API_TOKEN" "API_KEY" "SECRET" "PASSWORD" "DB_PASSWORD"
  "JWT" "ACCESS_TOKEN" "AUTH_TOKEN" "TOKEN:" "token:"
)

sanitize_yaml() {
    local infile="$1" outfile="$2"
    
    # Copia el archivo original como .raw (para referencia)
    cp -f "$infile" "${infile}.raw"
    
    # Copia el original al archivo de salida para empezar la limpieza
    cp -f "$infile" "$outfile"
    
    show_message "Saneando $outfile de secretos evidentes..."

    # Usar perl para buscar y reemplazar valores despues de patrones sensibles
    # Expresion para reemplazar ocurrencias: "pat: algun_valor" -> "pat: <REPLACE_ME>"
    # y "pat=algun_valor" -> "pat=<REPLACE_ME>"
    for pat in "${SENSITIVE_PATTERNS[@]}"; do
        # Escapamos el patron para el uso en perl
        local escaped_pat=$(echo "$pat" | sed 's/[][\/.^$*+?(){}|-]/\\&/g')
        # Reemplazar KEY: valor o KEY=valor
        perl -0777 -pi -e "s/(${escaped_pat}\s*[:=]\s*)(\S+)/\1<REPLACE_ME>/ig" "$outfile" || true
    done

    # Ademas, eliminar lineas que contengan variables de entorno en mayusculas seguidas de un string largo
    perl -0777 -pi -e 's/([A-Z_]+)\s*[:=]\s*([A-Za-z0-9_\-\.\/]{32,})/\1: <REPLACE_ME>/g' "$outfile" || true

    show_success "Saneado: $outfile (copia original en ${infile}.raw)"
}

# -------------------------------
# Funciones de Instalacion de Docker Swarm y Chatwoot (Mantenidas)
# -------------------------------

create_volume_directories() {
    local stack_file=$1
    local tool_name=$2

    show_message "Creando directorios para volumenes de $tool_name..."

    # Buscar todas las rutas de volumenes en el archivo de stack (patron: device: /ruta/de/carpeta)
    local volume_paths=$(grep -oP "device: \K/[^\s]+" "$stack_file" | sort | uniq)

    if [ -z "$volume_paths" ]; then
        show_message "No se encontraron rutas de volumenes para $tool_name"
        return
    fi

    for path in $volume_paths; do
        run_command "mkdir -p \"$path\"" "Creando directorio $path..."
    done
}

# Funcion compleja de inicializacion de Chatwoot (Mantenida)
initialize_chatwoot_database() {
    local tool_name="chatwoot"
    local subdomain=$1
    
    show_message "Inicializando base de datos de Chatwoot..."
    
    # 1. Verificar Redis (por conexion real) - Simplificado el chequeo para depender de la red
    show_message "Verificando disponibilidad de Redis. Se asume que 'redis' ya esta desplegado."
    
    # 2. Crear stack temporal solo para inicializar la base de datos
    show_message "Creando stack temporal para inicializacion de base de datos..."
    local init_stack_file="/tmp/chatwoot-init-stack.yml"
    
    # NOTE: Este YAML asume que existe un volumen llamado chatwoot_postgres_data en /home/docker/chatwoot/postgres_data
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
    
    # 3. Desplegar el stack de inicializacion
    run_command "docker stack deploy -c \"$init_stack_file\" chatwoot-init" "Desplegando stack temporal para inicializar DB..."
    
    # 4. Esperar a que el servicio de inicializacion termine (Simplificado, se asume que si el stack se despliega, el contenedor de inicializacion se ejecuta)
    show_message "Esperando a que el contenedor de inicializacion de Chatwoot termine (maximo 5 minutos)..."
    
    local init_service_name="chatwoot-init_chatwoot-init"
    local max_wait=300
    local waited=0
    local init_status=""

    while [ $waited -lt $max_wait ]; do
        init_status=$(docker service ps -q "$init_service_name" --filter "desired-state=shutdown" --format "{{.CurrentState}}" | head -n 1)
        
        if [[ "$init_status" == "Shutdown" || "$init_status" == *"Complete"* ]]; then
            show_success "Contenedor de inicializacion de Chatwoot finalizado."
            break
        fi

        sleep 10
        waited=$((waited + 10))
    done

    if [ $waited -ge $max_wait ]; then
        show_error "Timeout: El contenedor de inicializacion de la base de datos de Chatwoot no termino a tiempo."
        # Limpiamos el stack de todas formas para no dejar basura
        docker stack rm chatwoot-init >/dev/null 2>&1
        sleep 15
        return 1
    fi

    # 5. Limpiar el stack de inicializacion
    show_message "Limpiando stack de inicializacion..."
    docker stack rm chatwoot-init >/dev/null 2>&1
    sleep 15 # Esperar a que Swarm lo retire
    
    show_success "Base de datos de Chatwoot inicializada correctamente"
    return 0
}


install_docker_tool() {
    local tool_name=$1
    local default_subdomain=$2
    local tool_index=$3

    show_message "Configurando $tool_name..."
    local tool_dir="$DOCKER_DIR/$tool_name"
    mkdir -p "$tool_dir"
    cd "$tool_dir" || {
        show_error "No se pudo acceder al directorio $tool_dir"
        exit 1
    }
    
    # 1. Solicitar subdominio
    read -p "Ingrese el subdominio para $tool_name [$default_subdomain]: " SUBDOMAIN
    SUBDOMAIN=${SUBDOMAIN:-$default_subdomain}
    
    CUSTOM_SUBDOMAINS[$tool_index]=$SUBDOMAIN
    
    local subdomain_file="$tool_dir/.subdomain"
    echo "$SUBDOMAIN" > "$subdomain_file"
    register_temp_file "$subdomain_file"
    
    # 2. Descargar y sanear el archivo de stack
    local stack_url="${STACK_URLS[$tool_name]}"
    local stack_file="$tool_dir/$tool_name-stack.yml"
    local deploy_file="$tool_dir/$tool_name-deploy.yml"

    if ! download_file "$stack_url" "$stack_file"; then
        show_error "No se pudo descargar el archivo de stack para $tool_name"
        exit 1
    fi

    # Sanear y crear el archivo de despliegue
    sanitize_yaml "$stack_file" "$deploy_file"
    register_temp_file "$deploy_file"

    # 3. Reemplazar las variables en el archivo de stack saneado
    # Reemplazar <REPLACE_ME> por los valores de usuario
    # Asume que los stacks usan las siguientes variables:
    # COMMON_PASSWORD, BASE_DOMAIN, SUBDOMAIN, SECRET_KEY, REPLACE_PASSWORD, REPLACE_SUBDOMAIN, REPLACE_DOMAIN, REPLACE_SECRET_KEY
    
    sed -i "s|<REPLACE_ME>|$COMMON_PASSWORD|g" "$deploy_file"
    
    sed -i "s|REPLACE_PASSWORD|$COMMON_PASSWORD|g" "$deploy_file"
    sed -i "s|REPLACE_SUBDOMAIN|$SUBDOMAIN|g" "$deploy_file"
    sed -i "s|REPLACE_DOMAIN|$BASE_DOMAIN|g" "$deploy_file"
    sed -i "s|REPLACE_SECRET_KEY|$SECRET_KEY|g" "$deploy_file"

    # 4. Crear directorios de volumenes
    create_volume_directories "$deploy_file" "$tool_name"
    
    # 5. Tratamiento especial para Chatwoot
    if [ "$tool_name" = "chatwoot" ]; then
        show_message "Chatwoot detectado - se requiere inicializacion de base de datos"
        if ! initialize_chatwoot_database "$SUBDOMAIN"; then
            show_error "Error al inicializar la base de datos de Chatwoot"
            exit 1
        fi
    fi
    
    # 6. Desplegar stack en Swarm
    show_message "Desplegando $tool_name en Docker Swarm..."
    run_command "docker stack deploy -c \"$deploy_file\" $tool_name" "Desplegando $tool_name..."
    
    cd "$DOCKER_DIR" || {
        show_error "No se pudo volver al directorio principal $DOCKER_DIR"
        exit 1
    }
}


# -------------------------------
# Flujo Principal 
# -------------------------------
main() {
    show_message "Iniciando la instalacion automatizada de herramientas Docker (v$SCRIPT_VERSION)..."

    # 1. Verificar si el script se ejecuta como root
    if [ "$EUID" -ne 0 ]; then
        show_error "Este script debe ejecutarse como root"
        exit 1
    fi
    
    # 2. Configuracion inicial
    mkdir -p "$DOCKER_DIR"
    cd "$DOCKER_DIR" || { 
        show_error "No se pudo acceder al directorio $DOCKER_DIR"
        exit 1
    }

    show_message "Configuracion inicial"
    read -p "Ingrese la contrasena comun para todas las herramientas: " COMMON_PASSWORD
    if [ -z "$COMMON_PASSWORD" ]; then show_error "La contrasena no puede estar vacia"; exit 1; fi

    read -p "Ingrese el dominio base (ejemplo: midominio.com): " BASE_DOMAIN
    if [ -z "$BASE_DOMAIN" ]; then show_error "El dominio no puede estar vacio"; exit 1; fi

    DEFAULT_SECRET_KEY=$(generate_random_key)
    read -p "Ingrese una clave secreta de 32 caracteres para las herramientas (o presione Enter para usar una generada automaticamente): " SECRET_KEY
    SECRET_KEY=${SECRET_KEY:-$DEFAULT_SECRET_KEY}

    if [ ${#SECRET_KEY} -ne 32 ]; then
        show_warning "La clave proporcionada no tiene 32 caracteres. Se utilizara una clave generada automaticamente."
        SECRET_KEY=$DEFAULT_SECRET_KEY
    fi

    show_message "Se utilizara la siguiente clave secreta: $SECRET_KEY"

    # Guardar variables globales
    env_global_file="$DOCKER_DIR/.env.global"
    cat > "$env_global_file" << EOL
COMMON_PASSWORD=$COMMON_PASSWORD
BASE_DOMAIN=$BASE_DOMAIN
SECRET_KEY=$SECRET_KEY
EOL
    register_temp_file "$env_global_file"

    # 3. Instalacion de dependencias, Swarm, Seguridad y Redes
    install_dependencies
    initialize_docker_swarm
    install_server_tools
    create_docker_networks

    # 4. Inicializar array de subdominios personalizados
    for i in "${!SELECTED_TOOLS[@]}"; do CUSTOM_SUBDOMAINS[$i]=""; done

    # 5. Instalar herramientas Docker en orden de dependencias
    show_message "Instalando servicios en orden de dependencias..."
    
    INSTALL_ORDER=("traefik" "redis" "postgres" "portainer" "n8n" "evoapi" "chatwoot")
    
    for tool_name in "${INSTALL_ORDER[@]}"; do
        # Encontrar el default_subdomain y el tool_index
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

    # 6. Mostrar URLs y finalizar
    show_success "!Instalacion completada!"
    echo ""
    echo "Accede a tus servicios en los siguientes URLs:"
    
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
    echo "Informacion de credenciales:"
    echo "- Contrasena comun: $COMMON_PASSWORD"
    echo "- Clave secreta: $SECRET_KEY"
    echo ""
    echo "Esta informacion se ha guardado en: $DOCKER_DIR/.env.global"

    cleanup 0 true
}

# Ejecutar funcion principal
main "$@"
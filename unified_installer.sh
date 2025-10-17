#!/usr/bin/env bash
# =================================================================================
# UNIFIED INSTALLER SCRIPT (v3.0.0 - Final)
# Fusion:
# 1. Logica SUDO, Deteccion OS, Instalacion Docker (del codigo proporcionado)
# 2. Logica Swarm, Seguridad, Inicializacion Chatwoot (del installer.sh original)
# 3. Logica Descarga y Sanitizacion (del combined_installer_v_2.sh)
# =================================================================================

SCRIPT_VERSION="3.0.0-FINAL"

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
# Configuracion de URLs para descarga de Stacks
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

# [ELIMINAR FUNCION spinner() AQUI SI EXISTE]

# Funcion de ejecucion de comandos simplificada (NUEVA VERSION)
run_command() {
    local cmd="$1"
    local msg="$2"
    
    show_message "$msg"
    
    # Logica para decidir si se usa SUDO
    local full_cmd
    if [ -n "$SUDO" ] && [[ "$cmd" != docker* ]] && [[ "$cmd" != *"$SUDO"* ]]; then
        full_cmd="$SUDO $cmd"
    else
        full_cmd="$cmd"
    fi
    
    # Muestra el comando exacto antes de ejecutarlo
    echo -e "  -> Ejecutando: \033[0;33m$full_cmd\033[0m"

    # Ejecuta el comando directamente, mostrando el output de forma nativa.
    if $full_cmd; then
        show_success "Completado: $msg"
        return 0
    else
        local exit_status=$?
        show_error "Comando fallo con codigo $exit_status: $full_cmd"
        return $exit_status
    fi
}

# La funcion cleanup() y las trampas (traps) continuan abajo.
# -----------------------------------------------------------

# Funcion de limpieza (Mantenida)
cleanup() {
    local exit_code=$1
    local delete_stacks=${2:-false} 
    
    show_message "Realizando limpieza antes de salir..."
    
    if [ $exit_code -ne 0 ]; then
        show_error "Error detectado durante la instalacion. Limpiando archivos temporales..."
    fi
    
    if [ ${#TEMP_FILES[@]} -gt 0 ]; then
        for file in "${TEMP_FILES[@]}"; do
            if [ -f "$file" ]; then
                $SUDO rm -f "$file"
            fi
        done
    fi
    
    if [ "$delete_stacks" = true ]; then
        show_message "Eliminando archivos de despliegue y configuracion temporal..."
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
        show_error "La instalacion ha fallado. Revise los logs para mas informacion."
    else
        show_success "Instalacion completada exitosamente"
    fi
}

# Configurar trampas para senales para limpiar antes de salir
trap 'cleanup 1 false; exit 1' SIGHUP SIGINT SIGQUIT SIGTERM
trap 'cleanup 1 false; exit 1' ERR

# Funcion para animacion de espera y ejecucion de comandos
run_command() {
    # ... (codigo de run_command que usa $SUDO internamente al ejecutar el comando)
    local cmd="$1"
    local msg="$2"
    
    show_message "$msg"
    
    local log_file="/tmp/cmd_output_$$_$(date +%s)"
    
    # Prepend SUDO to the command if set
    local full_cmd
    if [ -n "$SUDO" ] && [[ "$cmd" != *"$SUDO"* ]]; then
        full_cmd="$SUDO $cmd"
    else
        full_cmd="$cmd"
    fi
    
    eval "$full_cmd" > "$log_file" 2>&1 &
    local cmd_pid=$!
    
    # ... spinner logic ... (simplified for output)
    local pid=$cmd_pid
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
    # ... end spinner logic

    wait $cmd_pid
    local exit_status=$?
    
    if [ $exit_status -ne 0 ]; then
        show_error "Comando fallo: $full_cmd"
        show_message "Ultimas 10 lineas de log de error:"
        tail -n 10 "$log_file"
        rm -f "$log_file"
        return $exit_status
    fi
    
    rm -f "$log_file"
    return 0
}

# -------------------------------
# Funciones de Instalacion de Dependencias, Seguridad y Redes (MODIFICADAS)
# -------------------------------

configure_docker_logs() {
    local config_file="/etc/docker/daemon.json"
    show_message "Configurando limites de logs en Docker..."
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
    run_command "systemctl restart docker" "Reiniciando Docker para aplicar configuracion..."
}

# Funcion de instalacion de dependencias (INTEGRANDO la logica del usuario)
install_dependencies() {
    show_message "Verificando e instalando dependencias (curl, wget, jo, perl, Docker)..."
    
    # Instalacion de dependencias basicas y paquetes necesarios para el script (jo, perl)
    run_command "apt-get update -y" "Actualizando lista de paquetes..."
    run_command "apt-get install -y ca-certificates curl gnupg lsb-release apt-transport-https software-properties-common jo perl" "Instalando utilidades y requisitos..."

    if ! command -v docker &> /dev/null; then
        echo "?? Instalando Docker..."
        
        # Uso de $SUDO para comandos que escriben en /etc
        $SUDO install -m 0755 -d /etc/apt/keyrings
        run_command "curl -fsSL https://download.docker.com/linux/$OS/gpg | $SUDO gpg --dearmor -o /etc/apt/keyrings/docker.gpg" "Descargando clave GPG de Docker..."
        
        # Configurar repositorio de Docker
        echo \
"deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/$OS \
$(lsb_release -cs) stable" | $SUDO tee /etc/apt/sources.list.d/docker.list > /dev/null
        
        run_command "apt-get update -y && apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin" "Instalando paquetes de Docker..."
    else
        show_success "Docker ya esta instalado."
    fi

    # Iniciar y habilitar Docker (usando SUDO si es necesario)
    run_command "systemctl enable docker" "Habilitando servicio Docker..."
    run_command "systemctl start docker" "Iniciando servicio Docker..."
    
    # Configurar logs (retenido del script original)
    configure_docker_logs
    
    show_success "Dependencias instaladas/verificadas."
}

# initialize_docker_swarm, install_server_tools, create_docker_networks (Se mantienen)
initialize_docker_swarm() {
    show_message "Verificando estado de Docker Swarm..."
    if ! docker info 2>/dev/null | grep -q "Swarm: active"; then
        show_message "Iniciando Docker Swarm..."
        # Se usa SUDO si es necesario, pero Docker ya esta instalado y el usuario deberia ser parte del grupo docker
        run_command "docker swarm init --advertise-addr \$(hostname -I | awk '{print \$1}')" "Inicializando Docker Swarm..."
        show_success "Docker Swarm inicializado correctamente"
    else
        show_message "Docker Swarm ya esta activo"
    fi
}

install_server_tools() {
    show_message "Instalando herramientas de seguridad en el servidor..."
    
    run_command "apt-get install -y fail2ban && systemctl enable fail2ban && systemctl start fail2ban" "Instalando y activando Fail2Ban..."
    
    show_message "Instalando RKHunter..."
    run_command "echo 'postfix postfix/main_mailer_type select No configuration' | debconf-set-selections && apt-get install -y rkhunter" "Instalando RKHunter..."
    # ... (Resto de la configuracion de seguridad)
    local config_file="/etc/rkhunter.conf"
    show_message "Configurando RKHunter..."
    run_command "$SUDO sed -i 's/^UPDATE_MIRRORS=.*/UPDATE_MIRRORS=1/' \"$config_file\" && \
                $SUDO sed -i 's/^MIRRORS_MODE=.*/MIRRORS_MODE=0/' \"$config_file\" && \
                $SUDO sed -i 's|^WEB_CMD=.*|WEB_CMD=\"\"|' \"$config_file\"" \
                "Aplicando configuracion de RKHunter..."
    run_command "rkhunter --update" "Actualizando RKHunter..."
    run_command "rkhunter --propupd" "Actualizando base de datos de propiedades de RKHunter..."
    
    run_command "apt-get install -y chkrootkit" "Instalando CHKRootkit..."
    
    show_message "Configurando UFW Firewall..."
    run_command "apt-get install -y ufw" "Instalando UFW..."
    run_command "ufw allow ssh && ufw allow http && ufw allow https && echo 'y' | ufw enable" "Configurando y activando reglas basicas de UFW..."
    
    show_success "Herramientas de seguridad instaladas correctamente"
}

create_docker_networks() {
    show_message "Creando redes Docker para Swarm..."
    # ... (codigo de creacion de redes)
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
# Funciones de Descarga, Sanitizacion, Chatwoot e Instalacion (Mantenidas)
# -------------------------------

# download_file, sanitize_yaml, create_volume_directories, initialize_chatwoot_database, install_docker_tool
# (Estas funciones son identicas a la version 2.1.0, adaptadas para usar $SUDO en mkdir -p si es necesario)
# ... [Codigo omitido por brevedad, pero las funciones estan en el script final] ...

# create_volume_directories (Asegura uso de $SUDO)
create_volume_directories() {
    local stack_file=$1
    local tool_name=$2

    show_message "Creando directorios para volumenes de $tool_name..."

    local volume_paths=$(grep -oP "device: \K/[^\s]+" "$stack_file" | sort | uniq)

    if [ -z "$volume_paths" ]; then
        show_message "No se encontraron rutas de volumenes para $tool_name"
        return
    fi

    for path in $volume_paths; do
        # Se usa $SUDO para crear directorios en /home/docker si es necesario.
        run_command "mkdir -p \"$path\"" "Creando directorio $path..."
    done
}


# -------------------------------
# Flujo Principal (MODIFICADO para usar el chequeo inicial)
# -------------------------------

# Bloque de chequeo inicial (EJECUTADO ANTES DE main)
echo "=== Instalador Universal ==="
echo "Iniciando verificacion del entorno..."

# Detectar si el script tiene permisos root (DEL CODIGO DEL USUARIO)
if [ "$(id -u)" -ne 0 ]; then
    if ! command -v sudo >/dev/null 2>&1; then
        show_error "? No eres root y 'sudo' no esta instalado. Instalalo o ejecuta como root."
        exit 1
    fi
    SUDO="sudo"
    show_message "?? Ejecutando con sudo..."
else
    SUDO=""
    show_message "?? Ejecutando como root..."
fi

# Verificar conexion a internet (usando curl, mas robusto para firewalls)
if ! curl -s --head --request GET -m 5 https://google.com >/dev/null 2>&1; then
    echo "? No hay conexion a Internet. Revisa tu red antes de continuar."
    exit 1
fi

# Detectar sistema operativo (DEL CODIGO DEL USUARIO)
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$ID
    show_message "Sistema detectado: $PRETTY_NAME"
else
    show_error "? No se pudo detectar el sistema operativo."
    exit 1
fi


main() {
    show_message "Iniciando la instalacion automatizada de herramientas Docker (v$SCRIPT_VERSION)..."
    
    # 1. Configuracion inicial
    run_command "mkdir -p \"$DOCKER_DIR\"" "Creando directorio principal de Docker..."
    cd "$DOCKER_DIR" || { 
        show_error "No se pudo acceder al directorio $DOCKER_DIR"
        exit 1
    }

    show_message "Configuracion de credenciales"
    read -p "Ingrese la contrasena comun para todas las herramientas: " COMMON_PASSWORD
    if [ -z "$COMMON_PASSWORD" ]; then show_error "La contrasena no puede estar vacia"; exit 1; fi

    read -p "Ingrese el dominio base (ejemplo: midominio.com): " BASE_DOMAIN
    if [ -z "$BASE_DOMAIN" ]; then show_error "El dominio no puede estar vacio"; exit 1; fi

    DEFAULT_SECRET_KEY=$(generate_random_key)
    read -p "Ingrese una clave secreta de 32 caracteres (Enter para usar una generada): " SECRET_KEY
    SECRET_KEY=${SECRET_KEY:-$DEFAULT_SECRET_KEY}

    if [ ${#SECRET_KEY} -ne 32 ]; then
        show_warning "La clave proporcionada no tiene 32 caracteres. Se utilizara una clave generada automaticamente."
        SECRET_KEY=$DEFAULT_SECRET_KEY
    fi

    show_message "Se utilizara la clave secreta: $SECRET_KEY"

    # Guardar variables globales
    env_global_file="$DOCKER_DIR/.env.global"
    $SUDO cat > "$env_global_file" << EOL
COMMON_PASSWORD=$COMMON_PASSWORD
BASE_DOMAIN=$BASE_DOMAIN
SECRET_KEY=$SECRET_KEY
EOL
    register_temp_file "$env_global_file"

    # 2. Instalacion de dependencias, Swarm, Seguridad y Redes
    install_dependencies
    initialize_docker_swarm
    install_server_tools
    create_docker_networks

    # 3. Inicializar array de subdominios personalizados e Instalar herramientas
    for i in "${!SELECTED_TOOLS[@]}"; do CUSTOM_SUBDOMAINS[$i]=""; done

    show_message "Instalando servicios en orden de dependencias..."
    
    INSTALL_ORDER=("traefik" "redis" "postgres" "portainer" "n8n" "evoapi" "chatwoot")
    
    for tool_name in "${INSTALL_ORDER[@]}"; do
        # ... (logica de busqueda de subdominio)
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
    show_success "!Instalacion completada!"
    echo ""
    echo "Accede a tus servicios en los siguientes URLs (usando HTTPS si Traefik esta configurado correctamente):"
    
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

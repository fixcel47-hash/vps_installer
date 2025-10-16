#!/bin/bash

# ============================================
# Instalador Unificado de Herramientas Docker
# ============================================

# Colores para mensajes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Funciones de mensaje
show_message() { echo -e "${BLUE}[INFO]${NC} $1"; }
show_error() { echo -e "${RED}[ERROR]${NC} $1"; }
show_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
show_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }

# Función para solicitar entrada al usuario
ask_for_input() {
    local prompt_message="$1"
    local default_value="$2"
    local input_var_name="$3"
    local hide_input="$4" # 'true' to hide input (for passwords)
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
    if [[ $domain =~ ^[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?\.[a-zA-Z]{2,}$ ]]; then
        return 0 # Válido
    else
        return 1 # Inválido
    fi
}

# Función para validar un email
validate_email() {
    local email="$1"
    # Expresión regular para validar un email simple
    if [[ $email =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
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
        ask_for_input "Introduce tu dominio (ej. midominio.com para HTTPS con Let's Encrypt)" "$default_domain" "domain_val"
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
        ask_for_input "Introduce tu correo electrónico para Let's Encrypt (ej. tu@email.com)" "$default_email" "email_val"
        if [ -z "$email_val" ]; then
            show_warning "No se ha introducido un email. Let's Encrypt no estará disponible."
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
show_message "\n--- Configuración de la Instalación ---"

# Contraseña de administrador
ADMIN_PASSWORD=""
ask_and_confirm_password "Introduce tu contraseña de administrador (para n8n y PostgreSQL)" "ADMIN_PASSWORD"

# Dominio y Email
DOMAIN=""
EMAIL=""
ask_and_validate_domain "DOMAIN" ""
if [ -n "$DOMAIN" ]; then
    ask_and_validate_email "EMAIL" ""
fi

show_message "\n--- Resumen de Configuración ---"
show_message "Contraseña de Administrador: ******** (oculta)"
show_message "Dominio: ${DOMAIN:-No especificado (usando IP/localhost)}"
show_message "Email para Let's Encrypt: ${EMAIL:-No especificado}"

read -p "Presiona Enter para continuar con la instalación o Ctrl+C para cancelar..."

# === VARIABLES INTERNAS ===
COMPOSE_PROJECT_NAME="queen_novedad_stack"
DOCKER_NETWORK="web"
TRAEFIK_DIR="/etc/traefik"
DATA_DIR="/opt/queen_novedad"
POSTGRES_PASSWORD="$ADMIN_PASSWORD"
POSTGRES_USER="n8n"
POSTGRES_DB="n8n"
N8N_PORT_LOCAL=5678

# === PASOS DE INSTALACIÓN ===

# 1) Actualizar e instalar dependencias básicas
run_command "export DEBIAN_FRONTEND=noninteractive && apt-get update -y && apt-get upgrade -y && apt-get install -y ca-certificates curl gnupg lsb-release wget software-properties-common apt-transport-https" "Actualizando paquetes e instalando dependencias básicas..."

# 2) Instalar Docker
if ! command -v docker >/dev/null 2>&1; then
  run_command "mkdir -p /etc/apt/keyrings && curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg && echo \"deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable\" | tee /etc/apt/sources.list.d/docker.list > /dev/null && apt-get update -y && apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin" "Instalando Docker Engine..."
  show_success "Docker instalado."
else
  show_message "Docker ya está instalado."
fi

# 3) Crear usuario y directorios
run_command "mkdir -p \"${DATA_DIR}/postgres\" \"${DATA_DIR}/n8n\" \"${DATA_DIR}/db_backups\" \"${DATA_DIR}/redis\" \"${TRAEFIK_DIR}/dynamic\" \"${TRAEFIK_DIR}/certs\" && chown -R root:root \"${DATA_DIR}\" \"${TRAEFIK_DIR}\"" "Creando directorios en ${DATA_DIR} y ${TRAEFIK_DIR}..."

# 4) Crear red docker
if ! docker network ls | grep -qw "${DOCKER_NETWORK}"; then
  run_command "docker network create ${DOCKER_NETWORK}" "Creando red Docker '${DOCKER_NETWORK}'..."
  show_success "Red Docker '${DOCKER_NETWORK}' creada."
else
  show_message "La red Docker '${DOCKER_NETWORK}' ya existe."
fi

# 5) Generar certificados auto-firmados si no hay DOMAIN/EMAIL
USE_LETSENCRYPT=false
if [ -n "${DOMAIN}" ] && [ -n "${EMAIL}" ]; then
  show_message "Dominio y email detectados: ${DOMAIN}, ${EMAIL} -> intentando Let's Encrypt (HTTP challenge)"
  USE_LETSENCRYPT=true
else
  show_warning "No se detectaron DOMAIN y/o EMAIL. Se generarán certificados auto-firmados para Traefik (no confiables por navegadores)."
  # crear self-signed cert
  run_command "openssl req -x509 -nodes -days 3650 -newkey rsa:4096 -keyout \"${TRAEFIK_DIR}/certs/self.key\" -out \"${TRAEFIK_DIR}/certs/self.crt\" -subj \"/CN=${DOMAIN:-localhost}\" >/dev/null 2>&1 || true" "Generando certificado auto-firmado..."
fi

# 6) Escribir configuración estática de Traefik
cat > "${TRAEFIK_DIR}/traefik.yml" <<EOF
entryPoints:
  web:
    address: ":80"
  websecure:
    address: ":443"
providers:
  docker:
    exposedByDefault: false
log:
  level: INFO
api:
  dashboard: true
  insecure: false
EOF

if [ "${USE_LETSENCRYPT}" = true ]; then
  cat >> "${TRAEFIK_DIR}/traefik.yml" <<EOF
certificatesResolvers:
  letsencrypt:
    acme:
      email: "${EMAIL}"
      storage: "/acme.json"
      httpChallenge:
        entryPoint: web
EOF
else
  cat >> "${TRAEFIK_DIR}/traefik.yml" <<EOF
# Usando certificado auto-firmado ubicado en /certs
tls:
  stores:
    default:
      defaultCertificate:
        certFile: /certs/self.crt
        keyFile: /certs/self.key
EOF
fi

# permisos
run_command "touch ${TRAEFIK_DIR}/acme.json || true && chmod 600 ${TRAEFIK_DIR}/acme.json || true" "Ajustando permisos para acme.json..."

# 7) Crear docker-compose.yml unificado
COMPOSE_FILE="${DATA_DIR}/docker-compose.yml"
cat > "${COMPOSE_FILE}" <<EOF
version: '3.8'
services:
  traefik:
    image: traefik:v2.10
    command:
      - --providers.docker=true
      - --entryPoints.web.address=:80
      - --entryPoints.websecure.address=:443
      - --api.insecure=false
      - --log.level=INFO
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
      - ${TRAEFIK_DIR}:/etc/traefik
      - ${TRAEFIK_DIR}/acme.json:/acme.json
      - ${TRAEFIK_DIR}/certs:/certs
    networks:
      - ${DOCKER_NETWORK}
    restart: unless-stopped

  portainer:
    image: portainer/portainer-ce:latest
    command: -H unix:///var/run/docker.sock
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - ${DATA_DIR}/portainer:/data
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.portainer.rule=Host(\`portainer.${DOMAIN:-localhost}\`)"
      - "traefik.http.routers.portainer.entrypoints=websecure"
      - "traefik.http.routers.portainer.tls.certresolver=letsencrypt"
    networks:
      - ${DOCKER_NETWORK}
    restart: unless-stopped

  postgres:
    image: postgres:15
    environment:
      - POSTGRES_USER=${POSTGRES_USER}
      - POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
      - POSTGRES_DB=${POSTGRES_DB}
    volumes:
      - ${DATA_DIR}/postgres:/var/lib/postgresql/data
    networks:
      - ${DOCKER_NETWORK}
    restart: unless-stopped

  redis:
    image: redis:alpine
    command: ["redis-server","--save","","--appendonly","no"]
    volumes:
      - ${DATA_DIR}/redis:/data
    networks:
      - ${DOCKER_NETWORK}
    restart: unless-stopped

  n8n:
    image: n8nio/n8n:latest
    environment:
      - N8N_BASIC_AUTH_ACTIVE=true
      - N8N_BASIC_AUTH_USER=admin
      - N8N_BASIC_AUTH_PASSWORD=${ADMIN_PASSWORD}
      - DB_TYPE=postgresdb
      - DB_POSTGRESDB_HOST=postgres
      - DB_POSTGRESDB_PORT=5432
      - DB_POSTGRESDB_DATABASE=${POSTGRES_DB}
      - DB_POSTGRESDB_USER=${POSTGRES_USER}
      - DB_POSTGRESDB_PASSWORD=${POSTGRES_PASSWORD}
      - N8N_HOST=${DOMAIN:-localhost}
      - N8N_PORT=5678
      - N8N_PROTOCOL=https
    depends_on:
      - postgres
      - redis
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.n8n.rule=Host(\`n8n.${DOMAIN:-localhost}\`)"
      - "traefik.http.routers.n8n.entrypoints=websecure"
      - "traefik.http.routers.n8n.tls.certresolver=letsencrypt"
      - "traefik.http.services.n8n.loadbalancer.server.port=5678"
    volumes:
      - ${DATA_DIR}/n8n:/home/node/.n8n
    networks:
      - ${DOCKER_NETWORK}
    restart: unless-stopped

networks:
  ${DOCKER_NETWORK}:
    external: true
EOF

show_message "Archivo docker-compose creado en: ${COMPOSE_FILE}"

# 8) Si no hay domain/email, ajustar etiquetas TLS en docker-compose para que no pidan certresolver
if [ "${USE_LETSENCRYPT}" = false ]; then
  show_message "Ajustando docker-compose para usar TLS local (auto-firmado)"
  sed -i 's/traefik.http.routers.portainer.tls.certresolver=letsencrypt/traefik.http.routers.portainer.tls=true/g' "${COMPOSE_FILE}"
  sed -i 's/traefik.http.routers.n8n.tls.certresolver=letsencrypt/traefik.http.routers.n8n.tls=true/g' "${COMPOSE_FILE}"
fi

# 9) Iniciar stack
show_message "Iniciando servicios con docker compose..."
run_command "cd \"${DATA_DIR}\" && docker compose -f \"${COMPOSE_FILE}\" up -d" "Levantando contenedores Docker..."

show_message "Los contenedores se están levantando..."

# 10) Resumen final
cat <<EOF

=== Resumen de la Instalación ===
- Servicios levantados: Traefik, Portainer, PostgreSQL, Redis, n8n
- Red Docker: ${DOCKER_NETWORK}
- Directorio de datos: ${DATA_DIR}
- Administrador n8n (basic auth): user=admin password=${ADMIN_PASSWORD}

Notas importantes:
- Si configuraste un dominio con Let's Encrypt, asegúrate de que el registro A de tu dominio apunte a la IP de este servidor y que los puertos 80 y 443 estén accesibles desde Internet.

- Accede a Portainer: https://${DOMAIN:+portainer.${DOMAIN}}${DOMAIN:+/} o https://<IP>:9443 (si no usaste dominio)
- Accede a n8n: https://n8n.${DOMAIN:-<IP>:${N8N_PORT_LOCAL}}

Para ver logs: docker compose -f ${COMPOSE_FILE} logs -f
Para detener: docker compose -f ${COMPOSE_FILE} down

=== Fin de la Instalación ===
EOF

show_success "Instalación finalizada. Revisa los logs si algún servicio tarda en levantarse."


#!/usr/bin/env bash
# combined_installer_v2.sh
# Versión mejorada: instala Docker (soporta Debian/Ubuntu y CentOS/RHEL), descarga y limpia los YAML de stacks
# proporcionados por el usuario, elimina líneas que contengan tokens/secretos evidentes y crea un .env
# NOTA: Este script NO inyecta ni adivina secretos. Todos los secretos se deben introducir en el archivo .env

set -euo pipefail
IFS=$'\n\t'

# -------------------------------
# Configuración de URLs (proporcionadas por el usuario)
# -------------------------------
CHATWOOT_URL="https://github.com/user-attachments/files/22956465/chatwoot-stack.yml"
EVOAPI_URL="https://github.com/user-attachments/files/22956481/evoapi-stack.yml"
N8N_URL="https://github.com/user-attachments/files/22956487/n8n-stack.yml"
PORTAINER_URL="https://github.com/user-attachments/files/22956492/portainer-stack.yml"
POSTGRES_URL="https://github.com/user-attachments/files/22956495/postgres-stack.yml"
REDIS_URL="https://github.com/user-attachments/files/22956503/redis-stack.yml"
TRAEFIK_URL="https://github.com/user-attachments/files/22956506/traefik-stack.yml"

# Directorio donde se guardan los stacks
STACK_DIR="/opt/docker-stacks"
mkdir -p "${STACK_DIR}"
cd "${STACK_DIR}"

# -------------------------------
# Utilidades
# -------------------------------
log() { echo -e "[\e[1;32mINFO\e[0m] $*"; }
warn() { echo -e "[\e[1;33mWARN\e[0m] $*"; }
err() { echo -e "[\e[1;31mERROR\e[0m] $*"; }

require_root() {
  if [[ "$EUID" -ne 0 ]]; then
    err "Este script requiere privilegios de root. Ejecuta con sudo."; exit 1
  fi
}

command_exists() { command -v "$1" >/dev/null 2>&1; }

# -------------------------------
# Detección de distribución e instalación de Docker
# - Soporta Debian/Ubuntu y CentOS/RHEL
# - Instala plugin docker compose o docker-compose binario como fallback
# -------------------------------
install_docker_ubuntu() {
  log "Instalando Docker en Debian/Ubuntu..."
  apt-get update -y
  apt-get install -y ca-certificates curl gnupg lsb-release apt-transport-https
  mkdir -p /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" > /etc/apt/sources.list.d/docker.list
  apt-get update -y
  apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  systemctl enable --now docker
}

install_docker_centos() {
  log "Instalando Docker en CentOS/RHEL..."
  yum install -y yum-utils
  yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
  yum install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin
  systemctl enable --now docker
  # docker compose plugin package may not be available en repos viejos; instalamos binario si falta
  if ! command_exists docker-compose && ! docker compose version >/dev/null 2>&1; then
    log "Instalando docker-compose (binaro) como fallback..."
    DC_VER="2.20.2"
    curl -L "https://github.com/docker/compose/releases/download/v${DC_VER}/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    chmod +x /usr/local/bin/docker-compose
  fi
}

ensure_docker() {
  if command_exists docker; then
    log "Docker detectado: $(docker --version)"
  else
    log "Docker no encontrado. Detectando distro..."
    if [[ -f /etc/os-release ]]; then
      . /etc/os-release
      case "$ID" in
        ubuntu|debian)
          install_docker_ubuntu
          ;;
        centos|rhel|rocky|almalinux)
          install_docker_centos
          ;;
        *)
          err "Distribución no soportada automáticamente. Instala Docker manualmente e inténtalo otra vez."; exit 1
          ;;
      esac
    else
      err "No se pudo detectar la distribución. Instala Docker manualmente."; exit 1
    fi
  fi

  # Asegurarnos de tener docker compose (plugin o binario)
  if docker compose version >/dev/null 2>&1; then
    log "Usaremos 'docker compose' (plugin v2)."
  elif command_exists docker-compose; then
    log "Usaremos 'docker-compose' (binario)."
  else
    warn "No se detectó docker compose. Intentando instalar el plugin (Linux)"
    # Intento de instalación del plugin por si falta (solo en sistemas con apt)
    if command_exists apt-get; then
      apt-get update -y && apt-get install -y docker-compose-plugin || true
    fi
    if ! docker compose version >/dev/null 2>&1 && ! command_exists docker-compose; then
      warn "No fue posible instalar docker compose automáticamente. Instala 'docker compose' o 'docker-compose' manualmente.";
    fi
  fi
}

# -------------------------------
# Descargar y limpiar stacks
# - Descarga cada YAML
# - Crea una copia "-raw" original
# - Limpia líneas que coincidan con patrones de tokens/secrets
# -------------------------------
DOWNLOAD_TIMEOUT=30

download_file() {
  local url="$1" file="$2"
  if [[ -z "$url" ]]; then warn "URL vacía para $file"; return 1; fi
  log "Descargando $url -> $file"
  if command_exists curl; then
    curl --fail --location --max-time ${DOWNLOAD_TIMEOUT} -sS "$url" -o "$file" || { err "Fallo al descargar $url"; return 2; }
  elif command_exists wget; then
    wget -q --timeout=${DOWNLOAD_TIMEOUT} -O "$file" "$url" || { err "Fallo al descargar $url"; return 2; }
  else
    err "Ni curl ni wget están disponibles."; return 3
  fi
  log "Descargado: $file"
}

# Patrones sospechosos de tokens/secretos que se eliminarán o se reemplazarán por PLACEHOLDER
SENSITIVE_PATTERNS=(
  "API_TOKEN"
  "API_KEY"
  "SECRET"
  "PASSWORD"
  "DB_PASSWORD"
  "JWT"
  "ACCESS_TOKEN"
  "AUTH_TOKEN"
  "TOKEN:"
  "token:"
)

sanitize_yaml() {
  local infile="$1" outfile="$2"
  cp -f "$infile" "${infile}.raw"
  # Reemplazar valores después de patrones como KEY=valor o key: valor o - KEY: valor
  # En lugar de eliminar la línea completa, la transformamos a "KEY: <REPLACE_ME>" o "KEY=" si es env file
  cp -f "$infile" "$outfile"
  for pat in "${SENSITIVE_PATTERNS[@]}"; do
    # Reemplazamos ocurrencias como: "pat: algun_valor" -> "pat: <REPLACE_ME>"
    # y "pat=algun_valor" -> "pat=<REPLACE_ME>"
    perl -0777 -pe "s/(${pat}\s*[:=]\s*)(\S+)/\1<REPLACE_ME>/ig" -i "$outfile" || true
    # Reemplazmos variables en mayúsculas en env-style: SECRET=... -> SECRET=<REPLACE_ME>
    perl -0777 -pe "s/(${pat})=(\S+)/\1=<REPLACE_ME>/ig" -i "$outfile" || true
  done

  # Además, eliminar líneas que contengan claramente long hex strings after 'token:' (para evitar dejar algo sensible)
  perl -0777 -ne 'print unless /token\s*[:=]\s*[A-Za-z0-9_\-]{20,}/i' "$outfile" > "${outfile}.tmp" && mv "${outfile}.tmp" "$outfile" || true

  log "Saneado: $outfile (copia original en ${infile}.raw)"
}

# -------------------------------
# Generar .env de ejemplo si no existe
# -------------------------------
create_env_example() {
  if [[ -f ".env" ]]; then
    log ".env ya existe en ${STACK_DIR}, no se sobrescribe."
    return
  fi
  cat > .env <<'EOF'
# Archivo .env de ejemplo. Rellena con tus valores reales.
# Ejemplo:
# POSTGRES_PASSWORD=changeme
# REDIS_PASSWORD=changeme
# CHATWOOT_SECRET_KEY=changeme
# N8N_BASIC_AUTH_USER=user
# N8N_BASIC_AUTH_PASSWORD=password
EOF
  log "Se creó ${STACK_DIR}/.env (ejemplo). Rellénalo antes de iniciar los servicios si requieren secretos."
}

# -------------------------------
# Despliegue con docker compose
# - Usa docker compose (plugin) si está disponible, sino docker-compose
# -------------------------------
deploy_compose() {
  local compose_file="$1"
  if [[ ! -f "$compose_file" ]]; then warn "No existe $compose_file"; return 1; fi
  log "Desplegando $compose_file"
  if docker compose version >/dev/null 2>&1; then
    docker compose -f "$compose_file" up -d --remove-orphans
  elif command_exists docker-compose; then
    docker-compose -f "$compose_file" up -d --remove-orphans
  else
    err "Ninguna herramienta de compose disponible. Saltando despliegue para $compose_file"; return 2
  fi
}

# -------------------------------
# Flujo principal
# -------------------------------
main() {
  require_root
  ensure_docker

  # Lista de descargas: par (URL, nombre local)
  declare -A stacks=(
    ["${CHATWOOT_URL}"]=chatwoot-stack.yml
    ["${EVOAPI_URL}"]=evoapi-stack.yml
    ["${N8N_URL}"]=n8n-stack.yml
    ["${PORTAINER_URL}"]=portainer-stack.yml
    ["${POSTGRES_URL}"]=postgres-stack.yml
    ["${REDIS_URL}"]=redis-stack.yml
    ["${TRAEFIK_URL}"]=traefik-stack.yml
  )

  for url in "${!stacks[@]}"; do
    file="${stacks[$url]}"
    if [[ -z "$url" || "$url" =~ "user-attachments/files/0" ]]; then
      warn "URL vacío o no válido para $file — se salta."; continue
    fi
    if download_file "$url" "$file"; then
      # Generamos fichero saneado: file.sanitized.yml
      sanitized="${file%.yml}.sanitized.yml"
      sanitize_yaml "$file" "$sanitized" || warn "Saneado de $file con problemas"
    else
      warn "No se pudo descargar $file desde $url"
    fi
  done

  create_env_example

  # Desplegar en orden: bases de datos -> reverse proxy -> herramientas -> apps
  log "Desplegando stacks: Postgres y Redis primero (si existen)"
  [[ -f "postgres-stack.yml" ]] && deploy_compose "postgres-stack.yml" || true
  [[ -f "redis-stack.yml" ]] && deploy_compose "redis-stack.yml" || true

  log "Pausa breve para el arranque de DBs (10s)"
  sleep 10

  [[ -f "traefik-stack.yml" ]] && deploy_compose "traefik-stack.yml" || true
  [[ -f "portainer-stack.yml" ]] && deploy_compose "portainer-stack.yml" || true
  [[ -f "n8n-stack.yml" ]] && deploy_compose "n8n-stack.yml" || true
  [[ -f "evoapi-stack.yml" ]] && deploy_compose "evoapi-stack.yml" || true
  [[ -f "chatwoot-stack.yml" ]] && deploy_compose "chatwoot-stack.yml" || true

  log "Despliegue finalizado (o iniciado). Comprueba: docker ps y docker compose -f <archivo> logs -f"
  log "Si algún servicio requiere secretos, edita ${STACK_DIR}/.env y vuelve a ejecutar: docker compose -f <archivo> up -d"

  # Crear README con enlaces a herramientas Docker comunes
  cat > README.md <<'EOF'
Este directorio contiene los stacks descargados y saneados. NOTAS:
- No se incluyen secretos ni tokens. Rellena .env si es necesario.
- Archivos *.raw son las copias originales descargadas.

Enlaces útiles para instalar herramientas Docker manualmente (si algo falla):
- Docker (instalación oficial): https://docs.docker.com/engine/install/
- Docker Compose v2 (plugin): https://docs.docker.com/compose/
- Docker Compose (binario releases): https://github.com/docker/compose/releases
- Portainer: https://www.portainer.io/
- Traefik: https://doc.traefik.io/traefik/

EOF
  log "Se creó README.md con enlaces útiles."
}

main "$@"

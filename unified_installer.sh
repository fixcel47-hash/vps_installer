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



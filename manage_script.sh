#!/bin/bash

# ============================================
# Script de Gestión de Servicios Docker
# ============================================

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[0;33m'
NC='\033[0m'

show_message() { echo -e "${BLUE}[INFO]${NC} $1"; }
show_error() { echo -e
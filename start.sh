#!/bin/bash

# --- COULEURS ---
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# --- FONCTION D'ANIMATION (SPINNER AVEC CHRONO) ---
# usage : <commande> & ; spinner $! "Message"
spinner() {
    local pid=$1
    local msg=$2
    local delay=0.2
    local spinstr='|/-\'
    local start=$(date +%s)
    tput civis 2>/dev/null
    while ps -p "$pid" > /dev/null 2>&1; do
        local elapsed=$(( $(date +%s) - start ))
        local c=${spinstr#?}
        printf "\r${CYAN}%s${NC} [%c] ${YELLOW}%ds${NC}   " "$msg" "$spinstr" "$elapsed"
        spinstr=$c${spinstr%"$c"}
        sleep $delay
    done
    tput cnorm 2>/dev/null
    printf "\r\033[K"
}

clear

# ==============================================================================
# 0. DÉTECTION DE LA LANGUE
# ==============================================================================
# On vérifie si un argument est passé (ex: ./start.sh FR)
if [[ "$1" == "FR" ]]; then
    LAN_CHOICE="2"
elif [[ "$1" == "EN" ]]; then
    LAN_CHOICE="1"
else
    # Sinon, on demande
    echo -e "${BLUE}==============================================${NC}"
    echo -e "${BLUE}   CLOUTIK LAUNCHER                           ${NC}"
    echo -e "${BLUE}==============================================${NC}"
    echo "  1) English"
    echo "  2) Français"
    read -p "Choice / Choix [1-2]: " LAN_CHOICE
fi

if [ "$LAN_CHOICE" == "2" ]; then
    # --- FRANÇAIS ---
    T_TITLE="LANCEMENT CLOUTIK (MODE VISUEL)"
    T_CHECKING="Vérification de l'environnement..."
    T_ERR_DOCKER="[ERREUR] Docker est requis."
    T_ERR_COMPOSE="[ERREUR] Docker Compose est requis."
    T_ERR_ENV="[ERREUR] Fichier .env manquant."

    T_PHASE1="[PHASE 1] Initialisation des services essentiels"
    T_PULL="→ Téléchargement des images (Pull)..."
    T_ERR_PULL="[ERREUR] Le téléchargement a échoué."
    T_START_CORE="→ Démarrage des conteneurs..."
    T_ERR_START="[ERREUR] Le démarrage a échoué."

    T_PHASE2="[PHASE 2] Vérification de la disponibilité"
    T_TARGET="Cible :"
    T_WAIT="En attente de réponse HTTP 200..."
    T_TIMEOUT="[TIMEOUT] Le système ne répond pas."
    T_DIAG="Diagnostic :"
    T_FIRSTRUN_NOTE="(Première initialisation : peut prendre plusieurs minutes, merci de patienter)"
    T_STEP_BOOT="Démarrage des services..."
    T_STEP_INIT="Initialisation (base de données, assets)..."
    T_STEP_FINAL="Finalisation, presque prêt..."

    T_PHASE3="[PHASE 3] Activation du monitoring"
    T_START_MONITOR="→ Démarrage des services de logs..."

    T_SUCCESS="APPLICATION DÉMARRÉE AVEC SUCCÈS !"
    T_ACCESS="Accédez à votre application ici :"
else
    # --- ENGLISH ---
    T_TITLE="CLOUTIK LAUNCHER (VISUAL MODE)"
    T_CHECKING="Checking environment..."
    T_ERR_DOCKER="[ERROR] Docker is required."
    T_ERR_COMPOSE="[ERROR] Docker Compose is required."
    T_ERR_ENV="[ERROR] .env file is missing."

    T_PHASE1="[PHASE 1] Initializing Essential Services"
    T_PULL="→ Downloading images (Pull)..."
    T_ERR_PULL="[ERROR] Pull failed."
    T_START_CORE="→ Starting containers..."
    T_ERR_START="[ERROR] Start failed."

    T_PHASE2="[PHASE 2] Health Check"
    T_TARGET="Target:"
    T_WAIT="Waiting for HTTP 200 response..."
    T_TIMEOUT="[TIMEOUT] System is not responding."
    T_DIAG="Diagnostic:"
    T_FIRSTRUN_NOTE="(First-time setup: may take several minutes, please wait)"
    T_STEP_BOOT="Starting services..."
    T_STEP_INIT="Initializing (database, assets)..."
    T_STEP_FINAL="Finalizing, almost ready..."

    T_PHASE3="[PHASE 3] Enabling Monitoring"
    T_START_MONITOR="→ Starting log services..."

    T_SUCCESS="APPLICATION STARTED SUCCESSFULLY!"
    T_ACCESS="Access your application here:"
fi

# ==============================================================================
# 1. PRÉPARATION
# ==============================================================================
if [ -z "$1" ]; then clear; fi # On clear seulement si on est en mode interactif
echo -e "${BLUE}==============================================${NC}"
echo -e "${BLUE}   $T_TITLE ${NC}"
echo -e "${BLUE}==============================================${NC}"

# ... (Vérifications habituelles inchangées) ...
if ! command -v docker &> /dev/null; then echo -e "${RED}$T_ERR_DOCKER${NC}"; exit 1; fi
if docker compose version >/dev/null 2>&1; then COMPOSE="docker compose"; elif command -v docker-compose >/dev/null 2>&1; then COMPOSE="docker-compose"; else echo -e "${RED}$T_ERR_COMPOSE${NC}"; exit 1; fi
if [ ! -f .env ]; then echo -e "${RED}$T_ERR_ENV${NC}"; exit 1; fi

APP_URL=$(grep "^APP_URL=" .env | cut -d '=' -f2)
LOGIN_URL="${APP_URL}/login"

# ==============================================================================
# PHASE 1 : CŒUR DU SYSTÈME
# ==============================================================================
echo -e "\n${BLUE}$T_PHASE1${NC}"

# 1. TÉLÉCHARGEMENT (sortie masquée : ne pas exposer les noms de service)
$COMPOSE pull > /dev/null 2>&1 &
PID=$!
spinner $PID "$T_PULL"
wait $PID
EXIT_CODE=$?

if [ $EXIT_CODE -ne 0 ]; then echo -e "${RED}$T_ERR_PULL${NC}"; exit 1; fi
echo -e "${CYAN}$T_PULL${NC} ${GREEN}[OK]${NC}"

# 2. DÉMARRAGE (Avec animation Spinner)
$COMPOSE up -d --remove-orphans > /dev/null 2>&1 &
PID=$!
spinner $PID "$T_START_CORE"
wait $PID
EXIT_CODE=$?

if [ $EXIT_CODE -eq 0 ]; then
    echo -e "${CYAN}$T_START_CORE${NC} ${GREEN}[OK]${NC}"
else
    echo -e "${RED}$T_ERR_START${NC}"
    exit 1
fi

mkdir -p storage/framework/{cache,sessions,views} storage/logs bootstrap/cache logs/laravel

sudo chown -R 33:33 storage bootstrap/cache logs/laravel 2>/dev/null || chown -R 33:33 storage bootstrap/cache logs/laravel
sudo chmod -R 775 storage bootstrap/cache logs/laravel 2>/dev/null || chmod -R 775 storage bootstrap/cache logs/laravel


# ==============================================================================
# PHASE 2 : VÉRIFICATION DE SANTÉ (COMPTEUR)
# ==============================================================================
echo -e "\n${BLUE}$T_PHASE2${NC}"
echo -e "$T_TARGET $LOGIN_URL"

echo -e "${YELLOW}$T_FIRSTRUN_NOTE${NC}"

MAX_RETRIES=60
COUNT=0
SUCCESS=false

while [ $COUNT -lt $MAX_RETRIES ]; do
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -k "$LOGIN_URL")

    if [[ "$HTTP_CODE" == "200" ]]; then
        SUCCESS=true
        printf "\r\033[K"
        echo -e "$T_WAIT ${GREEN}[OK] ($((COUNT * 5))s)${NC}"
        break
    fi

    ELAPSED=$((COUNT * 5))
    if   [ $ELAPSED -lt 30 ];  then STEP="$T_STEP_BOOT"
    elif [ $ELAPSED -lt 120 ]; then STEP="$T_STEP_INIT"
    else                            STEP="$T_STEP_FINAL"
    fi
    printf "\r\033[K  ${CYAN}%s${NC} ${YELLOW}%ds${NC}" "$STEP" "$ELAPSED"

    sleep 5
    ((COUNT++))
done

if [ "$SUCCESS" = false ]; then
    echo -e "\n\n${RED}$T_TIMEOUT${NC}"
    echo -e "$T_DIAG $COMPOSE logs app"
    exit 1
fi

# ==============================================================================
# PHASE 3 : SERVICES ADDITIONNELS
# ==============================================================================
echo -e "\n${BLUE}$T_PHASE3${NC}"

$COMPOSE up -d --remove-orphans > /dev/null 2>&1 &
PID=$!
spinner $PID "$T_START_MONITOR"
wait $PID

echo -e "${CYAN}$T_START_MONITOR${NC} ${GREEN}[OK]${NC}"

mkdir -p storage/framework/{cache,sessions,views} storage/logs bootstrap/cache logs/laravel

sudo chown -R 33:33 storage bootstrap/cache logs/laravel 2>/dev/null || chown -R 33:33 storage bootstrap/cache logs/laravel
sudo chmod -R 775 storage bootstrap/cache logs/laravel 2>/dev/null || chmod -R 775 storage bootstrap/cache logs/laravel



echo -e "\n${GREEN}==============================================${NC}"
echo -e "${GREEN}   $T_SUCCESS             ${NC}"
echo -e "${GREEN}==============================================${NC}"
echo -e "$T_ACCESS $APP_URL"
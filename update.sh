#!/bin/bash
set -uo pipefail   # -u: variables non définies = erreur ; pas de -e (on gère les erreurs à la main)

# ==============================================================================
# 0. AUTO-MAJ DES FICHIERS D'INSTALL (compose, scripts) PUIS RELANCE
# ==============================================================================
if [ "${CK_SELF_UPDATED:-0}" != "1" ] && [ -d .git ]; then
    if git fetch origin &> /dev/null && git reset --hard origin/main &> /dev/null; then
        export CK_SELF_UPDATED=1
        exec bash "$0" "$@"
    fi
fi

# --- COULEURS ---
GREEN='\033[0;32m'; BLUE='\033[0;34m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'

# --- SPINNER (repris de start.sh : chrono + message) ---
spinner() {
    local pid=$1 msg=$2 delay=0.2 spinstr='|/-\' start; start=$(date +%s)
    tput civis 2>/dev/null
    while ps -p "$pid" > /dev/null 2>&1; do
        local elapsed=$(( $(date +%s) - start )) c=${spinstr#?}
        printf "\r${CYAN}%s${NC} [%c] ${YELLOW}%ds${NC}   " "$msg" "$spinstr" "$elapsed"
        spinstr=$c${spinstr%"$c"}; sleep $delay
    done
    tput cnorm 2>/dev/null; printf "\r\033[K"
}

# --- Lecture robuste d'une clé .env (gère guillemets / CRLF / '=' dans la valeur) ---
read_env() { grep -E "^$1=" .env | head -n1 | cut -d= -f2- | tr -d '"\r' | sed 's/[[:space:]]*$//'; }

# --- Log docker (affiché seulement en cas d'échec) ---
LOG=$(mktemp); cleanup() { rm -f "$LOG"; tput cnorm 2>/dev/null; }; trap cleanup EXIT

clear
echo -e "${BLUE}==============================================${NC}"
echo -e "${BLUE}   CLOUTIK UPDATE MANAGER                     ${NC}"
echo -e "${BLUE}==============================================${NC}"

# ==============================================================================
# 1. LANGUE
# ==============================================================================
echo "  1) English"; echo "  2) Français"
read -p "Choice / Choix [1-2]: " LAN_CHOICE
if [ "$LAN_CHOICE" == "2" ]; then
    T_REQ_VER="Quelle version (TAG) installer ? (ex: 1.2.0) : "
    T_STOPPING="Arrêt des services..."; T_PULLING="Téléchargement de la version"
    T_WAIT_HTTP="En attente de réponse HTTP 200..."; T_SUCCESS="Mise à jour terminée avec succès !"
    T_ERR_ENV="Fichier .env introuvable."; T_ERR_DOCKER="Docker Compose introuvable."
    T_HEALTH="Vérification de santé..."; T_FIRSTRUN="(La migration peut prendre plusieurs minutes, patientez)"
    T_ROLLBACK="Échec détecté → restauration de la version précédente..."; T_ROLLBACK_OK="Ancienne version restaurée."
    T_PULL_FAIL="Échec du téléchargement — ancienne version conservée."
else
    T_REQ_VER="Which version (TAG) to install? (e.g., 1.2.0) : "
    T_STOPPING="Stopping services..."; T_PULLING="Pulling version"
    T_WAIT_HTTP="Waiting for HTTP 200 response..."; T_SUCCESS="Update completed successfully!"
    T_ERR_ENV=".env file not found."; T_ERR_DOCKER="Docker Compose not found."
    T_HEALTH="Health check..."; T_FIRSTRUN="(Migration may take several minutes, please wait)"
    T_ROLLBACK="Failure detected → rolling back to previous version..."; T_ROLLBACK_OK="Previous version restored."
    T_PULL_FAIL="Pull failed — previous version kept running."
fi

# ==============================================================================
# 2. VÉRIFICATIONS
# ==============================================================================
[ -f .env ] || { echo -e "${RED}[ERROR] $T_ERR_ENV${NC}"; exit 1; }
if docker compose version >/dev/null 2>&1; then COMPOSE="docker compose"
elif command -v docker-compose >/dev/null 2>&1; then COMPOSE="docker-compose"
else echo -e "${RED}[ERROR] $T_ERR_DOCKER${NC}"; exit 1; fi

APP_URL=$(read_env APP_URL); LOGIN_URL="${APP_URL}/login"; CURRENT_TAG=$(read_env TAG)
echo -e "\n${YELLOW}Current Version: ${CURRENT_TAG:-<none>}${NC}"

# ==============================================================================
# 3. VERSION CIBLE (arg ./update.sh 1.0.5 ou saisie)
# ==============================================================================
if [ -n "${1:-}" ]; then NEW_TAG=$1; else read -p "$T_REQ_VER" NEW_TAG; fi
[ -z "$NEW_TAG" ] && { echo -e "${RED}Version required.${NC}"; exit 1; }

# --- ROLLBACK : restaure .env + relance l'ancienne version ---
rollback() {
    echo -e "\n${YELLOW}→ $T_ROLLBACK${NC}"
    cp .env.bak .env 2>/dev/null
    $COMPOSE pull >>"$LOG" 2>&1
    $COMPOSE up -d --remove-orphans >>"$LOG" 2>&1
    echo -e "${GREEN}[OK]${NC} $T_ROLLBACK_OK"
}

# ==============================================================================
# 4. BACKUP + MAJ DU TAG (avant le down → .env.bak = ancienne version)
# ==============================================================================
echo -e "\n${BLUE}--- CONFIGURATION ---${NC}"
cp .env .env.bak
tmp=$(mktemp)
if grep -qE "^TAG=" .env; then
    awk -v v="$NEW_TAG" '/^TAG=/{print "TAG=" v; next} {print}' .env > "$tmp" && cat "$tmp" > .env && rm -f "$tmp"
else
    cp .env "$tmp"; echo "TAG=$NEW_TAG" >> "$tmp"; cat "$tmp" > .env && rm -f "$tmp"   # append si absent
fi
echo -e "${GREEN}[OK]${NC} TAG=$NEW_TAG"

# ==============================================================================
# 4b. CONFIG RUNTIME (.env + runtime guard)
# ==============================================================================
if grep -qE "^RUN_NPM_BUILD=" .env; then
    tmp=$(mktemp)
    awk '/^RUN_NPM_BUILD=/{print "RUN_NPM_BUILD=false"; next} {print}' .env > "$tmp" && cat "$tmp" > .env && rm -f "$tmp"
else
    echo "RUN_NPM_BUILD=false" >> .env
fi

# .env lisible par php-fpm (groupe www-data = GID 33 dans le conteneur), sinon
# MissingAppKeyException cote web (le .env monte est souvent en 600 root).
chown root:33 .env 2>/dev/null || sudo chown root:33 .env 2>/dev/null || true
chmod 640 .env 2>/dev/null || sudo chmod 640 .env 2>/dev/null || true

if command -v systemctl &> /dev/null; then
    sudo tee /etc/systemd/system/ck-guard.service > /dev/null <<'GUARD_EOF'
[Unit]
Description=Cloutik runtime guard
After=docker.service
Requires=docker.service

[Service]
Restart=always
RestartSec=10
ExecStart=/usr/bin/bash -c 'sleep 15; docker restart ck-12 2>/dev/null || true; last=$(docker inspect -f "{{.State.StartedAt}}" ck-07 2>/dev/null || echo ""); while true; do sleep 5; cur=$(docker inspect -f "{{.State.StartedAt}}" ck-07 2>/dev/null || echo ""); if [ -n "$cur" ] && [ "$cur" != "$last" ]; then sleep 3; docker restart ck-12 2>/dev/null || true; last="$cur"; fi; done'

[Install]
WantedBy=multi-user.target
GUARD_EOF
    sudo systemctl daemon-reload &> /dev/null || true
    sudo systemctl enable ck-guard.service &> /dev/null || true
    sudo systemctl restart ck-guard.service &> /dev/null || true
fi

# ==============================================================================
# 4c. LOGIN REGISTRE (token robot Harbor 48h rafraichi via le master)
# ==============================================================================
REG_MASTER=$(read_env MASTER_API_URL); REG_ITOKEN=$(read_env master_token)
if [ -n "$REG_MASTER" ] && [ -n "$REG_ITOKEN" ] && command -v jq &> /dev/null; then
    REG_RESP=$(curl -s -X POST --location "${REG_MASTER}/api/registry/refresh-token" \
        --header "Authorization: Bearer ${REG_ITOKEN}" --header "Accept: application/json")
    REG_USER=$(echo "$REG_RESP" | jq -r '.data.registry_user // empty')
    REG_TOKEN=$(echo "$REG_RESP" | jq -r '.data.registry_token // empty')
    if [ -n "$REG_TOKEN" ]; then
        echo "$REG_TOKEN" | docker login registry.cloutik.app -u "$REG_USER" --password-stdin &> /dev/null \
            && echo -e "${GREEN}[OK]${NC} Registry login" \
            || echo -e "${YELLOW}[WARN]${NC} docker login KO (pull tentera avec le login existant)"
    else
        echo -e "${YELLOW}[WARN]${NC} Refresh registre KO (pull tentera avec le login existant)"
    fi
fi

# ==============================================================================
# 5. PULL D'ABORD (ancienne version reste UP pendant le téléchargement)
# ==============================================================================
echo -e "\n${BLUE}--- DOCKER UPDATE ---${NC}"
$COMPOSE pull >>"$LOG" 2>&1 & PID=$!; spinner $PID "→ $T_PULLING $NEW_TAG..."; wait $PID; EXIT_CODE=$?
if [ $EXIT_CODE -ne 0 ]; then
    echo -e "${RED}[ERROR] $T_PULL_FAIL${NC}"; tail -n 20 "$LOG"
    cp .env.bak .env          # ancienne version toujours en cours d'exécution → pas de coupure
    exit 1
fi
echo -e "${GREEN}[OK]${NC} Pull"

# ==============================================================================
# 6. DOWN puis UP (nouvelle version)
# ==============================================================================
$COMPOSE down --remove-orphans >>"$LOG" 2>&1 & PID=$!; spinner $PID "→ $T_STOPPING"; wait $PID
echo -e "${GREEN}[OK]${NC} Stop"
$COMPOSE up -d --remove-orphans >>"$LOG" 2>&1 & PID=$!; spinner $PID "→ Starting containers..."; wait $PID; EXIT_CODE=$?
if [ $EXIT_CODE -ne 0 ]; then
    echo -e "${RED}[ERROR] Start failed.${NC}"; tail -n 20 "$LOG"
    rollback; exit 1
fi
echo -e "${GREEN}[OK]${NC} Start"

# ==============================================================================
# 7. HEALTH CHECK (300s par défaut, configurable via HEALTH_RETRIES)
# ==============================================================================
echo -e "\n${BLUE}$T_HEALTH${NC}"; echo -e "${YELLOW}$T_FIRSTRUN${NC}"
MAX_RETRIES=${HEALTH_RETRIES:-60}; COUNT=0; SUCCESS=false
while [ $COUNT -lt $MAX_RETRIES ]; do
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -k "$LOGIN_URL" || echo "000")
    if [ "$HTTP_CODE" == "200" ]; then
        SUCCESS=true; printf "\r\033[K"; echo -e "$T_WAIT_HTTP ${GREEN}[OK] ($((COUNT*5))s)${NC}"; break
    fi
    printf "\r\033[K  ${CYAN}%s${NC} ${YELLOW}%ds${NC} (HTTP %s)" "$T_WAIT_HTTP" "$((COUNT*5))" "$HTTP_CODE"
    sleep 5; ((COUNT++)) || true
done
if [ "$SUCCESS" = false ]; then
    echo -e "\n${RED}[TIMEOUT] $COMPOSE logs -f app${NC}"
    rollback; exit 1
fi

echo -e "\n${GREEN}==============================================${NC}"
echo -e "${GREEN}   $T_SUCCESS ($NEW_TAG)      ${NC}"
echo -e "${GREEN}==============================================${NC}"

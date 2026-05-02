#!/bin/bash

# ============================================
# auto_maintenance.sh - Automate de maintenance
# Module: Théorie des systèmes d'exploitation
# ============================================

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_DIR="/var/log/auto_maintenance"
LOG_FILE="$LOG_DIR/history.log"

# Codes d'erreur
ERR_NONE=0
ERR_OPTION=100
ERR_PARAM_MISSING=101
ERR_PERMISSION=102
ERR_COMPILE=103

# ============================================
# Journalisation
# ============================================
log_message() {
    local type="$1"
    local message="$2"
    local timestamp=$(date +"%Y-%m-%d-%H-%M-%S")
    local username=$(whoami)
    
    # Création du répertoire si nécessaire
    sudo mkdir -p "$LOG_DIR" 2>/dev/null
    
    echo "$timestamp : $username : $type : $message" | sudo tee -a "$LOG_FILE"
    
    if [ "$type" = "ERROR" ]; then
        echo "❌ ERREUR: $message" >&2
    else
        echo "✅ $message"
    fi
}

# ============================================
# Aide (-h)
# ============================================
show_help() {
    cat << EOF
╔══════════════════════════════════════════════════════════╗
║              auto_maintenance.sh v1.0                    ║
║         Automate de maintenance pour serveur Linux       ║
╚══════════════════════════════════════════════════════════╝

USAGE: ./auto_maintenance.sh [OPTION] [PARAMETRE]

OPTIONS:
    -h              Afficher cette aide
    -f              FORK: Vérification mises à jour + scan fichiers >100Mo
    -s              SUBSHELL: Calcul espace disque par utilisateur
    -t "ports"      THREADS: Scan ports réseau (ex: "22,80,443")
    -l REPERTOIRE   LOG: Répertoire personnalisé pour les logs
    -r DOSSIER      RESTORE: Réinitialiser permissions (nécessite root)

CODES D'ERREUR:
    100 : Option invalide
    101 : Paramètre manquant
    102 : Permission refusée (root requis)
    103 : Erreur de compilation

EXEMPLES:
    ./auto_maintenance.sh -f
    ./auto_maintenance.sh -s
    ./auto_maintenance.sh -t "22,80,443,3306"
    ./auto_maintenance.sh -l /tmp/mon_log
    sudo ./auto_maintenance.sh -r /var/www

LOG:
    Fichier: /var/log/auto_maintenance/history.log
    Format: yyyy-mm-dd-hh-mm-ss : user : TYPE : message
EOF
}

# ============================================
# Option -f : Fork (processus parallèles)
# ============================================
option_fork() {
    log_message "INFOS" "=== Option FORK ==="
    
    # Processus fils 1 : mise à jour système
    (
        echo "  🔄 [PID:$$] Vérification des mises à jour..."
        if command -v apt &>/dev/null; then
            apt update 2>/dev/null
            apt list --upgradable 2>/dev/null | head -3
        elif command -v yum &>/dev/null; then
            yum check-update 2>/dev/null | head -3
        else
            echo "  ⚠️ Gestionnaire non supporté"
        fi
        echo "  ✅ Mises à jour terminées"
    ) &
    
    # Processus fils 2 : recherche fichiers volumineux
    (
        echo "  🔍 [PID:$$] Recherche fichiers > 100Mo..."
        find /home /var -type f -size +100M 2>/dev/null | head -5
        echo "  ✅ Scan terminé"
    ) &
    
    wait
    log_message "INFOS" "Option FORK terminée"
}

# ============================================
# Option -s : Subshell
# ============================================
option_subshell() {
    log_message "INFOS" "=== Option SUBSHELL ==="
    
    (
        echo "  📊 Calcul de l'espace disque par utilisateur"
        echo "  ─────────────────────────────────────────"
        
        for user_home in /home/*; do
            if [ -d "$user_home" ]; then
                username=$(basename "$user_home")
                size=$(du -sh "$user_home" 2>/dev/null | cut -f1)
                echo "    $username : $size"
            fi
        done
        
        echo "  ─────────────────────────────────────────"
        echo "  Subshell PID: $$"
    )
    
    log_message "INFOS" "Option SUBSHELL terminée"
}

# ============================================
# Option -t : Threads (appel au programme C)
# ============================================
option_threads() {
    local ports="$1"
    
    if [ -z "$ports" ]; then
        log_message "ERROR" "Option -t nécessite une liste de ports"
        show_help
        return $ERR_PARAM_MISSING
    fi
    
    log_message "INFOS" "=== Option THREADS ==="
    log_message "INFOS" "Scan des ports: $ports"
    
    # Vérification du programme C
    local c_source="$SCRIPT_DIR/port_scanner.c"
    local c_binary="/tmp/port_scanner"
    
    if [ ! -f "$c_source" ]; then
        log_message "ERROR" "Fichier port_scanner.c non trouvé"
        return $ERR_COMPILE
    fi
    
    # Compilation
    echo "  🔨 Compilation de port_scanner.c..."
    gcc -o "$c_binary" "$c_source" -lpthread 2>/dev/null
    
    if [ $? -ne 0 ]; then
        log_message "ERROR" "Échec de compilation"
        return $ERR_COMPILE
    fi
    
    echo "  ✅ Compilation réussie"
    echo ""
    
    # Exécution du scan multi-thread
    "$c_binary" "$ports"
    
    # Nettoyage
    rm -f "$c_binary"
    
    log_message "INFOS" "Option THREADS terminée"
}

# ============================================
# Option -l : Log personnalisé
# ============================================
option_log() {
    local custom_dir="$1"
    
    if [ -z "$custom_dir" ]; then
        log_message "ERROR" "Option -l nécessite un répertoire"
        show_help
        return $ERR_PARAM_MISSING
    fi
    
    # Sauvegarde ancien log
    local old_log="$LOG_FILE"
    
    # Nouveau répertoire
    LOG_DIR="$custom_dir"
    LOG_FILE="$LOG_DIR/history.log"
    
    sudo mkdir -p "$LOG_DIR" 2>/dev/null
    
    if [ $? -eq 0 ]; then
        log_message "INFOS" "Logs redirigés vers $LOG_DIR"
        echo "  📝 Ancien log: $old_log"
    else
        log_message "ERROR" "Impossible de créer $LOG_DIR"
        return $ERR_PERMISSION
    fi
}

# ============================================
# Option -r : Restore (nécessite root)
# ============================================
option_restore() {
    local target_dir="${1:-/var/www}"
    
    # Vérification des privilèges root
    if [ "$EUID" -ne 0 ]; then
        log_message "ERROR" "Option -r nécessite les privilèges root"
        echo "  💡 Utilisez: sudo ./auto_maintenance.sh -r $target_dir"
        show_help
        return $ERR_PERMISSION
    fi
    
    log_message "INFOS" "=== Option RESTORE ==="
    
    if [ ! -d "$target_dir" ]; then
        log_message "ERROR" "Le répertoire $target_dir n'existe pas"
        return $ERR_PARAM_MISSING
    fi
    
    echo "  🔧 Réinitialisation des permissions de $target_dir"
    
    # Restauration des permissions
    chown -R root:www-data "$target_dir" 2>/dev/null
    find "$target_dir" -type d -exec chmod 755 {} \; 2>/dev/null
    find "$target_dir" -type f -exec chmod 644 {} \; 2>/dev/null
    
    echo "  ✅ Permissions restaurées avec succès"
    log_message "INFOS" "Permissions restaurées pour $target_dir"
}

# ============================================
# Initialisation
# ============================================
init_log_system() {
    sudo mkdir -p "$LOG_DIR" 2>/dev/null
    sudo touch "$LOG_FILE" 2>/dev/null
    sudo chmod 644 "$LOG_FILE" 2>/dev/null
}

# ============================================
# Main
# ============================================

# Initialisation des logs
init_log_system

# Vérification des arguments
if [ $# -eq 0 ]; then
    log_message "ERROR" "Aucune option fournie"
    show_help
    exit $ERR_PARAM_MISSING
fi

# Traitement des options
case "$1" in
    -h)
        show_help
        exit $ERR_NONE
        ;;
    -f)
        option_fork
        ;;
    -s)
        option_subshell
        ;;
    -t)
        option_threads "$2"
        ;;
    -l)
        option_log "$2"
        ;;
    -r)
        option_restore "$2"
        ;;
    *)
        log_message "ERROR" "Option invalide: $1"
        show_help
        exit $ERR_OPTION
        ;;
esac

exit $ERR_NONE

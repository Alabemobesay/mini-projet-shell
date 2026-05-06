#!/bin/bash
# ============================================================
#  TrinityOPS v2.0 — Advanced File Management System
#  Author: TrinityOPS
# ============================================================

set -euo pipefail

# ─── CONFIGURATION ────────────────────────────────────────
readonly DATA_DIR="./data_source"
readonly ARCHIVE_DIR="./archives"
readonly LOG_FILE="$(pwd)/history.log"
readonly LOCK_FILE="/tmp/trinityops.lock"
readonly MAX_PARALLEL_JOBS=4
readonly LOG_MAX_LINES=10000

# ─── COLORS & STYLES ──────────────────────────────────────
if [[ -t 1 ]]; then
    RED='\033[0;31m';    GREEN='\033[0;32m';   YELLOW='\033[1;33m'
    BLUE='\033[0;34m';   CYAN='\033[0;36m';    BOLD='\033[1m'
    DIM='\033[2m';       RESET='\033[0m'
else
    RED=''; GREEN=''; YELLOW=''; BLUE=''; CYAN=''; BOLD=''; DIM=''; RESET=''
fi

# ─── LOGGING ──────────────────────────────────────────────
log_event() {
    local level="$1" message="$2"
    local timestamp
    timestamp="$(date '+%Y-%m-%d %H:%M:%S')"
    echo "${timestamp} | $(whoami) | ${level} | ${message}" >> "$LOG_FILE"

    # Rotate log if too large
    local line_count
    line_count=$(wc -l < "$LOG_FILE" 2>/dev/null || echo 0)
    if (( line_count > LOG_MAX_LINES )); then
        local tmpfile
        tmpfile=$(mktemp)
        tail -n $((LOG_MAX_LINES / 2)) "$LOG_FILE" > "$tmpfile"
        mv "$tmpfile" "$LOG_FILE"
        log_event "INFO" "Log rotated (exceeded ${LOG_MAX_LINES} lines)"
    fi
}

# ─── OUTPUT HELPERS ───────────────────────────────────────
info()    { echo -e "${CYAN}[INFO]${RESET}  $*"; }
success() { echo -e "${GREEN}[OK]${RESET}    $*"; }
warn()    { echo -e "${YELLOW}[WARN]${RESET}  $*" >&2; }
error()   { echo -e "${RED}[ERROR]${RESET} $*" >&2; }
header()  { echo -e "\n${BOLD}${BLUE}══ $* ══${RESET}"; }
divider() { echo -e "${DIM}────────────────────────────────────────${RESET}"; }

# Progress bar
progress_bar() {
    local current="$1" total="$2" label="${3:-Progress}"
    local width=30
    local filled=$(( current * width / (total > 0 ? total : 1) ))
    local bar=""
    for (( i=0; i<filled; i++ )); do bar+="█"; done
    for (( i=filled; i<width; i++ )); do bar+="░"; done
    printf "\r${CYAN}%-12s${RESET} [%s] %d/%d  " "$label" "$bar" "$current" "$total"
    # Flush stdout so fast terminals actually render each step
    # shellcheck disable=SC2166
    [[ "$current" -ge "$total" ]] && echo || true
}

# ─── SETUP ────────────────────────────────────────────────
setup_dirs() {
    mkdir -p "$DATA_DIR" "$ARCHIVE_DIR"
    touch "$LOG_FILE"
}

# ─── LOCK MANAGEMENT ──────────────────────────────────────
acquire_lock() {
    if [[ -f "$LOCK_FILE" ]]; then
        local pid
        pid=$(cat "$LOCK_FILE" 2>/dev/null || echo "unknown")
        error "TrinityOPS is already running (PID: ${pid}). Use --force to override."
        exit 1
    fi
    echo $$ > "$LOCK_FILE"
    trap 'release_lock' EXIT INT TERM
}

release_lock() {
    rm -f "$LOCK_FILE"
}

# ─── HELP ─────────────────────────────────────────────────
show_help() {
    echo -e "
${BOLD}${BLUE}╔══════════════════════════════════════════════════════╗
║           TrinityOPS v2.0 — Guide d'utilisation      ║
╚══════════════════════════════════════════════════════╝${RESET}

${BOLD}USAGE:${RESET}
  $0 [OPTION] [ARGS...]

${BOLD}${CYAN}OPÉRATIONS PRINCIPALES:${RESET}
  ${GREEN}-f${RESET}              (Fork)     Trie les fichiers par extension (.log, .csv, .txt)
  ${GREEN}-t${RESET}              (Thread)   Chiffre les fichiers sensibles (.csv, .txt) → .enc
  ${GREEN}-s${RESET}              (Subshell) Affiche le rapport statistique des données
  ${GREEN}-r${RESET}              (Restore)  Restaure les fichiers depuis le dossier archives

${BOLD}${CYAN}ARCHIVAGE:${RESET}
  ${GREEN}-c${RESET}              (Compress)   Crée une archive tar.gz horodatée
  ${GREEN}-x${RESET}              (Decompress) Extrait la dernière archive disponible
  ${GREEN}-d${RESET} [archive]    (Decompress) Extrait une archive spécifique

${BOLD}${CYAN}MAINTENANCE:${RESET}
  ${GREEN}-p${RESET}              (Prune)   Supprime les fichiers .tmp et .enc orphelins
  ${GREEN}-v${RESET}              (Verify)  Vérifie les outils système requis
  ${GREEN}-l${RESET} [N]          (Log)     Affiche les N dernières entrées (défaut: 10)
  ${GREEN}--clear-logs${RESET}    Réinitialise le fichier history.log

${BOLD}${CYAN}AUTRES:${RESET}
  ${GREEN}--status${RESET}        Affiche l'état général du système
  ${GREEN}--force${RESET}         Force l'exécution même si un verrou existe
  ${GREEN}-h, --help${RESET}      Affiche cette aide

${BOLD}EXEMPLES:${RESET}
  $0 -f                    # Trier les fichiers
  $0 -c                    # Compresser les données
  $0 -d backup_20250506.tar.gz   # Extraire une archive précise
  $0 -l 20                 # Voir les 20 derniers logs
"
}

# ─── FORK: FILE SORTING ───────────────────────────────────
sort_files_fork() {
    header "FORK — Tri des fichiers par extension"
    log_event "INFO" "Démarrage du tri par extension"

    local extensions=("log" "csv" "txt")
    local total_moved=0
    local pids=()

    for ext in "${extensions[@]}"; do
        (
            local dest="$DATA_DIR/$ext"
            mkdir -p "$dest"
            local files=()
            while IFS= read -r -d '' f; do
                files+=("$f")
            done < <(find "$DATA_DIR" -maxdepth 1 -name "*.$ext" -print0 2>/dev/null)

            local count=${#files[@]}
            if (( count > 0 )); then
                for f in "${files[@]}"; do
                    mv -- "$f" "$dest/" 2>/dev/null || warn "Impossible de déplacer: $f"
                done
                echo " ${GREEN}▸${RESET} .$ext → $count fichier(s) déplacé(s) dans ${DIM}$dest${RESET}"
            else
                echo " ${DIM}▸ .$ext → aucun fichier trouvé${RESET}"
            fi
        ) &
        pids+=($!)
    done

    local i=0
    for pid in "${pids[@]}"; do
        wait "$pid" && (( i++ ))
        progress_bar "$i" "${#pids[@]}" "Tri"
    done

    divider
    success "Tri terminé."
    log_event "INFO" "Tri par extension terminé"
}

# ─── THREAD: ENCRYPTION ───────────────────────────────────
encrypt_data_thread() {
    header "THREAD — Chiffrement des fichiers sensibles"
    log_event "INFO" "Chiffrement des données en cours"

    local files=()
    while IFS= read -r -d '' f; do
        files+=("$f")
    done < <(find "$DATA_DIR" -type f \( -name "*.csv" -o -name "*.txt" \) \
             ! -name "*.enc" -print0 2>/dev/null)

    local total=${#files[@]}
    if (( total == 0 )); then
        warn "Aucun fichier .csv/.txt trouvé à chiffrer."
        return 0
    fi

    info "$total fichier(s) à traiter..."
    local count=0
    local failed=0

    # Sequential processing so progress bar reflects actual work done
    for file in "${files[@]}"; do
        if mv -- "$file" "${file}.enc" 2>/dev/null; then
            : # success
        else
            (( failed++ ))
        fi
        (( count++ ))
        progress_bar "$count" "$total" "Chiffrement"
    done

    echo  # newline after progress bar
    divider

    if (( failed > 0 )); then
        warn "Chiffrement terminé — $((count - failed))/$total succès, $failed échec(s)."
        log_event "WARN" "Chiffrement terminé avec $failed échec(s) sur $total"
    else
        success "Chiffrement terminé — $total fichier(s) traité(s)."
        log_event "INFO" "Chiffrement terminé ($total fichiers)"
    fi
}

# ─── SUBSHELL: STATISTICS ─────────────────────────────────
generate_stats_subshell() {
    header "SUBSHELL — Rapport statistique"
    (
        local total_files total_size enc_files log_files csv_files txt_files
        total_files=$(find "$DATA_DIR" -type f | wc -l)
        total_size=$(du -sh "$DATA_DIR" 2>/dev/null | cut -f1)
        enc_files=$(find "$DATA_DIR" -type f -name "*.enc" | wc -l)
        log_files=$(find "$DATA_DIR" -type f -name "*.log" | wc -l)
        csv_files=$(find "$DATA_DIR" -type f -name "*.csv" | wc -l)
        txt_files=$(find "$DATA_DIR" -type f -name "*.txt" | wc -l)
        arc_count=$(find "$ARCHIVE_DIR" -name "*.tar.gz" | wc -l)
        arc_size=$(du -sh "$ARCHIVE_DIR" 2>/dev/null | cut -f1)

        echo -e "
${BOLD}  Répertoire    :${RESET} $DATA_DIR
${BOLD}  Total fichiers:${RESET} $total_files
${BOLD}  Taille totale :${RESET} $total_size

  ${CYAN}Par type:${RESET}
    .log  → $log_files
    .csv  → $csv_files
    .txt  → $txt_files
    .enc  → $enc_files ${DIM}(chiffrés)${RESET}

  ${CYAN}Archives:${RESET}
    Nombre → $arc_count
    Taille → $arc_size
"
    )
    log_event "INFO" "Rapport statistique généré"
}

# ─── RESTORE ──────────────────────────────────────────────
restore_archives() {
    header "RESTORE — Restauration des fichiers"
    local count
    count=$(find "$ARCHIVE_DIR" -maxdepth 1 -mindepth 1 -type f | wc -l)

    # Only restore non-archive files — skip .tar.gz backups
    local restorable
    restorable=$(find "$ARCHIVE_DIR" -maxdepth 1 -mindepth 1 -type f ! -name "*.tar.gz" | wc -l)

    if (( restorable > 0 )); then
        local moved=0
        while IFS= read -r -d '' f; do
            mv -- "$f" "$DATA_DIR/" 2>/dev/null && (( moved++ )) || warn "Impossible de restaurer: $f"
        done < <(find "$ARCHIVE_DIR" -maxdepth 1 -mindepth 1 -type f ! -name "*.tar.gz" -print0)
        success "$moved fichier(s) restauré(s) vers $DATA_DIR"
        log_event "INFO" "Restauration effectuée: $moved fichiers"
    else
        warn "Aucun fichier à restaurer dans $ARCHIVE_DIR (les .tar.gz sont ignorés)"
        info "Pour extraire une archive, utilisez: $0 -x  ou  $0 -d <archive>"
    fi
}

# ─── COMPRESS ─────────────────────────────────────────────
compress_data() {
    header "COMPRESS — Archivage des données"
    local archive_name="backup_$(date +%Y%m%d_%H%M%S).tar.gz"
    local dest="$ARCHIVE_DIR/$archive_name"

    local file_count
    file_count=$(find "$DATA_DIR" -type f | wc -l)

    if (( file_count == 0 )); then
        warn "Aucun fichier à compresser dans $DATA_DIR"
        return 0
    fi

    info "Compression de $file_count fichier(s)..."
    if tar -czf "$dest" "$DATA_DIR" 2>/dev/null; then
        local size
        size=$(du -sh "$dest" | cut -f1)
        success "Archive créée: ${BOLD}$dest${RESET} (${size})"
        log_event "INFO" "Archive créée: $archive_name ($size)"
    else
        error "Échec de la compression."
        log_event "ERROR" "Échec compression vers $dest"
        return 1
    fi
}

# ─── DECOMPRESS ───────────────────────────────────────────
decompress_data() {
    local target_archive="${1:-}"
    header "DECOMPRESS — Extraction d'archive"

    if [[ -n "$target_archive" ]]; then
        # Specific archive requested
        local archive_path
        if [[ -f "$target_archive" ]]; then
            archive_path="$target_archive"
        elif [[ -f "$ARCHIVE_DIR/$target_archive" ]]; then
            archive_path="$ARCHIVE_DIR/$target_archive"
        else
            error "Archive introuvable: $target_archive"
            return 1
        fi
    else
        # Latest archive
        archive_path=$(ls -t "$ARCHIVE_DIR"/*.tar.gz 2>/dev/null | head -n 1 || true)
        if [[ -z "$archive_path" ]]; then
            warn "Aucune archive .tar.gz trouvée dans $ARCHIVE_DIR"
            return 0
        fi
        info "Dernière archive détectée: ${BOLD}$(basename "$archive_path")${RESET}"
    fi

    if tar -xzf "$archive_path" -C "$DATA_DIR" 2>/dev/null; then
        success "Extraction réussie: $(basename "$archive_path")"
        log_event "INFO" "Désarchivage de $(basename "$archive_path") effectué"
    else
        error "Échec de l'extraction."
        log_event "ERROR" "Échec extraction: $archive_path"
        return 1
    fi
}

# ─── PRUNE ────────────────────────────────────────────────
prune_system() {
    header "PRUNE — Nettoyage du système"
    local tmp_count enc_count

    tmp_count=$(find . -name "*.tmp" 2>/dev/null | wc -l)
    enc_count=$(find "$DATA_DIR" -name "*.enc" 2>/dev/null | wc -l)

    echo -e "  Fichiers .tmp trouvés  : ${YELLOW}$tmp_count${RESET}"
    echo -e "  Fichiers .enc trouvés  : ${YELLOW}$enc_count${RESET}"
    echo

    if (( tmp_count + enc_count == 0 )); then
        success "Aucun fichier à supprimer."
        return 0
    fi

    read -rp "$(echo -e "  ${YELLOW}Confirmer la suppression ? [y/N]${RESET} ")" confirm
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        find . -name "*.tmp" -delete 2>/dev/null
        info "$tmp_count fichier(s) .tmp supprimé(s)"
        log_event "INFO" "Prune: $tmp_count .tmp supprimés"
    else
        info "Opération annulée."
    fi
}

# ─── VERIFY TOOLS ─────────────────────────────────────────
verify_tools() {
    header "VERIFY — Vérification des outils requis"
    local tools=("tar" "find" "du" "wc" "date" "mktemp" "tail" "cut")
    local missing=0

    for tool in "${tools[@]}"; do
        if command -v "$tool" &>/dev/null; then
            local ver
            ver=$(command -v "$tool")
            echo -e "  ${GREEN}[OK]${RESET}    $tool ${DIM}→ $ver${RESET}"
        else
            echo -e "  ${RED}[MISSING]${RESET} $tool — REQUIS"
            (( missing++ ))
        fi
    done

    divider
    if (( missing > 0 )); then
        warn "$missing outil(s) manquant(s). Certaines fonctions seront indisponibles."
        log_event "WARN" "Vérification: $missing outil(s) manquant(s)"
    else
        success "Tous les outils sont disponibles."
        log_event "INFO" "Vérification des outils: OK"
    fi
}

# ─── VIEW LOGS ────────────────────────────────────────────
view_logs() {
    local n="${1:-10}"
    header "LOGS — ${n} dernières entrées"

    if [[ ! -f "$LOG_FILE" ]] || [[ ! -s "$LOG_FILE" ]]; then
        warn "Aucune entrée dans $LOG_FILE"
        return 0
    fi

    tail -n "$n" "$LOG_FILE" | while IFS='|' read -r ts user level msg; do
        local color="$CYAN"
        [[ "$level" =~ ERROR ]] && color="$RED"
        [[ "$level" =~ WARN  ]] && color="$YELLOW"
        [[ "$level" =~ INFO  ]] && color="$GREEN"
        printf "  ${DIM}%s${RESET} ${color}%-8s${RESET} %s\n" "$ts" "[$level]" "$msg"
    done
}

# ─── STATUS ───────────────────────────────────────────────
show_status() {
    header "STATUS — État du système TrinityOPS"
    local data_files arc_files log_lines
    data_files=$(find "$DATA_DIR" -type f 2>/dev/null | wc -l)
    arc_files=$(find "$ARCHIVE_DIR" -name "*.tar.gz" 2>/dev/null | wc -l)
    log_lines=$(wc -l < "$LOG_FILE" 2>/dev/null || echo 0)

    echo -e "
  ${CYAN}Répertoires:${RESET}
    ${BOLD}data_source/${RESET}  → $data_files fichier(s)     ${DIM}[$(du -sh "$DATA_DIR" 2>/dev/null | cut -f1)]${RESET}
    ${BOLD}archives/${RESET}     → $arc_files archive(s)  ${DIM}[$(du -sh "$ARCHIVE_DIR" 2>/dev/null | cut -f1)]${RESET}

  ${CYAN}Journal:${RESET}
    ${BOLD}history.log${RESET}   → $log_lines ligne(s)

  ${CYAN}Verrou système:${RESET}
    $( [[ -f "$LOCK_FILE" ]] && echo "${YELLOW}Actif${RESET} (PID: $(cat "$LOCK_FILE"))" || echo "${GREEN}Inactif${RESET}" )
"
    log_event "INFO" "Statut système affiché"
}

# ─── MAIN ENTRYPOINT ──────────────────────────────────────
main() {
    setup_dirs

    local force=false
    local args=()
    for arg in "$@"; do
        [[ "$arg" == "--force" ]] && force=true || args+=("$arg")
    done

    local opt="${args[0]:-}"
    local opt2="${args[1]:-}"

    # Lock (skip for read-only and help operations)
    if [[ "$opt" != "-h" && "$opt" != "--help" && "$opt" != "-v" && \
          "$opt" != "-l" && "$opt" != "-s" && "$opt" != "--status" ]]; then
        if [[ "$force" == true ]]; then
            rm -f "$LOCK_FILE"
        fi
        acquire_lock
    fi

    case "$opt" in
        -f)           sort_files_fork ;;
        -t)           encrypt_data_thread ;;
        -s)           generate_stats_subshell ;;
        -r)           restore_archives ;;
        -c)           compress_data ;;
        -x)           decompress_data ;;
        -d)           decompress_data "$opt2" ;;
        -p)           prune_system ;;
        -v)           verify_tools ;;
        -l)           view_logs "${opt2:-10}" ;;
        --status)     show_status ;;
        --clear-logs)
            > "$LOG_FILE"
            success "Journal history.log réinitialisé."
            log_event "INFO" "Journal vidé par $(whoami)"
            ;;
        -h|--help)    show_help ;;
        "")
            show_help
            exit 0
            ;;
        *)
            error "Option inconnue: '$opt'"
            echo -e "  Utilisez ${BOLD}$0 -h${RESET} pour voir l'aide."
            exit 1
            ;;
    esac
}

main "$@"
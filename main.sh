#!/usr/bin/env bash
# ==============================================================================
# SCRIPT PRINCIPAL ORCHESTRATEUR - MINI PROJET ENSET MOHAMMEDIA 2026
# ==============================================================================
# Nom du programme  : main.sh
# Module            : Théorie des systèmes d'exploitation & SE Windows/Unix/Linux
# Description       : Script global qui orchestre l'exécution des scripts métiers
#                     des membres du groupe selon le mode choisi (normal/fork/
#                     thread/subshell).
# Syntaxe           : ./main.sh [options] TARGET_DIR
# Auteur            : [Votre Nom] - [Votre Équipe]
# Version           : 1.0
# Date              : 2026
# ==============================================================================

# ==============================================================================
# SECTION 1 : VARIABLES GLOBALES
# ==============================================================================

# Nom du programme (utilisé dans les messages et les logs)
readonly PROG_NAME="$(basename "$0")"

# Version du script
readonly VERSION="1.0"

# Répertoire de base du projet (répertoire où se trouve main.sh)
readonly BASE_DIR="$(cd "$(dirname "$0")" && pwd)"

# Répertoire des scripts des collègues
readonly SCRIPTS_DIR="${BASE_DIR}/scripts"

# Répertoire de logs par défaut (peut être surchargé par -l)
DEFAULT_LOG_DIR="/var/log/${PROG_NAME%.*}"

# Répertoire de logs actif (modifiable via -l)
LOG_DIR="${DEFAULT_LOG_DIR}"

# Fichier de log principal
LOG_FILE=""   # Sera défini après parsing des options

# Paramètre obligatoire : répertoire cible à traiter
TARGET_DIR=""

# Mode d'exécution : normal (défaut), fork, thread, subshell
EXEC_MODE="normal"

# Drapeau pour l'option restore
OPT_RESTORE=false

# Codes de retour / codes d'erreur explicites
readonly ERR_INVALID_OPTION=100
readonly ERR_MISSING_PARAM=101
readonly ERR_NOT_ADMIN=102
readonly ERR_MISSING_SCRIPT=103
readonly ERR_INVALID_DIR=104
readonly ERR_MODULE_FAILED=105
readonly ERR_LOG_INIT=106

# Liste ordonnée des scripts collègues (chemins relatifs depuis BASE_DIR)
# -----------------------------------------------------------------------
# EMPLACEMENT RÉSERVÉ : ces scripts seront développés par chaque collègue.
# Le script principal vérifie leur existence et les appelle au bon moment.
# -----------------------------------------------------------------------
COLLEAGUE_SCRIPTS=(
    "${SCRIPTS_DIR}/script_collegue_1.sh"   # Module 1 : [description à compléter]
    "${SCRIPTS_DIR}/script_collegue_2.sh"   # Module 2 : [description à compléter]
    "${SCRIPTS_DIR}/script_collegue_3.sh"   # Module 3 : [description à compléter]
    "${SCRIPTS_DIR}/script_collegue_4.sh"   # Module 4 : [description à compléter]
)

# ==============================================================================
# SECTION 2 : FONCTION D'AIDE (option -h)
# ==============================================================================

show_help() {
    # Affichage de la documentation complète du programme (style man Linux)
    cat <<EOF

NOM
    ${PROG_NAME} - Orchestrateur de traitements automatisés (Mini Projet ENSET 2026)

SYNOPSIS
    ${PROG_NAME} [OPTIONS] TARGET_DIR

DESCRIPTION
    Script Bash principal qui coordonne l'exécution de quatre modules spécialisés
    développés par les membres du groupe. Il supporte plusieurs modes d'exécution
    (normal, fork, thread, subshell) et centralise la journalisation.

    TARGET_DIR   Répertoire cible obligatoire sur lequel les modules vont opérer.
                 Ce répertoire doit exister et être accessible en lecture.

OPTIONS
    -h           Affiche cette aide détaillée et quitte.

    -f           Mode FORK : chaque module est exécuté dans un sous-processus
                 indépendant (& + wait). Permet la parallélisation des traitements.

    -t           Mode THREAD : simulation de parallélisme en Bash via sous-processus
                 en arrière-plan. Équivalent fonctionnel au mode fork en Bash pur.

    -s           Mode SUBSHELL : chaque module est exécuté dans un sous-shell isolé
                 (entre parenthèses). L'environnement du shell parent est préservé.

    -l LOG_DIR   Spécifie un répertoire personnalisé pour le fichier de log
                 history.log. Par défaut : ${DEFAULT_LOG_DIR}

    -r           RESTORE : réinitialise l'état par défaut du projet.
                 NÉCESSITE LES PRIVILÈGES ROOT/ADMINISTRATEUR.

FORMAT DES LOGS
    Chaque entrée dans history.log suit le format :
        yyyy-mm-dd-hh-mm-ss : username : INFOS : message
        yyyy-mm-dd-hh-mm-ss : username : ERROR : message

CODES D'ERREUR
    ${ERR_INVALID_OPTION}   Option invalide ou inconnue
    ${ERR_MISSING_PARAM}   Paramètre obligatoire manquant (TARGET_DIR)
    ${ERR_NOT_ADMIN}   Privilèges insuffisants (root requis)
    ${ERR_MISSING_SCRIPT}   Script externe (module collègue) introuvable
    ${ERR_INVALID_DIR}   Répertoire invalide ou inaccessible
    ${ERR_MODULE_FAILED}   Échec d'exécution d'un module
    ${ERR_LOG_INIT}   Impossible d'initialiser le répertoire de logs

EXEMPLES
    # Exécution normale sur /data/projet
    ./${PROG_NAME} /data/projet

    # Exécution en mode fork avec log personnalisé
    ./${PROG_NAME} -f -l /tmp/logs /data/projet

    # Exécution en mode subshell
    ./${PROG_NAME} -s /data/projet

    # Exécution en mode thread
    ./${PROG_NAME} -t /data/projet

    # Restauration (root uniquement)
    sudo ./${PROG_NAME} -r /data/projet

    # Afficher l'aide
    ./${PROG_NAME} -h

ARCHITECTURE DU PROJET
    project/
    ├── main.sh                     ← Ce script (orchestrateur)
    ├── scripts/
    │   ├── script_collegue_1.sh    ← Module 1 (développé par collègue 1)
    │   ├── script_collegue_2.sh    ← Module 2 (développé par collègue 2)
    │   ├── script_collegue_3.sh    ← Module 3 (développé par collègue 3)
    │   └── script_collegue_4.sh    ← Module 4 (développé par collègue 4)
    └── logs/
        └── history.log             ← Journal centralisé

VERSION
    ${PROG_NAME} version ${VERSION} - ENSET Mohammedia 2026

EOF
}

# ==============================================================================
# SECTION 3 : FONCTIONS DE JOURNALISATION
# ==============================================================================

# Fonction interne : génère un horodatage au format yyyy-mm-dd-hh-mm-ss
_timestamp() {
    date "+%Y-%m-%d-%H-%M-%S"
}

# Fonction interne : retourne le nom de l'utilisateur courant
_username() {
    echo "${USER:-$(whoami)}"
}

# log_info : journalise un message de type INFOS
# Usage : log_info "message"
log_info() {
    local message="$1"
    # Construction de l'entrée de log au format requis
    local entry="$(_timestamp) : $(_username) : INFOS : ${message}"

    # Affichage dans le terminal (stdout)
    echo "${entry}"

    # Écriture dans le fichier de log (si initialisé)
    if [[ -n "${LOG_FILE}" ]]; then
        echo "${entry}" >> "${LOG_FILE}"
    fi
}

# log_error : journalise un message de type ERROR
# Usage : log_error "message"
log_error() {
    local message="$1"
    # Construction de l'entrée de log au format requis
    local entry="$(_timestamp) : $(_username) : ERROR : ${message}"

    # Affichage dans le terminal (stderr)
    echo "${entry}" >&2

    # Écriture dans le fichier de log (si initialisé)
    if [[ -n "${LOG_FILE}" ]]; then
        echo "${entry}" >> "${LOG_FILE}"
    fi
}

# ==============================================================================
# SECTION 4 : FONCTION DE CONTRÔLE D'ACCÈS ADMINISTRATEUR
# ==============================================================================

# check_admin : vérifie que le script est exécuté par root (UID=0)
# En cas d'échec, affiche une erreur et quitte avec le code ERR_NOT_ADMIN
check_admin() {
    # $EUID est l'UID effectif de l'utilisateur courant (0 = root)
    if [[ "${EUID}" -ne 0 ]]; then
        log_error "L'option -r (restore) nécessite les privilèges administrateur (root)."
        log_error "Veuillez relancer avec : sudo ${PROG_NAME} -r ${TARGET_DIR}"
        show_help
        exit "${ERR_NOT_ADMIN}"
    fi
    log_info "Vérification des privilèges administrateur : OK (UID=${EUID})"
}

# ==============================================================================
# SECTION 5 : FONCTION DE VÉRIFICATION DES DÉPENDANCES (scripts collègues)
# ==============================================================================

# check_dependencies : vérifie que tous les scripts collègues sont présents
# et exécutables. Journalise le statut de chaque module.
check_dependencies() {
    log_info "Vérification des modules externes (scripts collègues)..."

    # Variable de suivi : devient true si au moins un script est manquant
    local all_ok=true

    # Boucle sur chaque script collègue déclaré dans le tableau COLLEAGUE_SCRIPTS
    for script in "${COLLEAGUE_SCRIPTS[@]}"; do
        if [[ -f "${script}" && -x "${script}" ]]; then
            # Le script existe et est exécutable
            log_info "  [OK] Module trouvé : ${script}"
        elif [[ -f "${script}" && ! -x "${script}" ]]; then
            # Le script existe mais n'est pas exécutable
            log_error "  [WARN] Module non exécutable : ${script} — Tentative de correction..."
            chmod +x "${script}" 2>/dev/null && log_info "  [OK] Permissions corrigées : ${script}" \
                || { log_error "  [ERR] Impossible de corriger : ${script}"; all_ok=false; }
        else
            # Le script est complètement absent
            log_error "  [MANQUANT] Module introuvable : ${script}"
            all_ok=false
        fi
    done

    # Si un ou plusieurs scripts sont absents, on quitte avec ERR_MISSING_SCRIPT
    if [[ "${all_ok}" == false ]]; then
        log_error "Un ou plusieurs modules sont manquants. Vérifiez l'arborescence du projet."
        show_help
        exit "${ERR_MISSING_SCRIPT}"
    fi

    log_info "Tous les modules sont présents et prêts."
}

# ==============================================================================
# SECTION 6 : FONCTION D'INITIALISATION DU RÉPERTOIRE DE LOGS
# ==============================================================================

# init_log : crée le répertoire de logs et initialise LOG_FILE
init_log() {
    # Création du répertoire de logs s'il n'existe pas encore
    if [[ ! -d "${LOG_DIR}" ]]; then
        mkdir -p "${LOG_DIR}" 2>/dev/null
        if [[ $? -ne 0 ]]; then
            # Impossible de créer le répertoire (permissions insuffisantes ?)
            echo "ERREUR : Impossible de créer le répertoire de logs : ${LOG_DIR}" >&2
            echo "Conseil : essayez avec sudo, ou spécifiez un autre dossier avec -l" >&2
            show_help
            exit "${ERR_LOG_INIT}"
        fi
    fi

    # Définition du chemin complet du fichier de log
    LOG_FILE="${LOG_DIR}/history.log"

    # Création du fichier s'il n'existe pas
    touch "${LOG_FILE}" 2>/dev/null || {
        echo "ERREUR : Impossible de créer le fichier de log : ${LOG_FILE}" >&2
        exit "${ERR_LOG_INIT}"
    }

    log_info "Journalisation initialisée → ${LOG_FILE}"
}

# ==============================================================================
# SECTION 7 : FONCTION RESTORE (option -r, admin uniquement)
# ==============================================================================

# restore_defaults : réinitialise l'état par défaut du projet
# ⚠️ EMPLACEMENT RÉSERVÉ : la logique exacte doit être adaptée au projet final.
# L'implémentation ci-dessous est générique et non destructive.
restore_defaults() {
    log_info "=== DÉBUT DE LA RESTAURATION ==="
    log_info "Restauration de l'état par défaut du projet sur : ${TARGET_DIR}"

    # --- EMPLACEMENT RÉSERVÉ : logique de restauration à personnaliser ---
    # Exemple générique : suppression des fichiers temporaires produits par les modules
    # Cette section doit être adaptée selon les fichiers générés par votre projet.

    # Exemple 1 : suppression des fichiers temporaires (.tmp) dans TARGET_DIR
    log_info "Nettoyage des fichiers temporaires dans ${TARGET_DIR}..."
    find "${TARGET_DIR}" -maxdepth 2 -name "*.tmp" -type f -print -delete 2>/dev/null \
        && log_info "Fichiers temporaires supprimés." \
        || log_error "Aucun fichier temporaire trouvé ou erreur de suppression."

    # Exemple 2 : réinitialisation des permissions sur TARGET_DIR (non destructif)
    log_info "Réinitialisation des permissions sur ${TARGET_DIR}..."
    chmod 755 "${TARGET_DIR}" 2>/dev/null \
        && log_info "Permissions réinitialisées à 755." \
        || log_error "Impossible de modifier les permissions."

    # Exemple 3 : archivage des anciens logs avant réinitialisation
    if [[ -f "${LOG_FILE}" ]]; then
        local archive_name="${LOG_DIR}/history_backup_$(_timestamp).log.gz"
        log_info "Archivage de l'ancien log → ${archive_name}"
        gzip -c "${LOG_FILE}" > "${archive_name}" 2>/dev/null \
            && log_info "Archive créée : ${archive_name}" \
            || log_error "Échec de l'archivage du log."
    fi

    # ⚠️ NOTE : Ajoutez ici les étapes spécifiques à votre projet (ex: reset BDD,
    # réinitialisation de fichiers de config, etc.) selon les besoins définis
    # dans votre compte rendu.

    log_info "=== RESTAURATION TERMINÉE ==="
}

# ==============================================================================
# SECTION 8 : FONCTIONS D'EXÉCUTION DES MODULES
# ==============================================================================

# --- Sous-fonction : appelle un script collègue et vérifie son code de retour ---
# Usage : _run_module <script_path> <target_dir>
_run_module() {
    local script="$1"
    local target="$2"
    local module_name
    module_name="$(basename "${script}")"

    log_info "  → Lancement du module : ${module_name} avec TARGET_DIR=${target}"

    # Appel du script collègue avec TARGET_DIR en argument
    # EMPLACEMENT RÉSERVÉ : seul l'appel est défini ici, pas le contenu métier.
    bash "${script}" "${target}"
    local exit_code=$?

    # Vérification du code de retour du module
    if [[ ${exit_code} -ne 0 ]]; then
        log_error "  ✗ Échec du module ${module_name} (code de retour : ${exit_code})"
        return "${ERR_MODULE_FAILED}"
    else
        log_info "  ✓ Module ${module_name} terminé avec succès."
        return 0
    fi
}

# -----------------------------------------------------------------------
# run_normal : exécution séquentielle classique des modules
# Les scripts sont exécutés l'un après l'autre dans l'ordre du tableau.
# -----------------------------------------------------------------------
run_normal() {
    log_info "=== MODE NORMAL : exécution séquentielle ==="
    local global_status=0

    for script in "${COLLEAGUE_SCRIPTS[@]}"; do
        _run_module "${script}" "${TARGET_DIR}"
        if [[ $? -ne 0 ]]; then
            global_status="${ERR_MODULE_FAILED}"
        fi
    done

    if [[ ${global_status} -ne 0 ]]; then
        log_error "Un ou plusieurs modules ont échoué en mode normal."
        exit "${global_status}"
    fi
    log_info "=== MODE NORMAL : tous les modules terminés ==="
}

# -----------------------------------------------------------------------
# run_fork : exécution parallèle via sous-processus (fork avec & et wait)
# Chaque module est lancé en arrière-plan. Le script attend leur fin.
# -----------------------------------------------------------------------
run_fork() {
    log_info "=== MODE FORK : exécution parallèle par sous-processus ==="
    local pids=()           # tableau des PIDs des processus fils
    local scripts_map=()    # tableau des noms de scripts pour le suivi

    # Lancement de chaque module dans un sous-processus indépendant
    for script in "${COLLEAGUE_SCRIPTS[@]}"; do
        local module_name
        module_name="$(basename "${script}")"
        log_info "  [FORK] Création du sous-processus pour : ${module_name}"

        # Fork : lancement en arrière-plan (&)
        bash "${script}" "${TARGET_DIR}" &
        local pid=$!
        pids+=("${pid}")
        scripts_map+=("${module_name}")
        log_info "  [FORK] PID ${pid} → ${module_name}"
    done

    # Attente de la fin de tous les processus fils
    log_info "  [FORK] Attente de la fin de tous les processus fils..."
    local global_status=0

    for i in "${!pids[@]}"; do
        wait "${pids[$i]}"
        local exit_code=$?
        if [[ ${exit_code} -ne 0 ]]; then
            log_error "  [FORK] ✗ ${scripts_map[$i]} (PID ${pids[$i]}) a échoué (code: ${exit_code})"
            global_status="${ERR_MODULE_FAILED}"
        else
            log_info "  [FORK] ✓ ${scripts_map[$i]} (PID ${pids[$i]}) terminé avec succès."
        fi
    done

    if [[ ${global_status} -ne 0 ]]; then
        log_error "Un ou plusieurs modules ont échoué en mode fork."
        exit "${global_status}"
    fi
    log_info "=== MODE FORK : tous les processus fils terminés ==="
}

# -----------------------------------------------------------------------
# run_thread : simulation de parallélisme en Bash
# En Bash, il n'y a pas de threads natifs. On simule le parallélisme
# via des sous-processus en arrière-plan (comportement similaire au fork).
# Si un outil externe threadé est disponible (ex: programme C compilé),
# il peut être appelé ici sans casser le script s'il est absent.
# -----------------------------------------------------------------------
run_thread() {
    log_info "=== MODE THREAD : simulation de parallélisme en Bash ==="
    log_info "  [INFO] Bash ne supporte pas les threads natifs."
    log_info "  [INFO] Simulation via sous-processus parallèles (comme le mode fork)."

    # Vérification optionnelle : si un programme C threadé existe dans scripts/
    # EMPLACEMENT RÉSERVÉ : remplacer par le vrai programme si disponible
    local threaded_prog="${SCRIPTS_DIR}/threaded_runner"
    if [[ -x "${threaded_prog}" ]]; then
        log_info "  [THREAD] Programme threadé détecté : ${threaded_prog}"
        log_info "  [THREAD] Délégation au programme externe..."
        "${threaded_prog}" "${TARGET_DIR}" "${COLLEAGUE_SCRIPTS[@]}"
        local exit_code=$?
        if [[ ${exit_code} -ne 0 ]]; then
            log_error "  [THREAD] Échec du programme threadé (code: ${exit_code})"
            exit "${ERR_MODULE_FAILED}"
        fi
        log_info "  [THREAD] Programme threadé terminé avec succès."
    else
        # Fallback : simulation par sous-processus parallèles (identique au fork)
        log_info "  [THREAD] Programme threadé absent → simulation par sous-processus."
        local pids=()
        local scripts_map=()

        for script in "${COLLEAGUE_SCRIPTS[@]}"; do
            local module_name
            module_name="$(basename "${script}")"
            bash "${script}" "${TARGET_DIR}" &
            local pid=$!
            pids+=("${pid}")
            scripts_map+=("${module_name}")
            log_info "  [THREAD] Sous-processus lancé : ${module_name} (PID ${pid})"
        done

        local global_status=0
        for i in "${!pids[@]}"; do
            wait "${pids[$i]}"
            local exit_code=$?
            if [[ ${exit_code} -ne 0 ]]; then
                log_error "  [THREAD] ✗ ${scripts_map[$i]} échoué (code: ${exit_code})"
                global_status="${ERR_MODULE_FAILED}"
            else
                log_info "  [THREAD] ✓ ${scripts_map[$i]} terminé."
            fi
        done

        if [[ ${global_status} -ne 0 ]]; then
            exit "${global_status}"
        fi
    fi

    log_info "=== MODE THREAD : traitement terminé ==="
}

# -----------------------------------------------------------------------
# run_subshell : exécution dans des sous-shells isolés (parenthèses)
# Chaque module est exécuté dans un environnement isolé.
# Les modifications de variables dans le sous-shell n'affectent pas le parent.
# -----------------------------------------------------------------------
run_subshell() {
    log_info "=== MODE SUBSHELL : exécution dans des sous-shells isolés ==="
    local global_status=0

    for script in "${COLLEAGUE_SCRIPTS[@]}"; do
        local module_name
        module_name="$(basename "${script}")"
        log_info "  [SUBSHELL] Lancement dans un sous-shell isolé : ${module_name}"

        # Exécution dans un sous-shell entre parenthèses
        # L'environnement du shell parent est copié mais toute modification
        # effectuée dans le sous-shell reste locale à celui-ci.
        (
            # Le sous-shell hérite des variables mais travaille en isolation
            log_info "    [SUBSHELL] Début du sous-shell pour : ${module_name} (PID $$)"
            bash "${script}" "${TARGET_DIR}"
            local exit_code=$?
            if [[ ${exit_code} -ne 0 ]]; then
                log_error "    [SUBSHELL] ✗ ${module_name} échoué (code: ${exit_code})"
                exit "${ERR_MODULE_FAILED}"
            fi
            log_info "    [SUBSHELL] ✓ ${module_name} terminé dans le sous-shell."
        )

        # Récupération du code de retour du sous-shell
        local subshell_exit=$?
        if [[ ${subshell_exit} -ne 0 ]]; then
            log_error "  [SUBSHELL] Sous-shell pour ${module_name} a retourné une erreur."
            global_status="${ERR_MODULE_FAILED}"
        fi
    done

    if [[ ${global_status} -ne 0 ]]; then
        log_error "Un ou plusieurs modules ont échoué en mode subshell."
        exit "${global_status}"
    fi
    log_info "=== MODE SUBSHELL : tous les sous-shells terminés ==="
}

# ==============================================================================
# SECTION 9 : PARSING DES OPTIONS (getopts)
# ==============================================================================

# Affiche une erreur d'usage et quitte
# Usage : usage_error "message d'erreur" <code_erreur>
usage_error() {
    local msg="$1"
    local code="${2:-${ERR_INVALID_OPTION}}"
    log_error "${msg}"
    show_help
    exit "${code}"
}

# Parsing des options avec getopts
# La chaîne "hftsl:r" définit les options acceptées :
#   h, f, t, s, r → options sans argument
#   l              → option avec argument (le : après l)
parse_options() {
    while getopts ":hftsl:r" opt; do
        case "${opt}" in
            h)
                # Option -h : affichage de l'aide puis sortie propre
                show_help
                exit 0
                ;;
            f)
                # Option -f : activation du mode fork
                EXEC_MODE="fork"
                ;;
            t)
                # Option -t : activation du mode thread
                EXEC_MODE="thread"
                ;;
            s)
                # Option -s : activation du mode subshell
                EXEC_MODE="subshell"
                ;;
            l)
                # Option -l : répertoire de log personnalisé
                # $OPTARG contient la valeur passée après -l
                LOG_DIR="${OPTARG}"
                ;;
            r)
                # Option -r : activation du mode restore (admin uniquement)
                OPT_RESTORE=true
                ;;
            :)
                # Option reconnue mais sans argument (ex: -l sans chemin)
                usage_error "L'option -${OPTARG} nécessite un argument." "${ERR_INVALID_OPTION}"
                ;;
            \?)
                # Option inconnue
                usage_error "Option invalide : -${OPTARG}" "${ERR_INVALID_OPTION}"
                ;;
        esac
    done

    # Décalage des arguments : après getopts, $@ ne contient plus les options
    # $OPTIND pointe sur le premier argument non-option
    shift $((OPTIND - 1))

    # Récupération du paramètre obligatoire TARGET_DIR
    TARGET_DIR="$1"

    # Vérification que TARGET_DIR a bien été fourni
    if [[ -z "${TARGET_DIR}" ]]; then
        usage_error "Paramètre obligatoire manquant : TARGET_DIR" "${ERR_MISSING_PARAM}"
    fi

    # Vérification que TARGET_DIR est un répertoire valide et accessible
    if [[ ! -d "${TARGET_DIR}" ]]; then
        usage_error "Le répertoire cible est invalide ou inaccessible : '${TARGET_DIR}'" "${ERR_INVALID_DIR}"
    fi

    # Normalisation du chemin (résolution du chemin absolu)
    TARGET_DIR="$(realpath "${TARGET_DIR}")"
}

# ==============================================================================
# SECTION 10 : POINT D'ENTRÉE PRINCIPAL
# ==============================================================================

main() {
    # --- Étape 1 : Parsing des options et du paramètre obligatoire ---
    parse_options "$@"

    # --- Étape 2 : Initialisation du système de journalisation ---
    init_log

    # --- Étape 3 : Bannière de démarrage ---
    log_info "======================================================"
    log_info " ${PROG_NAME} v${VERSION} - Démarrage"
    log_info "======================================================"
    log_info "Utilisateur       : $(_username)"
    log_info "Répertoire cible  : ${TARGET_DIR}"
    log_info "Mode d'exécution  : ${EXEC_MODE}"
    log_info "Fichier de log    : ${LOG_FILE}"
    log_info "Option restore    : ${OPT_RESTORE}"
    log_info "======================================================"

    # --- Étape 4 : Traitement de l'option -r (restore) en priorité ---
    if [[ "${OPT_RESTORE}" == true ]]; then
        # Vérification des privilèges administrateur (obligatoire pour -r)
        check_admin
        restore_defaults
        log_info "Restauration effectuée. Fin du programme."
        exit 0
    fi

    # --- Étape 5 : Vérification des scripts des collègues ---
    check_dependencies

    # --- Étape 6 : Exécution selon le mode choisi ---
    log_info "Début de l'exécution en mode : ${EXEC_MODE^^}"

    case "${EXEC_MODE}" in
        normal)
            run_normal
            ;;
        fork)
            run_fork
            ;;
        thread)
            run_thread
            ;;
        subshell)
            run_subshell
            ;;
        *)
            # Mode inconnu (ne devrait pas arriver grâce à getopts)
            usage_error "Mode d'exécution inconnu : ${EXEC_MODE}" "${ERR_INVALID_OPTION}"
            ;;
    esac

    # --- Étape 7 : Fin normale du programme ---
    log_info "======================================================"
    log_info " ${PROG_NAME} v${VERSION} - Terminé avec succès"
    log_info "======================================================"
    exit 0
}

# Appel du point d'entrée en transmettant tous les arguments du script
main "$@"
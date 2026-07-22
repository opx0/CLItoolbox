#!/usr/bin/env bash
# =============================================================================
# devbox/cli/clean/docker.sh — Interactive Docker inspector & tiered cleaner
# =============================================================================
# Shows the full Docker state (swarm/containers/images/volumes/networks) and
# lets you pick a cleanup LEVEL (Safe → Nuke). Every destructive step is shown
# and confirmed before running. Honours --dry-run.
#
# Usage:
#   docker.sh                 # interactive menu
#   docker.sh --dry-run       # show commands, change nothing
#   docker.sh --state         # print state dashboard and exit
#   docker.sh --level N        # run level N (1-4) non-interactively (asks confirm)
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../lib/common.sh"

DRY_RUN=false
NONINTERACTIVE_LEVEL=""
SHOW_CMDS=true   # print the read-only command behind each dashboard section

# -----------------------------------------------------------------------------
# CORE HELPERS
# -----------------------------------------------------------------------------

# Echo a command (dimmed) then run it — unless dry-run. Never aborts the script.
run() {
    log_dim "\$ $*"
    if [[ "$DRY_RUN" == true ]]; then
        return 0
    fi
    "$@" || log_warn "exited with status $? (continuing)"
}

# Free space on / for before/after reporting
root_avail() { df -h --output=avail / 2>/dev/null | tail -1 | tr -d ' '; }

# Transparency: echo the (concise) read-only command behind a dashboard section.
qc() { [[ "$SHOW_CMDS" == true ]] && echo "${C_DIM}  \$ $*${C_RESET}"; return 0; }

pause() {
    [[ -n "$NONINTERACTIVE_LEVEL" ]] && return 0
    echo -n "${C_DIM}  ↵ Enter to continue…${C_RESET}"
    read -r _ || true
    echo ""
}

require_docker() {
    require_cmd docker "your package manager (e.g. sudo pacman -S docker)"
    if ! docker info &>/dev/null; then
        die "Docker daemon not reachable. Start it: sudo systemctl start docker"
    fi
}

swarm_active() {
    [[ "$(docker info --format '{{.Swarm.LocalNodeState}}' 2>/dev/null)" == "active" ]]
}

# -----------------------------------------------------------------------------
# STATE DASHBOARD
# -----------------------------------------------------------------------------

show_state() {
    echo ""
    echo "${C_BOLD}══════════════════════ DOCKER STATE ══════════════════════${C_RESET}"

    echo ""
    echo "${C_CYAN}▸ Disk usage${C_RESET}"
    qc 'docker system df'
    docker system df 2>/dev/null || true

    if swarm_active; then
        echo ""
        echo "${C_CYAN}▸ Swarm services${C_RESET}  ${C_DIM}(swarm is ACTIVE — services own some containers)${C_RESET}"
        qc 'docker service ls'
        docker service ls 2>/dev/null || true
        # Flag any service that isn't at full replicas
        local bad
        bad=$(docker service ls --format '{{.Name}} {{.Replicas}}' 2>/dev/null \
              | awk '{split($2,a,"/"); if (a[1]!=a[2]) print "   ⚠ "$1" "$2}')
        [[ -n "$bad" ]] && echo "${C_YELLOW}$bad${C_RESET}"
    fi

    echo ""
    echo "${C_CYAN}▸ Running containers${C_RESET}"
    qc "docker ps --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}'"
    docker ps --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}' 2>/dev/null || true

    echo ""
    local stopped
    stopped=$(docker ps -aq --filter status=exited 2>/dev/null | wc -l)
    echo "${C_CYAN}▸ Stopped containers ($stopped)${C_RESET}"
    qc "docker ps -a --filter status=exited --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}'"
    docker ps -a --filter status=exited --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}' 2>/dev/null | head -30 || true

    echo ""
    local dvol
    dvol=$(docker volume ls -qf dangling=true 2>/dev/null | wc -l)
    echo "${C_CYAN}▸ Volumes — total $(docker volume ls -q 2>/dev/null | wc -l), dangling $dvol${C_RESET}"
    echo "${C_DIM}  named volumes WITH data (don't blind-prune):${C_RESET}"
    qc 'docker system df -v   # Local Volumes section, size>0'
    docker system df -v 2>/dev/null | awk '/Local Volumes space usage/{f=1;next} /^Build cache/{f=0} f && $1!="VOLUME" && $1!="" {if ($2>0) print "   "$1"  links="$2"  "$3}' | sort -k3 -h | tail -8 || true

    echo ""
    echo "${C_CYAN}▸ Biggest images (size · #containers using it)${C_RESET}"
    qc "docker images --format '{{.Size}}\t{{.Repository}}:{{.Tag}}\t{{.ID}}' | sort -rh | head -12"
    qc 'per image: docker ps -aq --filter ancestor=<id> | wc -l   # =0 ⇒ safe'
    docker images --format '{{.Size}}\t{{.Repository}}:{{.Tag}}\t{{.ID}}' 2>/dev/null \
        | sort -rh | head -12 \
        | while IFS=$'\t' read -r size ref id; do
            local n
            n=$(docker ps -aq --filter ancestor="$id" 2>/dev/null | wc -l)
            if [[ "$n" -eq 0 ]]; then
                printf '   %b%-8s%b %s  %b(0 containers — safe to remove)%b\n' \
                    "$C_GREEN" "$size" "$C_RESET" "$ref" "$C_DIM" "$C_RESET"
            else
                printf '   %-8s %s  %b(%s container[s])%b\n' \
                    "$size" "$ref" "$C_DIM" "$n" "$C_RESET"
            fi
        done

    echo ""
    echo "${C_CYAN}▸ Networks${C_RESET}"
    qc "docker network ls --format 'table {{.Name}}\t{{.Driver}}\t{{.Scope}}'"
    docker network ls --format 'table {{.Name}}\t{{.Driver}}\t{{.Scope}}' 2>/dev/null || true

    echo ""
    echo "${C_DIM}Free on / : $(root_avail)${C_RESET}"
    echo "${C_BOLD}═══════════════════════════════════════════════════════════${C_RESET}"
}

# -----------------------------------------------------------------------------
# SWARM DIAGNOSTICS (the flapping postgres service)
# -----------------------------------------------------------------------------

swarm_diagnostics() {
    if ! swarm_active; then
        log_info "Swarm is not active on this host — nothing to diagnose."
        return 0
    fi
    echo ""
    echo "${C_BOLD}── Swarm diagnostics ──${C_RESET}"
    qc 'docker node ls'
    docker node ls 2>/dev/null || true
    local svc
    for svc in $(docker service ls --format '{{.Name}}' 2>/dev/null); do
        echo ""
        echo "${C_CYAN}▸ service: $svc${C_RESET}"
        qc "docker service ps $svc --no-trunc --format 'table {{.Name}}\t{{.CurrentState}}\t{{.Error}}'"
        docker service ps "$svc" --no-trunc --format 'table {{.Name}}\t{{.CurrentState}}\t{{.Error}}' 2>/dev/null | head -12 || true
        # If it has errors, offer to tail its logs
        if docker service ps "$svc" --format '{{.Error}}' 2>/dev/null | grep -q .; then
            log_warn "$svc has task errors above."
            if ask_no "Tail last 40 log lines for '$svc'?"; then
                docker service logs "$svc" --tail 40 2>&1 | tail -40 || true
            fi
        fi
    done
    echo ""
    log_dim "Task-history retention: $(docker info --format '{{.Swarm.Cluster.Spec.Orchestration.TaskHistoryRetentionLimit}}' 2>/dev/null)"
    pause
}

# -----------------------------------------------------------------------------
# CLEANUP LEVELS
# -----------------------------------------------------------------------------

confirm_level() {
    local title="$1"
    echo ""
    echo "${C_BOLD}$title${C_RESET}"
    shift
    local line
    for line in "$@"; do echo "  • $line"; done
    echo ""
    [[ "$DRY_RUN" == true ]] && { log_warn "DRY RUN — nothing will be deleted"; return 0; }
    ask_no "Proceed?"
}

# Remove only UNUSED custom networks; never touch system / swarm-infra networks
# (bridge, host, none, docker_gwbridge, ingress). Safer than `network prune -f`,
# which will happily delete docker_gwbridge when momentarily idle.
prune_networks_safe() {
    local protected='^(bridge|host|none|docker_gwbridge|ingress)$'
    local net attached
    for net in $(docker network ls --format '{{.Name}}' 2>/dev/null | grep -vE "$protected"); do
        attached=$(docker network inspect "$net" --format '{{range .Containers}}x{{end}}' 2>/dev/null)
        if [[ -z "$attached" ]]; then
            run docker network rm "$net"
        else
            log_dim "keep network $net (in use)"
        fi
    done
}

# LEVEL 1 — SAFE: stopped containers, dangling images, unused networks, build cache.
# No volumes, no tagged images, no data loss.
level1_safe() {
    confirm_level "LEVEL 1 — SAFE (no data loss)" \
        "Remove ALL stopped containers (incl. dead swarm task-history)" \
        "Remove dangling (untagged) images" \
        "Remove unused networks" \
        "Remove build cache" || { log_info "Skipped level 1."; return 0; }
    run docker container prune -f
    run docker image prune -f
    prune_networks_safe
    run docker builder prune -f
    log_ok "Level 1 done."
}

# LEVEL 2 — MODERATE: + dangling volumes + ALL unused images + trim swarm history.
level2_moderate() {
    level1_safe
    confirm_level "LEVEL 2 — MODERATE (forces image re-pulls; drops anonymous volumes)" \
        "Remove dangling (anonymous, unattached) volumes" \
        "Remove ALL images not used by a RUNNING container (re-pull later)" \
        "Lower swarm task-history limit to 2 (less dead-task buildup)" \
        || { log_info "Skipped level 2."; return 0; }
    run docker volume prune -f
    run docker image prune -a -f
    if swarm_active; then
        run docker swarm update --task-history-limit 2
    fi
    log_ok "Level 2 done."
}

# LEVEL 3 — AGGRESSIVE / interactive: per-big-image, finished compose projects, swarm services.
level3_aggressive() {
    echo ""
    echo "${C_BOLD}LEVEL 3 — AGGRESSIVE (interactive, per-item confirm)${C_RESET}"

    # 3a. Big images not used by any container.
    # NOTE: read into an array FIRST — looping over a `... | while` pipe would make
    # ask_no's `read` consume the piped image list instead of your y/N answer.
    echo ""
    log_info "Images ≥ 500 MB not used by any container:"
    local -a imglines
    mapfile -t imglines < <(docker images --format '{{.Size}}\t{{.Repository}}:{{.Tag}}\t{{.ID}}' 2>/dev/null | sort -rh)
    local line size ref id mb
    for line in "${imglines[@]}"; do
        IFS=$'\t' read -r size ref id <<<"$line"
        mb=$(echo "$size" | awk '{n=$1+0; if($1 ~ /GB/) n*=1024; print int(n)}')
        [[ "$mb" -lt 500 ]] && continue
        [[ -n "$(docker ps -aq --filter ancestor="$id" 2>/dev/null)" ]] && continue
        if ask_no "Remove image $ref ($size)?"; then
            run docker rmi "$ref"
        fi
    done

    # 3b. Stopped compose projects
    echo ""
    log_info "Compose projects with only stopped containers:"
    local projects
    projects=$(docker ps -a --format '{{.Label "com.docker.compose.project"}}|{{.State}}' 2>/dev/null \
               | grep -v '^|' | sort -u)
    # find projects where no container is running
    local proj
    for proj in $(echo "$projects" | cut -d'|' -f1 | sort -u); do
        [[ -z "$proj" ]] && continue
        local running
        running=$(docker ps --format '{{.Label "com.docker.compose.project"}}' 2>/dev/null | grep -cx "$proj" || true)
        if [[ "$running" -eq 0 ]]; then
            local dir
            dir=$(docker inspect "$(docker ps -aq --filter label=com.docker.compose.project="$proj" | head -1)" \
                  --format '{{index .Config.Labels "com.docker.compose.project.working_dir"}}' 2>/dev/null)
            if ask_no "Project '$proj' (dir: ${dir:-?}) is fully stopped. Remove its containers + named volumes?"; then
                if [[ -n "$dir" && -d "$dir" ]]; then
                    run docker compose -p "$proj" --project-directory "$dir" down -v
                else
                    log_warn "No working dir; removing containers only."
                    run docker rm $(docker ps -aq --filter label=com.docker.compose.project="$proj")
                fi
            fi
        fi
    done

    # 3c. Swarm services
    if swarm_active; then
        echo ""
        log_info "Swarm services:"
        local svc
        for svc in $(docker service ls --format '{{.Name}}' 2>/dev/null); do
            if ask_no "Remove swarm service '$svc' (stops + removes all its tasks)?"; then
                run docker service rm "$svc"
            fi
        done
        if [[ -z "$(docker service ls -q 2>/dev/null)" ]]; then
            if ask_no "No services left. Leave swarm entirely (docker swarm leave --force)?"; then
                run docker swarm leave --force
            fi
        fi
    fi
    log_ok "Level 3 done."
}

# LEVEL 4 — NUKE: everything unused, including volumes. Double confirm.
level4_nuke() {
    echo ""
    log_error "LEVEL 4 — NUKE: removes ALL stopped containers, ALL unused images,"
    log_error "ALL unused networks, ALL unused volumes (DATA LOSS), and build cache."
    log_error "Running containers and the volumes they use are kept."
    echo ""
    [[ "$DRY_RUN" == true ]] && { log_warn "DRY RUN"; run docker system prune -a --volumes; return 0; }
    if ! ask_no "Are you sure?"; then log_info "Aborted."; return 0; fi
    # Read inline (NOT via ask_value in $(), which would swallow the prompt)
    local word=""
    echo -n "${C_RED}? Type NUKE to confirm: ${C_RESET}"
    read -r word || true
    [[ "$word" == "NUKE" ]] || { log_info "Not confirmed — aborted."; return 0; }
    run docker system prune -a --volumes -f
    log_ok "Nuke complete."
}

# -----------------------------------------------------------------------------
# MENU
# -----------------------------------------------------------------------------

run_level() {
    local before; before=$(root_avail)
    case "$1" in
        1) level1_safe ;;
        2) level2_moderate ;;
        3) level3_aggressive ;;
        4) level4_nuke ;;
        *) log_error "Unknown level: $1"; return 1 ;;
    esac
    echo ""
    log_ok "Free on / : $before → $(root_avail)"
    docker system df 2>/dev/null || true
}

menu() {
    while true; do
        echo ""
        local dr=""
        [[ "$DRY_RUN" == true ]] && dr="  ${C_YELLOW}[dry-run]${C_RESET}"
        echo "${C_BOLD}Docker cleanup — pick an action${C_RESET}$dr"
        echo "  ${C_CYAN}1${C_RESET}) Show full state dashboard"
        echo "  ${C_CYAN}2${C_RESET}) Swarm diagnostics (flapping services + logs)"
        echo "  ${C_GREEN}3${C_RESET}) LEVEL 1 — Safe   (stopped containers, dangling images/networks/cache)"
        echo "  ${C_GREEN}4${C_RESET}) LEVEL 2 — Moderate (+ dangling volumes, all unused images, trim swarm)"
        echo "  ${C_YELLOW}5${C_RESET}) LEVEL 3 — Aggressive (interactive: big images, compose down, services)"
        echo "  ${C_RED}6${C_RESET}) LEVEL 4 — Nuke   (system prune -a --volumes)"
        echo "  ${C_CYAN}d${C_RESET}) Toggle dry-run (currently: $DRY_RUN)"
        echo "  ${C_CYAN}c${C_RESET}) Toggle show-commands (currently: $SHOW_CMDS)"
        echo "  ${C_CYAN}q${C_RESET}) Quit"
        echo -n "${C_CYAN}? choice${C_RESET}: "
        local choice
        read -r choice || exit 0
        case "$choice" in
            1) show_state; pause ;;
            2) swarm_diagnostics ;;
            3) run_level 1; pause ;;
            4) run_level 2; pause ;;
            5) run_level 3; pause ;;
            6) run_level 4; pause ;;
            d|D) if [[ "$DRY_RUN" == true ]]; then DRY_RUN=false; else DRY_RUN=true; fi ;;
            c|C) if [[ "$SHOW_CMDS" == true ]]; then SHOW_CMDS=false; else SHOW_CMDS=true; fi ;;
            q|Q|"") echo "bye"; exit 0 ;;
            *) log_warn "Unknown choice: $choice" ;;
        esac
    done
}

# -----------------------------------------------------------------------------
# MAIN
# -----------------------------------------------------------------------------

usage() {
    cat <<EOF
Usage: $(basename "$0") [options]

Interactive Docker inspector + tiered cleaner.

Options:
  --state        Print the state dashboard and exit
  --level N      Run cleanup level N (1-4) directly (still asks confirmation)
  --dry-run      Show every command, change nothing
  --no-cmds      Hide the read-only command shown above each dashboard section
  --help, -h     This help

Levels:
  1 Safe       stopped containers + dangling images/networks/build cache
  2 Moderate   + dangling volumes + ALL unused images + trim swarm history
  3 Aggressive interactive: per big image, 'compose down -v' stopped projects, swarm services
  4 Nuke       docker system prune -a --volumes  (double-confirm)
EOF
    exit 0
}

main() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --dry-run) DRY_RUN=true; shift ;;
            --no-cmds) SHOW_CMDS=false; shift ;;
            --state)   NONINTERACTIVE_LEVEL="state"; shift ;;
            --level)   NONINTERACTIVE_LEVEL="$2"; shift 2 ;;
            --help|-h) usage ;;
            *) die "Unknown option: $1 (try --help)" ;;
        esac
    done

    require_docker

    if [[ "$NONINTERACTIVE_LEVEL" == "state" ]]; then
        show_state
        exit 0
    elif [[ -n "$NONINTERACTIVE_LEVEL" ]]; then
        show_state
        run_level "$NONINTERACTIVE_LEVEL"
        exit 0
    fi

    show_state
    menu
}

main "$@"

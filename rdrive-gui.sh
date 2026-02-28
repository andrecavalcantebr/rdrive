#!/usr/bin/env bash
set -u -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

CONF_DIR="${HOME}/.config/rdrive"
CONF_FILE="${CONF_DIR}/rdrive.conf"
INSTALL_SCRIPT="${SCRIPT_DIR}/rdrive-install.sh"

BIN_MOUNT="${HOME}/.local/bin/rdrive-mount.sh"
BIN_REFRESH="${HOME}/.local/bin/rdrive-refresh.sh"

LOG_DIR="${HOME}/.cache/rdrive-logs"
RUN_LOG="${LOG_DIR}/rdrive-gui-$(date +%Y%m%d-%H%M%S).log"

REMOTE_NAMES=()
REMOTE_ROOT_IDS=()
REMOTE_MOUNT_SUBS=()
REMOTE_CREDS=()
UNKNOWN_GLOBAL_LINES=()

KNOWN_KEYS=(
  MOUNT_BASE
  CACHE_DIR
  LOG_DIR
  VFS_CACHE_MODE
  VFS_CACHE_MAX_SIZE
  VFS_CACHE_MAX_AGE
  BUFFER_SIZE
  DIR_CACHE_TIME
  POLL_INTERVAL
  UMASK
  EXPORT_FORMATS
)

str_trim() {
  local s="$1"
  s="${s#"${s%%[![:space:]]*}"}"
  s="${s%"${s##*[![:space:]]}"}"
  printf '%s' "$s"
}

path_expand() {
  local p="$1"
  p="$(str_trim "$p")"

  if [[ "$p" == \"*\" && "$p" == *\" ]]; then
    p="${p:1:${#p}-2}"
  elif [[ "$p" == \'*\' && "$p" == *\' ]]; then
    p="${p:1:${#p}-2}"
  fi

  p="$(str_trim "$p")"

  if [[ "$p" == "$HOME/~/"* ]]; then
    printf '%s' "${HOME}/${p#"$HOME/~/"}"
    return
  fi

  if [[ "$p" == "~" ]]; then
    printf '%s' "$HOME"
    return
  fi

  if [[ "$p" == ~/* ]]; then
    printf '%s' "${HOME}/${p#~/}"
    return
  fi

  if [[ "$p" == '$HOME' ]]; then
    printf '%s' "$HOME"
    return
  fi

  if [[ "$p" == '$HOME/'* ]]; then
    printf '%s' "${HOME}/${p#\$HOME/}"
    return
  fi

  if [[ "$p" == '${HOME}' ]]; then
    printf '%s' "$HOME"
    return
  fi

  if [[ "$p" == '${HOME}/'* ]]; then
    printf '%s' "${HOME}/${p#\$\{HOME\}/}"
    return
  fi

  printf '%s' "$p"
}

config_normalize_runtime_paths() {
  MOUNT_BASE="$(realpath -m "$(path_expand "$MOUNT_BASE")")"
  CACHE_DIR="$(realpath -m "$(path_expand "$CACHE_DIR")")"
  LOG_DIR="$(realpath -m "$(path_expand "$LOG_DIR")")"
}

ui_error() {
  zenity --error --title="RDrive GUI" --width=560 --text="$1" >/dev/null 2>&1 || true
}

ui_warning() {
  zenity --warning --title="RDrive GUI" --width=560 --text="$1" >/dev/null 2>&1 || true
}

ui_info() {
  zenity --info --title="RDrive GUI" --width=560 --text="$1" >/dev/null 2>&1 || true
}

config_is_known_key() {
  local key="$1"
  local k
  for k in "${KNOWN_KEYS[@]}"; do
    [[ "$k" == "$key" ]] && return 0
  done
  return 1
}

config_set_defaults() {
  MOUNT_BASE="$HOME/rdrive"
  CACHE_DIR="$HOME/.cache/rdrive-rclone"
  LOG_DIR="$HOME/.cache/rdrive-logs"
  VFS_CACHE_MODE="full"
  VFS_CACHE_MAX_SIZE="2G"
  VFS_CACHE_MAX_AGE="72h"
  BUFFER_SIZE="64M"
  DIR_CACHE_TIME="72h"
  POLL_INTERVAL="1m"
  UMASK="002"
  EXPORT_FORMATS="link.html"
}

config_write_embedded_example() {
  mkdir -p "$CONF_DIR"

  cat > "$CONF_FILE" <<'EOF'
# rdrive.conf (gerado pelo rdrive-gui.sh)
# Allowed lines:
#   KEY=VALUE
#   REMOTE "remote_rclone","root_folder_or_empty","mount_subdir","path_to_credentials.json"

MOUNT_BASE=$HOME/rdrive
CACHE_DIR=$HOME/.cache/rdrive-rclone
LOG_DIR=$HOME/.cache/rdrive-logs

VFS_CACHE_MODE=full
VFS_CACHE_MAX_SIZE=2G
VFS_CACHE_MAX_AGE=72h
BUFFER_SIZE=64M
DIR_CACHE_TIME=72h
POLL_INTERVAL=1m
UMASK=002
EXPORT_FORMATS=link.html

REMOTE "UFAM","","UFAM","$HOME/.config/rdrive/credentials-ufam.json"
REMOTE "Pessoal","","Pessoal","$HOME/.config/rdrive/credentials-person.json"
REMOTE "EspacoLam","","EspacoLam","$HOME/.config/rdrive/credentials-lam.json"
EOF

  chmod 600 "$CONF_FILE" 2>/dev/null || true
}

config_load() {
  local file="$1"
  [[ -f "$file" ]] || return 1

  config_set_defaults
  REMOTE_NAMES=()
  REMOTE_ROOT_IDS=()
  REMOTE_MOUNT_SUBS=()
  REMOTE_CREDS=()
  UNKNOWN_GLOBAL_LINES=()

  local line key val
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%%#*}"
    line="$(str_trim "$line")"
    [[ -z "$line" ]] && continue

    if [[ "$line" =~ ^REMOTE[[:space:]]+\"([^\"]+)\"[[:space:]]*,[[:space:]]*\"([^\"]*)\"[[:space:]]*,[[:space:]]*\"([^\"]+)\"[[:space:]]*,[[:space:]]*\"([^\"]+)\"[[:space:]]*$ ]]; then
      REMOTE_NAMES+=("${BASH_REMATCH[1]}")
      REMOTE_ROOT_IDS+=("${BASH_REMATCH[2]}")
      REMOTE_MOUNT_SUBS+=("${BASH_REMATCH[3]}")
      REMOTE_CREDS+=("$(realpath -m "$(path_expand "${BASH_REMATCH[4]}")")")
      continue
    fi

    if [[ "$line" =~ ^[A-Za-z_][A-Za-z0-9_]*= ]]; then
      key="${line%%=*}"
      val="${line#*=}"
      key="$(str_trim "$key")"
      val="$(str_trim "$val")"
      if config_is_known_key "$key"; then
        printf -v "$key" '%s' "$val"
      else
        UNKNOWN_GLOBAL_LINES+=("${key}=${val}")
      fi
    fi
  done < "$file"

  config_normalize_runtime_paths

  return 0
}

config_validate_globals() {
  [[ -n "$MOUNT_BASE" ]] || { ui_error "MOUNT_BASE não pode ser vazio."; return 1; }
  [[ -n "$CACHE_DIR" ]] || { ui_error "CACHE_DIR não pode ser vazio."; return 1; }
  [[ -n "$LOG_DIR" ]] || { ui_error "LOG_DIR não pode ser vazio."; return 1; }
  if [[ ! "$UMASK" =~ ^[0-7]{3,4}$ ]]; then
    ui_error "UMASK inválido. Use octal (ex.: 002)."
    return 1
  fi
  return 0
}

config_validate_remotes() {
  if [[ "${#REMOTE_NAMES[@]}" -eq 0 ]]; then
    ui_error "Defina ao menos um REMOTE."
    return 1
  fi

  local -A seen_name=()
  local -A seen_mount=()
  local i n m c
  for i in "${!REMOTE_NAMES[@]}"; do
    n="${REMOTE_NAMES[$i]}"
    m="${REMOTE_MOUNT_SUBS[$i]}"
    c="${REMOTE_CREDS[$i]}"

    [[ -n "$n" ]] || { ui_error "Há REMOTE sem nome."; return 1; }
    [[ -n "$m" ]] || { ui_error "REMOTE '$n' sem pasta de montagem."; return 1; }
    [[ -n "$c" ]] || { ui_error "REMOTE '$n' sem caminho de credencial."; return 1; }

    if [[ ! -f "$c" ]]; then
      ui_error "Arquivo de credencial não encontrado para '$n': $c"
      return 1
    fi
    if [[ ! -r "$c" ]]; then
      ui_error "Sem permissão de leitura no arquivo de credencial de '$n': $c"
      return 1
    fi

    local nk="${n,,}"
    local mk="${m,,}"
    if [[ -n "${seen_name[$nk]:-}" ]]; then
      ui_error "Nome de REMOTE duplicado: $n"
      return 1
    fi
    if [[ -n "${seen_mount[$mk]:-}" ]]; then
      ui_error "Pasta de montagem duplicada: $m"
      return 1
    fi
    seen_name[$nk]=1
    seen_mount[$mk]=1
  done

  return 0
}

config_write() {
  config_validate_globals || return 1
  config_validate_remotes || return 1

  mkdir -p "$CONF_DIR"
  local tmp
  tmp="$(mktemp)"

  {
    echo "# rdrive.conf (gerado por rdrive-gui.sh)"
    echo "# Formato: KEY=VALUE e REMOTE \"name\",\"root\",\"mount\",\"cred\""
    echo
    echo "MOUNT_BASE=$MOUNT_BASE"
    echo "CACHE_DIR=$CACHE_DIR"
    echo "LOG_DIR=$LOG_DIR"
    echo
    echo "VFS_CACHE_MODE=$VFS_CACHE_MODE"
    echo "VFS_CACHE_MAX_SIZE=$VFS_CACHE_MAX_SIZE"
    echo "VFS_CACHE_MAX_AGE=$VFS_CACHE_MAX_AGE"
    echo "BUFFER_SIZE=$BUFFER_SIZE"
    echo "DIR_CACHE_TIME=$DIR_CACHE_TIME"
    echo "POLL_INTERVAL=$POLL_INTERVAL"
    echo "UMASK=$UMASK"
    echo "EXPORT_FORMATS=$EXPORT_FORMATS"

    if [[ "${#UNKNOWN_GLOBAL_LINES[@]}" -gt 0 ]]; then
      echo
      echo "# Chaves adicionais preservadas"
      local extra
      for extra in "${UNKNOWN_GLOBAL_LINES[@]}"; do
        echo "$extra"
      done
    fi

    echo
    local i
    for i in "${!REMOTE_NAMES[@]}"; do
      echo "REMOTE \"${REMOTE_NAMES[$i]}\",\"${REMOTE_ROOT_IDS[$i]}\",\"${REMOTE_MOUNT_SUBS[$i]}\",\"${REMOTE_CREDS[$i]}\""
    done
  } > "$tmp"

  if [[ -f "$CONF_FILE" ]]; then
    cp -f "$CONF_FILE" "${CONF_FILE}.bak" 2>/dev/null || true
  fi

  mv -f "$tmp" "$CONF_FILE"
  chmod 600 "$CONF_FILE" 2>/dev/null || true
  return 0
}

config_ensure_exists() {
  mkdir -p "$CONF_DIR"

  if [[ ! -f "$CONF_FILE" ]]; then
    config_write_embedded_example
  fi
}

system_scripts_installed() {
  [[ -x "$BIN_MOUNT" && -x "$BIN_REFRESH" ]]
}

ui_show_config_file() {
  zenity --text-info \
    --title="Visualização do arquivo" \
    --ok-label="Fechar" \
    --width=980 \
    --height=720 \
    --filename="$CONF_FILE" >/dev/null 2>&1 || true
}

show_welcome_flow() {
  zenity --question \
    --title="Bem-vindo" \
    --ok-label="OK" \
    --cancel-label="Cancelar" \
    --width=720 \
    --text="Bem-vindo ao RDrive GUI.\n\nEste assistente ajuda a configurar o arquivo:\n$CONF_FILE\n\nDepois da configuração, você poderá instalar scripts e autorizar remotes." >/dev/null 2>&1 || exit 0

  local choice
  choice="$(zenity --list --radiolist \
    --title="Como iniciar" \
    --ok-label="OK" \
    --cancel-label="Cancelar" \
    --width=760 --height=320 \
    --text="Escolha uma opção inicial:" \
    --column="" --column="Opção" \
    TRUE "Carregar configuração existente" \
    FALSE "Resetar configuração padrão" 2>/dev/null)" || exit 0

  if [[ "$choice" == "Resetar configuração padrão" ]]; then
    config_write_embedded_example
  fi

  config_load "$CONF_FILE" || {
    ui_error "Falha ao carregar configuração."
    exit 1
  }
}

edit_global_variable() {
  local key="$1"
  local help="$2"
  local current="$3"

  local new_value
  new_value="$(zenity --entry \
    --title="Editar variável" \
    --ok-label="OK" \
    --cancel-label="Cancelar" \
    --width=820 \
    --text="$help\n\n$key:" \
    --entry-text="$current" 2>/dev/null)" || return 1

  printf -v "$key" '%s' "$new_value"
  return 0
}

edit_global_settings_menu() {
  while true; do
    local action
    action="$(zenity --list \
      --title="Variáveis globais" \
      --ok-label="OK" \
      --cancel-label="Voltar" \
      --width=980 --height=560 \
      --text="Descrição/Ajuda e valor atual. Selecione uma variável para editar." \
      --column="Variável" --column="Valor Atual" --column="Ajuda" \
      "MOUNT_BASE" "$MOUNT_BASE" "Pasta base de montagem (recomendado: ~/rdrive)" \
      "CACHE_DIR" "$CACHE_DIR" "Cache VFS do rclone (recomendado: ~/.cache/rdrive-rclone)" \
      "LOG_DIR" "$LOG_DIR" "Diretório de logs (recomendado: ~/.cache/rdrive-logs)" \
      "VFS_CACHE_MODE" "$VFS_CACHE_MODE" "off|minimal|writes|full (recomendado: full)" \
      "VFS_CACHE_MAX_SIZE" "$VFS_CACHE_MAX_SIZE" "Tamanho máximo do cache (recomendado: 2G)" \
      "VFS_CACHE_MAX_AGE" "$VFS_CACHE_MAX_AGE" "Idade máxima do cache (recomendado: 72h)" \
      "BUFFER_SIZE" "$BUFFER_SIZE" "Buffer por arquivo aberto (recomendado: 64M)" \
      "DIR_CACHE_TIME" "$DIR_CACHE_TIME" "Cache de diretórios (recomendado: 72h)" \
      "POLL_INTERVAL" "$POLL_INTERVAL" "Intervalo de polling (recomendado: 1m)" \
      "UMASK" "$UMASK" "Permissões em octal (recomendado: 002)" \
      "EXPORT_FORMATS" "$EXPORT_FORMATS" "Formato de export (recomendado: link.html)" 2>/dev/null)" || return 0

    case "$action" in
      MOUNT_BASE)
        edit_global_variable "MOUNT_BASE" "Pasta base de montagem." "$MOUNT_BASE" || continue
        ;;
      CACHE_DIR)
        edit_global_variable "CACHE_DIR" "Diretório de cache VFS." "$CACHE_DIR" || continue
        ;;
      LOG_DIR)
        edit_global_variable "LOG_DIR" "Diretório de logs do rclone." "$LOG_DIR" || continue
        ;;
      VFS_CACHE_MODE)
        edit_global_variable "VFS_CACHE_MODE" "off|minimal|writes|full." "$VFS_CACHE_MODE" || continue
        ;;
      VFS_CACHE_MAX_SIZE)
        edit_global_variable "VFS_CACHE_MAX_SIZE" "Exemplo: 2G." "$VFS_CACHE_MAX_SIZE" || continue
        ;;
      VFS_CACHE_MAX_AGE)
        edit_global_variable "VFS_CACHE_MAX_AGE" "Exemplo: 72h." "$VFS_CACHE_MAX_AGE" || continue
        ;;
      BUFFER_SIZE)
        edit_global_variable "BUFFER_SIZE" "Exemplo: 64M." "$BUFFER_SIZE" || continue
        ;;
      DIR_CACHE_TIME)
        edit_global_variable "DIR_CACHE_TIME" "Exemplo: 72h." "$DIR_CACHE_TIME" || continue
        ;;
      POLL_INTERVAL)
        edit_global_variable "POLL_INTERVAL" "Exemplo: 1m." "$POLL_INTERVAL" || continue
        ;;
      UMASK)
        edit_global_variable "UMASK" "Use octal (exemplo: 002)." "$UMASK" || continue
        ;;
      EXPORT_FORMATS)
        edit_global_variable "EXPORT_FORMATS" "Exemplo: link.html." "$EXPORT_FORMATS" || continue
        ;;
    esac

    config_write || continue
    config_load "$CONF_FILE" || continue
  done
  return 0
}

remote_remove_at_index() {
  local idx="$1"
  unset 'REMOTE_NAMES[idx]'
  unset 'REMOTE_ROOT_IDS[idx]'
  unset 'REMOTE_MOUNT_SUBS[idx]'
  unset 'REMOTE_CREDS[idx]'

  REMOTE_NAMES=("${REMOTE_NAMES[@]}")
  REMOTE_ROOT_IDS=("${REMOTE_ROOT_IDS[@]}")
  REMOTE_MOUNT_SUBS=("${REMOTE_MOUNT_SUBS[@]}")
  REMOTE_CREDS=("${REMOTE_CREDS[@]}")
}

edit_single_remote() {
  local idx="$1"
  local is_new=0
  local name root mount_sub cred

  if [[ "$idx" == "novo" ]]; then
    is_new=1
    name=""
    root=""
    mount_sub=""
    cred="$HOME/.config/rdrive/credentials.json"
  else
    name="${REMOTE_NAMES[$idx]}"
    root="${REMOTE_ROOT_IDS[$idx]}"
    mount_sub="${REMOTE_MOUNT_SUBS[$idx]}"
    cred="${REMOTE_CREDS[$idx]}"
  fi

  while true; do
    local label_mount="$mount_sub"
    [[ -n "$label_mount" ]] || label_mount="<não definido>"
    local label_cred="$cred"
    [[ -n "$label_cred" ]] || label_cred="<não definido>"

    local action
    if [[ "$is_new" -eq 1 ]]; then
      action="$(zenity --list \
        --title="Edição de remote" \
        --ok-label="OK" \
        --cancel-label="Cancelar" \
        --width=920 --height=440 \
        --text="Selecione o campo para editar.\nPara pasta e arquivo, use o seletor padrão do sistema." \
        --column="Campo" --column="Valor" \
        "Nome do remote" "$name" \
        "Root folder ID" "${root:-<vazio>}" \
        "Pasta de montagem" "$label_mount" \
        "Arquivo de credencial" "$label_cred" \
        "Guardar" "Salvar este remote" 2>/dev/null)" || return 0
    else
      action="$(zenity --list \
        --title="Edição de remote" \
        --ok-label="OK" \
        --cancel-label="Cancelar" \
        --width=920 --height=500 \
        --text="Selecione o campo para editar.\nPara pasta e arquivo, use o seletor padrão do sistema." \
        --column="Campo" --column="Valor" \
        "Nome do remote" "$name" \
        "Root folder ID" "${root:-<vazio>}" \
        "Pasta de montagem" "$label_mount" \
        "Arquivo de credencial" "$label_cred" \
        "Guardar" "Salvar alterações" \
        "Excluir remote" "Remover este remote" 2>/dev/null)" || return 0
    fi

    case "$action" in
      "Nome do remote")
        local new_name
        new_name="$(zenity --entry \
          --title="Nome do remote" \
          --text="Exemplo: UFAM" \
          --entry-text="$name" 2>/dev/null)" || continue
        name="$(str_trim "$new_name")"
        ;;
      "Root folder ID")
        local new_root
        new_root="$(zenity --entry \
          --title="Root folder ID" \
          --text="Opcional. Pode deixar vazio." \
          --entry-text="$root" 2>/dev/null)" || continue
        root="$(str_trim "$new_root")"
        ;;
      "Pasta de montagem")
        local typed_mount
        typed_mount="$(zenity --entry \
          --title="Pasta de montagem" \
          --width=900 \
          --text="Informe somente o nome/subcaminho da pasta dentro de $MOUNT_BASE\n(ex.: Teste ou projetos/2026)." \
          --entry-text="${mount_sub:-Teste}" 2>/dev/null)" || continue
        typed_mount="$(str_trim "$typed_mount")"
        [[ -n "$typed_mount" ]] || continue
        mount_sub="$typed_mount"
        ;;
      "Arquivo de credencial")
        local current_guess chosen chosen_abs
        current_guess="$cred"
        chosen="$(zenity --file-selection \
          --title="Escolha o arquivo de credencial (somente caminho)" \
          --filename="$current_guess" 2>/dev/null)" || continue
        chosen_abs="$(realpath -m "$chosen")"
        if [[ ! -f "$chosen_abs" ]]; then
          ui_warning "Arquivo não encontrado: $chosen_abs"
          continue
        fi
        if [[ ! -r "$chosen_abs" ]]; then
          ui_warning "Sem permissão de leitura: $chosen_abs"
          continue
        fi
        cred="$chosen_abs"
        ;;
      Guardar)
        [[ -n "$name" ]] || { ui_error "Nome do remote é obrigatório."; continue; }
        [[ -n "$mount_sub" ]] || { ui_error "Pasta de montagem é obrigatória."; continue; }
        [[ -n "$cred" ]] || { ui_error "Arquivo de credencial é obrigatório."; continue; }

        if [[ "$is_new" -eq 1 ]]; then
          REMOTE_NAMES+=("$name")
          REMOTE_ROOT_IDS+=("$root")
          REMOTE_MOUNT_SUBS+=("$mount_sub")
          REMOTE_CREDS+=("$cred")
        else
          REMOTE_NAMES[$idx]="$name"
          REMOTE_ROOT_IDS[$idx]="$root"
          REMOTE_MOUNT_SUBS[$idx]="$mount_sub"
          REMOTE_CREDS[$idx]="$cred"
        fi

        config_write || {
          if [[ "$is_new" -eq 1 ]]; then
            remote_remove_at_index "$((${#REMOTE_NAMES[@]} - 1))"
          fi
          continue
        }
        config_load "$CONF_FILE" || true
        return 0
        ;;
      "Excluir remote")
        zenity --question --title="Confirmar" --text="Excluir este remote?" 2>/dev/null || continue
        remote_remove_at_index "$idx"
        config_write || return 1
        config_load "$CONF_FILE" || true
        return 0
        ;;
    esac
  done
}

edit_remotes_menu() {
  while true; do
    if [[ "${#REMOTE_NAMES[@]}" -eq 0 ]]; then
      ui_info "Nenhum remote cadastrado. Vamos criar o primeiro."
      edit_single_remote "novo"
      continue
    fi

    local args=(
      --list
      --title="Configuração de remotes"
      --ok-label="Editar"
      --cancel-label="Voltar"
      --width=1020
      --height=520
      --text="Selecione um remote para editar.\n(Use a linha 'NOVO REMOTE' para inserir.)"
      --print-column=1
      --column="ID"
      --column="Remote"
      --column="Root"
      --column="Mount"
      --column="Credencial"
    )

    local i
    for i in "${!REMOTE_NAMES[@]}"; do
      args+=("$i" "${REMOTE_NAMES[$i]}" "${REMOTE_ROOT_IDS[$i]}" "${REMOTE_MOUNT_SUBS[$i]}" "${REMOTE_CREDS[$i]}")
    done
    args+=("novo" "NOVO REMOTE" "" "" "")

    local selected
    selected="$(zenity "${args[@]}" 2>/dev/null)" || return 0
    [[ -n "$selected" ]] || continue
    edit_single_remote "$selected"
  done
}

edit_config_menu() {
  local snapshot
  snapshot="$(cat "$CONF_FILE" 2>/dev/null || true)"

  while true; do
    local action
    action="$(zenity --list \
      --title="Editar configurações" \
      --ok-label="OK" \
      --cancel-label="Voltar" \
      --width=760 --height=360 \
      --column="Opção" \
      "Visualizar arquivo atual" \
      "Editar variáveis globais" \
      "Editar remotes" \
      "Reverter edição" 2>/dev/null)" || return 0

    case "$action" in
      "Visualizar arquivo atual")
        ui_show_config_file
        ;;
      "Editar variáveis globais")
        edit_global_settings_menu
        ;;
      "Editar remotes")
        edit_remotes_menu
        ;;
      "Reverter edição")
        zenity --question --title="Reverter" --text="Reverter para o estado do início deste menu de edição?" 2>/dev/null || continue
        printf '%s\n' "$snapshot" > "$CONF_FILE"
        chmod 600 "$CONF_FILE" 2>/dev/null || true
        config_load "$CONF_FILE" || true
        ui_info "Edição revertida."
        ;;
    esac
  done
}

system_run_with_progress() {
  local title="$1"
  shift

  mkdir -p "$LOG_DIR"
  touch "$RUN_LOG"

  local rc_file
  rc_file="$(mktemp)"

  (
    echo "# ${title}" >> "$RUN_LOG"
    echo "# Início: $(date '+%F %T')" >> "$RUN_LOG"
    "$@" >> "$RUN_LOG" 2>&1
    echo "$?" > "$rc_file"
    echo "# Fim: $(date '+%F %T')" >> "$RUN_LOG"
  ) &

  local pid=$!
  (
    while kill -0 "$pid" 2>/dev/null; do
      echo "50"
      echo "# Executando..."
      sleep 1
    done
    echo "100"
    echo "# Concluído"
  ) | zenity --progress \
    --title="$title" \
    --width=680 \
    --auto-close \
    --no-cancel \
    --text="Executando..." >/dev/null 2>&1

  local rc
  rc="$(cat "$rc_file" 2>/dev/null || echo 1)"
  rm -f "$rc_file"
  return "$rc"
}

system_open_terminal_command() {
  local title="$1"
  local shell_cmd="$2"

  if command -v x-terminal-emulator >/dev/null 2>&1; then
    x-terminal-emulator -T "$title" -e bash -lc "$shell_cmd"
    return $?
  fi

  if command -v gnome-terminal >/dev/null 2>&1; then
    gnome-terminal --wait --title="$title" -- bash -lc "$shell_cmd"
    return $?
  fi

  ui_warning "Nenhum emulador de terminal foi encontrado. Executando no shell atual."
  bash -lc "$shell_cmd"
}

system_run_interactive_with_log() {
  local title="$1"
  shift

  mkdir -p "$LOG_DIR"
  touch "$RUN_LOG"

  local command_line shell_cmd rc
  printf -v command_line '%q ' "$@"
  printf -v shell_cmd 'set -o pipefail; %s 2>&1 | tee -a %q; rc=${PIPESTATUS[0]}; echo; echo "Pressione Enter para fechar esta janela..."; read -r _; exit "$rc"' "$command_line" "$RUN_LOG"

  {
    echo "# ${title}"
    echo "# Início: $(date '+%F %T')"
  } >> "$RUN_LOG"

  system_open_terminal_command "$title" "$shell_cmd"
  rc=$?

  {
    echo "# Fim: $(date '+%F %T')"
    echo "# Código de saída: ${rc}"
  } >> "$RUN_LOG"

  return "$rc"
}

ui_show_log() {
  zenity --text-info \
    --title="Log da execução" \
    --ok-label="Fechar" \
    --width=1000 --height=720 \
    --filename="$RUN_LOG" >/dev/null 2>&1 || true
}

install_scripts_flow() {
  [[ -x "$INSTALL_SCRIPT" ]] || {
    ui_error "Script não encontrado/executável: $INSTALL_SCRIPT"
    return 1
  }

  zenity --question \
    --title="Confirmação de instalação" \
    --ok-label="Instalar" \
    --cancel-label="Cancelar" \
    --width=640 \
    --text="Executar $INSTALL_SCRIPT agora?" >/dev/null 2>&1 || return 0

  if system_run_interactive_with_log "Instalando scripts" "$INSTALL_SCRIPT"; then
    ui_info "Instalação concluída."
  else
    ui_warning "Instalação terminou com erro. Veja o log."
  fi

  ui_show_log
  return 0
}

refresh_remote_flow() {
  if ! system_scripts_installed; then
    ui_warning "Refresh de remotes indisponível: scripts ainda não instalados."
    return 1
  fi

  [[ "${#REMOTE_NAMES[@]}" -gt 0 ]] || {
    ui_warning "Não há remotes no arquivo de configuração."
    return 1
  }

  local args=(
    --list
    --title="Refresh de remotes" 
    --ok-label="OK"
    --cancel-label="Voltar"
    --width=980
    --height=500
    --print-column=1
    --column="ID"
    --column="Remote"
    --column="Root"
    --column="Mount"
    --column="Credencial"
  )

  local i
  for i in "${!REMOTE_NAMES[@]}"; do
    args+=("$i" "${REMOTE_NAMES[$i]}" "${REMOTE_ROOT_IDS[$i]}" "${REMOTE_MOUNT_SUBS[$i]}" "${REMOTE_CREDS[$i]}")
  done

  local selected
  selected="$(zenity "${args[@]}" 2>/dev/null)" || return 0
  [[ -n "$selected" ]] || return 0

  local remote_name="${REMOTE_NAMES[$selected]}"
  zenity --question \
    --title="Autorizar remote" \
    --ok-label="Autorizar" \
    --cancel-label="Cancelar" \
    --width=700 \
    --text="Remote selecionado: ${remote_name}\n\nAbra o navegador no perfil correto desta conta e, em seguida, clique em Autorizar." >/dev/null 2>&1 || return 0

  if system_run_interactive_with_log "Autorizando ${remote_name}" "$BIN_REFRESH" "$remote_name"; then
    ui_info "Autorização concluída para '${remote_name}'."
  else
    ui_warning "Falha na autorização de '${remote_name}'. Veja o log."
  fi

  ui_show_log
}

uninstall_scripts_flow() {
  if ! system_scripts_installed; then
    ui_info "Scripts não estão instalados."
    return 0
  fi

  zenity --question \
    --title="Confirmar desinstalação" \
    --ok-label="Desinstalar" \
    --cancel-label="Cancelar" \
    --width=720 \
    --text="Desinstalar scripts do RDrive?\n\nSerão removidos:\n- Scripts em ~/.local/lib/rdrive/\n- Links em ~/.local/bin/\n- Autostart em ~/.config/autostart/\n\nO arquivo de configuração pode ser removido opcionalmente." >/dev/null 2>&1 || return 0

  local unmount_first="no"
  if [[ -x "$BIN_MOUNT" ]]; then
    if zenity --question \
      --title="Desmontar remotes" \
      --ok-label="Sim" \
      --cancel-label="Não" \
      --width=640 \
      --text="Desmontar todos os remotes antes de desinstalar?" >/dev/null 2>&1; then
      unmount_first="yes"
    fi
  fi

  local remove_conf="no"
  if [[ -f "$CONF_FILE" ]]; then
    if zenity --question \
      --title="Remover configuração" \
      --ok-label="Sim" \
      --cancel-label="Não" \
      --width=640 \
      --text="Remover também o arquivo de configuração?\n\n$CONF_FILE" >/dev/null 2>&1; then
      remove_conf="yes"
    fi
  fi

  local result=""

  if [[ "$unmount_first" == "yes" ]]; then
    result+="Desmontando remotes...\n"
    if command -v fusermount3 >/dev/null 2>&1; then
      config_load "$CONF_FILE" 2>/dev/null || true
      local i
      for i in "${!REMOTE_NAMES[@]}"; do
        local target="${MOUNT_BASE}/${REMOTE_MOUNT_SUBS[$i]}"
        if mountpoint -q "$target" 2>/dev/null; then
          fusermount3 -u "$target" 2>/dev/null && result+="  ✓ Desmontado: $target\n" || result+="  ✗ Falha: $target\n"
        fi
      done
    fi
    result+="\n"
  fi

  result+="Removendo scripts...\n"

  if [[ -d "${HOME}/.local/lib/rdrive" ]]; then
    rm -rf "${HOME}/.local/lib/rdrive" && result+="  ✓ ~/.local/lib/rdrive\n" || result+="  ✗ Falha ao remover ~/.local/lib/rdrive\n"
  fi

  if [[ -L "$BIN_MOUNT" ]]; then
    rm -f "$BIN_MOUNT" && result+="  ✓ $BIN_MOUNT\n" || result+="  ✗ Falha ao remover $BIN_MOUNT\n"
  fi
  if [[ -L "$BIN_REFRESH" ]]; then
    rm -f "$BIN_REFRESH" && result+="  ✓ $BIN_REFRESH\n" || result+="  ✗ Falha ao remover $BIN_REFRESH\n"
  fi
  if [[ -L "${HOME}/.local/bin/rdrive-umount.sh" ]]; then
    rm -f "${HOME}/.local/bin/rdrive-umount.sh" && result+="  ✓ ~/.local/bin/rdrive-umount.sh\n" || result+="  ✗ Falha\n"
  fi

  local autostart_file="${HOME}/.config/autostart/rdrive.desktop"
  if [[ -f "$autostart_file" ]]; then
    rm -f "$autostart_file" && result+="  ✓ $autostart_file\n" || result+="  ✗ Falha ao remover autostart\n"
  fi

  result+="\n"

  if [[ "$remove_conf" == "yes" ]]; then
    result+="Removendo configuração...\n"
    if [[ -f "$CONF_FILE" ]]; then
      rm -f "$CONF_FILE" && result+="  ✓ $CONF_FILE\n" || result+="  ✗ Falha ao remover $CONF_FILE\n"
    fi
    result+="\n"
  fi

  result+="Desinstalação concluída."

  zenity --info \
    --title="Desinstalação" \
    --width=680 \
    --text="$result" >/dev/null 2>&1 || true

  return 0
}

main_menu_loop() {
  while true; do
    config_load "$CONF_FILE" || true

    local refresh_label="Refresh de remote (OAuth)"
    local uninstall_label="Desinstalar scripts"
    if ! system_scripts_installed; then
      refresh_label="Refresh de remote (indisponível: instale scripts antes)"
      uninstall_label="Desinstalar scripts (indisponível: não instalado)"
    fi

    local action
    action="$(zenity --list \
      --title="Menu principal" \
      --ok-label="OK" \
      --cancel-label="Fechar" \
      --width=860 --height=440 \
      --text="Escolha uma ação:" \
      --column="Opção" \
      "Visualizar arquivo atual" \
      "Editar configurações" \
      "Instalar scripts" \
      "$refresh_label" \
      "$uninstall_label" 2>/dev/null)" || break

    case "$action" in
      "Visualizar arquivo atual")
        ui_show_config_file
        ;;
      "Editar configurações")
        edit_config_menu
        ;;
      "Instalar scripts")
        install_scripts_flow
        ;;
      "Refresh de remote (OAuth)")
        refresh_remote_flow
        ;;
      "Refresh de remote (indisponível: instale scripts antes)")
        ui_warning "Opção indisponível. Execute 'Instalar scripts' primeiro."
        ;;
      "Desinstalar scripts")
        uninstall_scripts_flow
        ;;
      "Desinstalar scripts (indisponível: não instalado)")
        ui_info "Scripts não estão instalados."
        ;;
    esac
  done
}

system_check_prerequisites() {
  command -v zenity >/dev/null 2>&1 || {
    echo "erro: zenity não encontrado." >&2
    exit 1
  }
  command -v realpath >/dev/null 2>&1 || {
    echo "erro: realpath não encontrado." >&2
    exit 1
  }
}

main() {
  system_check_prerequisites
  mkdir -p "$LOG_DIR"
  config_ensure_exists
  show_welcome_flow
  main_menu_loop
}

main "$@"

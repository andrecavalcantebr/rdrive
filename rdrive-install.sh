#!/usr/bin/env bash
set -euo pipefail

# rdrive-install.sh
# RDrive (remote drive) - installer + generator for Google Drive mounts using rclone
#
# What this script does:
# - Installs prerequisites (rclone, fuse3, python3) using apt
# - Reads ~/.config/rdrive/rdrive.conf as DATA (never sources it)
# - Generates ~/.config/rclone/rclone.conf (one [remote] section per REMOTE line)
# - Installs user scripts:
#     ~/.local/lib/rdrive/rdrive-mount.sh
#     ~/.local/lib/rdrive/rdrive-umount.sh
#     ~/.local/lib/rdrive/rdrive-refresh.sh
#   and symlinks them into:
#     ~/.local/bin/*.sh
# - Creates XDG autostart entry to mount all remotes on login
#
# rdrive.conf format:
#   KEY=VALUE
#   REMOTE "remote_rclone","root_folder_or_empty","mount_point_in_~/rdrive","path_to_credentials.json"
#
# Example:
#   MOUNT_BASE=~/rdrive
#   VFS_CACHE_MODE=full
#   REMOTE "UFAM","","ufam","~/.config/rdrive/cred-ufam.json"

CONF_DIR="${HOME}/.config/rdrive"
CONF_FILE="${CONF_DIR}/rdrive.conf"

RCLONE_DIR="${HOME}/.config/rclone"
RCLONE_CONF="${RCLONE_DIR}/rclone.conf"

LIB_DIR="${HOME}/.local/lib/rdrive"
BIN_DIR="${HOME}/.local/bin"

AUTOSTART_DIR="${HOME}/.config/autostart"
AUTOSTART_DESKTOP="${AUTOSTART_DIR}/rdrive-mount.desktop"

die() { echo "erro: $*" >&2; exit 1; }

trim() {
  local s="$1"
  s="${s#"${s%%[![:space:]]*}"}"
  s="${s%"${s##*[![:space:]]}"}"
  printf '%s' "$s"
}

path_expand() {
  local p="$1"
  p="$(trim "$p")"

  if [[ "$p" == \"*\" && "$p" == *\" ]]; then
    p="${p:1:${#p}-2}"
  elif [[ "$p" == \'*\' && "$p" == *\' ]]; then
    p="${p:1:${#p}-2}"
  fi

  p="$(trim "$p")"

  if [[ "$p" == "~" ]]; then
    printf '%s' "$HOME"
    return
  fi
  if [[ "$p" == "$HOME/~/"* ]]; then
    printf '%s' "${HOME}/${p#"$HOME/~/"}"
    return
  fi
  if [[ "$p" == "~/"* ]]; then
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

normalize_runtime_paths() {
  MOUNT_BASE="$(realpath -m "$(path_expand "$MOUNT_BASE")")"
  CACHE_DIR="$(realpath -m "$(path_expand "$CACHE_DIR")")"
  LOG_DIR="$(realpath -m "$(path_expand "$LOG_DIR")")"
}

sudo_run() {
  if sudo -n true >/dev/null 2>&1; then
    sudo "$@"
    return
  fi

  if [[ -n "${RDRIVE_SUDO_PASS:-}" ]]; then
    printf '%s\n' "$RDRIVE_SUDO_PASS" | sudo -S "$@"
    return
  fi

  if [[ ! -t 0 ]] && command -v zenity >/dev/null 2>&1; then
    local sudo_pass
    sudo_pass="$(zenity --password \
      --title="RDrive - senha administrativa" \
      --width=420 \
      --text="Digite a senha de administrador para concluir a instalação." 2>/dev/null)" || die "operação cancelada: senha administrativa não informada"
    printf '%s\n' "$sudo_pass" | sudo -S "$@"
    return
  fi

  sudo "$@"
}

# --------- Parser (DATA ONLY) ----------
load_rdrive_conf() {
  [[ -f "$CONF_FILE" ]] || die "config não encontrada: $CONF_FILE"

  # defaults (can be overridden by KEY=VALUE lines)
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

  REMOTE_NAMES=()
  REMOTE_ROOT_IDS=()
  REMOTE_MOUNT_SUBS=()
  REMOTE_CREDS=()

  local line key val
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%%#*}"
    line="${line#"${line%%[![:space:]]*}"}"
    line="${line%"${line##*[![:space:]]}"}"
    [[ -z "$line" ]] && continue

    # REMOTE "name","root","mount","creds"
    if [[ "$line" =~ ^REMOTE[[:space:]]+\"([^\"]+)\"[[:space:]]*,[[:space:]]*\"([^\"]*)\"[[:space:]]*,[[:space:]]*\"([^\"]+)\"[[:space:]]*,[[:space:]]*\"([^\"]+)\"[[:space:]]*$ ]]; then
      local cred_path
      cred_path="$(path_expand "${BASH_REMATCH[4]}")"
      if [[ "$cred_path" == "~/"* ]]; then
        cred_path="${HOME}/${cred_path#~/}"
      fi
      if [[ "$cred_path" == "$HOME/~/"* ]]; then
        cred_path="${HOME}/${cred_path#"$HOME/~/"}"
      fi

      REMOTE_NAMES+=("${BASH_REMATCH[1]}")
      REMOTE_ROOT_IDS+=("${BASH_REMATCH[2]}")
      REMOTE_MOUNT_SUBS+=("${BASH_REMATCH[3]}")
      REMOTE_CREDS+=("$(realpath -m "$cred_path")")
      continue
    fi

    # KEY=VALUE
    if [[ "$line" =~ ^[A-Za-z_][A-Za-z0-9_]*= ]]; then
      key="${line%%=*}"
      val="${line#*=}"
      key="$(trim "$key")"
      val="${val#"${val%%[![:space:]]*}"}"
      val="${val%"${val##*[![:space:]]}"}"
      printf -v "$key" '%s' "$val"
      continue
    fi

    die "linha inválida em $CONF_FILE: $line"
  done < "$CONF_FILE"

  normalize_runtime_paths

  [[ "${#REMOTE_NAMES[@]}" -gt 0 ]] || die "nenhum REMOTE definido em $CONF_FILE"
}

# --------- deps ----------
install_deps() {
  local need_update=0
  if ! command -v rclone >/dev/null 2>&1; then
    need_update=1
  fi
  if ! command -v fusermount3 >/dev/null 2>&1; then
    need_update=1
  fi
  if ! command -v python3 >/dev/null 2>&1; then
    need_update=1
  fi

  if [[ "$need_update" -eq 1 ]]; then
    echo "[1/4] instalando dependências (rclone, fuse3, python3)..."
    sudo_run apt-get update
    sudo_run apt-get install -y rclone fuse3 python3
  else
    echo "[1/4] dependências já instaladas."
  fi
}

ensure_fuse_allow_other() {
  local fuse_conf="/etc/fuse.conf"

  if [[ -f "$fuse_conf" ]] && grep -Eq '^[[:space:]]*user_allow_other[[:space:]]*$' "$fuse_conf"; then
    echo "ok: user_allow_other já habilitado em $fuse_conf"
    return 0
  fi

  echo "habilitando user_allow_other em $fuse_conf (necessário para --allow-other)..."
  sudo_run sh -c '
set -e
conf="/etc/fuse.conf"
touch "$conf"
if grep -Eq "^[[:space:]]*user_allow_other[[:space:]]*$" "$conf"; then
  exit 0
fi
if grep -Eq "^[[:space:]]*#[[:space:]]*user_allow_other[[:space:]]*$" "$conf"; then
  sed -i -E "s/^[[:space:]]*#[[:space:]]*user_allow_other[[:space:]]*$/user_allow_other/" "$conf"
else
  printf "\nuser_allow_other\n" >> "$conf"
fi
'

  echo "ok: user_allow_other habilitado"
}

# --------- extract oauth from Google credentials.json ----------
extract_oauth() {
  local cred_json="$1"
  [[ -f "$cred_json" ]] || die "credentials.json não encontrado: $cred_json"

  OAUTH_CLIENT_ID="$(python3 - <<PY
import json
p=r"${cred_json}"
j=json.load(open(p,"r"))
root=j.get("installed") or j.get("web") or {}
print(root.get("client_id",""))
PY
)"
  OAUTH_CLIENT_SECRET="$(python3 - <<PY
import json
p=r"${cred_json}"
j=json.load(open(p,"r"))
root=j.get("installed") or j.get("web") or {}
print(root.get("client_secret",""))
PY
)"
  [[ -n "$OAUTH_CLIENT_ID" ]] || die "não consegui extrair client_id de: $cred_json"
  [[ -n "$OAUTH_CLIENT_SECRET" ]] || die "não consegui extrair client_secret de: $cred_json"
}

# --------- generate rclone.conf ----------
write_rclone_conf() {
  echo "[2/4] gerando rclone.conf..."
  mkdir -p "$RCLONE_DIR"
  chmod 700 "$RCLONE_DIR"

  : > "$RCLONE_CONF"
  chmod 600 "$RCLONE_CONF"

  local i name root cred
  for i in "${!REMOTE_NAMES[@]}"; do
    name="${REMOTE_NAMES[$i]}"
    root="${REMOTE_ROOT_IDS[$i]}"
    cred="${REMOTE_CREDS[$i]}"

    extract_oauth "$cred"

    {
      echo "[$name]"
      echo "type = drive"
      echo "client_id = $OAUTH_CLIENT_ID"
      echo "client_secret = $OAUTH_CLIENT_SECRET"
      echo "scope = drive"
      if [[ -n "${EXPORT_FORMATS}" ]]; then
        echo "export_formats = ${EXPORT_FORMATS}"
      fi
      if [[ -n "$root" ]]; then
        echo "root_folder_id = $root"
      fi
      # token will be populated via: rclone config reconnect "<name>:"
      echo "team_drive ="
      echo ""
    } >> "$RCLONE_CONF"
  done

  echo "ok: $RCLONE_CONF"
}

# --------- write user scripts ----------
write_user_scripts() {
  echo "[3/4] instalando scripts rdrive..."
  mkdir -p "$LIB_DIR" "$BIN_DIR"

  # Common parser + helpers embedded into each script (no extra files)
  common_block='
die(){ echo "erro: $*" >&2; exit 1; }

trim(){
  local s="$1"
  s="${s#"${s%%[![:space:]]*}"}"
  s="${s%"${s##*[![:space:]]}"}"
  printf "%s" "$s"
}

path_expand(){
  local p="$1"
  p="$(trim "$p")"

  if [[ "$p" == \"*\" && "$p" == *\" ]]; then
    p="${p:1:${#p}-2}"
  fi

  p="$(trim "$p")"

  if [[ "$p" == "~" ]]; then
    printf "%s" "$HOME"
    return
  fi
  if [[ "$p" == "$HOME/~/"* ]]; then
    printf "%s" "${HOME}/${p#"$HOME/~/"}"
    return
  fi
  if [[ "$p" == "~/"* ]]; then
    printf "%s" "${HOME}/${p#~/}"
    return
  fi
  if [[ "$p" == "$HOME" ]]; then
    printf "%s" "$HOME"
    return
  fi
  if [[ "$p" == "$HOME"/* ]]; then
    printf "%s" "$p"
    return
  fi
  if [[ "$p" == "\$HOME" ]]; then
    printf "%s" "$HOME"
    return
  fi
  if [[ "$p" == "\$HOME/"* ]]; then
    printf "%s" "${HOME}/${p#\$HOME/}"
    return
  fi
  if [[ "$p" == "\${HOME}" ]]; then
    printf "%s" "$HOME"
    return
  fi
  if [[ "$p" == "\${HOME}/"* ]]; then
    printf "%s" "${HOME}/${p#\$\{HOME\}/}"
    return
  fi

  printf "%s" "$p"
}

normalize_runtime_paths(){
  MOUNT_BASE="$(realpath -m "$(path_expand "$MOUNT_BASE")")"
  CACHE_DIR="$(realpath -m "$(path_expand "$CACHE_DIR")")"
  LOG_DIR="$(realpath -m "$(path_expand "$LOG_DIR")")"
}

load_rdrive_conf() {
  [[ -f "$CONF_FILE" ]] || die "config não encontrada: $CONF_FILE"

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

  EXPORT_FORMATS=""

  REMOTE_NAMES=()
  REMOTE_ROOT_IDS=()
  REMOTE_MOUNT_SUBS=()
  REMOTE_CREDS=()

  local line key val
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%%#*}"
    line="${line#"${line%%[![:space:]]*}"}"
    line="${line%"${line##*[![:space:]]}"}"
    [[ -z "$line" ]] && continue

    if [[ "$line" =~ ^REMOTE[[:space:]]+\"([^\"]+)\"[[:space:]]*,[[:space:]]*\"([^\"]*)\"[[:space:]]*,[[:space:]]*\"([^\"]+)\"[[:space:]]*,[[:space:]]*\"([^\"]+)\"[[:space:]]*$ ]]; then
      local cred_path
      cred_path="$(path_expand "${BASH_REMATCH[4]}")"
      if [[ "$cred_path" == "~/"* ]]; then
        cred_path="${HOME}/${cred_path#~/}"
      fi
      if [[ "$cred_path" == "$HOME/~/"* ]]; then
        cred_path="${HOME}/${cred_path#"$HOME/~/"}"
      fi

      REMOTE_NAMES+=("${BASH_REMATCH[1]}")
      REMOTE_ROOT_IDS+=("${BASH_REMATCH[2]}")
      REMOTE_MOUNT_SUBS+=("${BASH_REMATCH[3]}")
      REMOTE_CREDS+=("$(realpath -m "$cred_path")")
      continue
    fi

    if [[ "$line" =~ ^[A-Za-z_][A-Za-z0-9_]*= ]]; then
      key="${line%%=*}"
      val="${line#*=}"
      key="$(trim "$key")"
      val="${val#"${val%%[![:space:]]*}"}"
      val="${val%"${val##*[![:space:]]}"}"
      printf -v "$key" "%s" "$val"
      continue
    fi

    die "linha inválida em $CONF_FILE: $line"
  done < "$CONF_FILE"

  normalize_runtime_paths

  [[ "${#REMOTE_NAMES[@]}" -gt 0 ]] || die "nenhum REMOTE definido em $CONF_FILE"
}

find_remote_index() {
  local key="${1,,}" i
  for i in "${!REMOTE_NAMES[@]}"; do
    [[ "${REMOTE_NAMES[$i],,}" == "$key" ]] && { echo "$i"; return 0; }
  done
  return 1
}
'

  # --- rdrive-mount.sh ---
  cat > "${LIB_DIR}/rdrive-mount.sh" <<EOS
#!/usr/bin/env bash
set -euo pipefail

CONF_FILE="\${HOME}/.config/rdrive/rdrive.conf"
${common_block}

usage() {
  cat <<'USG'
uso:
  rdrive-mount.sh -all
  rdrive-mount.sh <REMOTE>

exemplos:
  rdrive-mount.sh -all
  rdrive-mount.sh UFAM
USG
}

mount_one() {
  local idx="\$1"
  local name="\${REMOTE_NAMES[\$idx]}"
  local sub="\${REMOTE_MOUNT_SUBS[\$idx]}"

  local target="\${MOUNT_BASE}/\${sub}"
  mkdir -p "\$target" "\$CACHE_DIR" "\$LOG_DIR"

  if mountpoint -q "\$target"; then
    echo "já montado: \$name -> \$target"
    return 0
  fi

  local logfile="\${LOG_DIR}/rclone-\${name}.log"

  rclone mount "\${name}:" "\$target" \\
    --umask "\${UMASK}" \\
    --allow-other \\
    --vfs-cache-mode "\${VFS_CACHE_MODE}" \\
    --vfs-cache-max-size "\${VFS_CACHE_MAX_SIZE}" \\
    --vfs-cache-max-age "\${VFS_CACHE_MAX_AGE}" \\
    --buffer-size "\${BUFFER_SIZE}" \\
    --dir-cache-time "\${DIR_CACHE_TIME}" \\
    --poll-interval "\${POLL_INTERVAL}" \\
    --cache-dir "\$CACHE_DIR" \\
    --log-level INFO \\
    --log-file "\$logfile" \\
    --daemon

  echo "montado: \$name -> \$target"
}

main() {
  command -v rclone >/dev/null 2>&1 || die "rclone não instalado"
  load_rdrive_conf

  [[ \$# -ge 1 ]] || { usage; exit 1; }

  if [[ "\${1:-}" == "-all" ]]; then
    local i
    for i in "\${!REMOTE_NAMES[@]}"; do
      mount_one "\$i"
    done
    exit 0
  fi

  local idx
  idx="\$(find_remote_index "\$1")" || die "remote não encontrado: \$1"
  mount_one "\$idx"
}

main "\$@"
EOS

  # --- rdrive-umount.sh ---
  cat > "${LIB_DIR}/rdrive-umount.sh" <<EOS
#!/usr/bin/env bash
set -euo pipefail

CONF_FILE="\${HOME}/.config/rdrive/rdrive.conf"
${common_block}

usage() {
  cat <<'USG'
uso:
  rdrive-umount.sh -all
  rdrive-umount.sh <REMOTE>

exemplos:
  rdrive-umount.sh -all
  rdrive-umount.sh UFAM
USG
}

umount_target() {
  local target="\$1"
  if mountpoint -q "\$target"; then
    fusermount3 -u "\$target" && echo "desmontado: \$target"
  else
    echo "não está montado: \$target"
  fi
}

main() {
  command -v fusermount3 >/dev/null 2>&1 || die "fusermount3 não encontrado (instale fuse3)"
  load_rdrive_conf

  [[ \$# -ge 1 ]] || { usage; exit 1; }

  if [[ "\${1:-}" == "-all" ]]; then
    local i
    for i in "\${!REMOTE_NAMES[@]}"; do
      umount_target "\${MOUNT_BASE}/\${REMOTE_MOUNT_SUBS[\$i]}"
    done
    exit 0
  fi

  local idx
  idx="\$(find_remote_index "\$1")" || die "remote não encontrado: \$1"
  umount_target "\${MOUNT_BASE}/\${REMOTE_MOUNT_SUBS[\$idx]}"
}

main "\$@"
EOS

  # --- rdrive-refresh.sh ---
  cat > "${LIB_DIR}/rdrive-refresh.sh" <<EOS
#!/usr/bin/env bash
set -euo pipefail

CONF_FILE="\${HOME}/.config/rdrive/rdrive.conf"
${common_block}

usage() {
  cat <<'USG'
uso:
  rdrive-refresh.sh -all
  rdrive-refresh.sh <REMOTE>

faz:
  reautoriza o token OAuth via:
    rclone config reconnect "<REMOTE>:"

recomendado:
  rdrive-umount.sh -all
  rdrive-refresh.sh -all
  rdrive-mount.sh -all
USG
}

refresh_one() {
  local idx="\$1"
  local name="\${REMOTE_NAMES[\$idx]}"
  echo "==> reautorizando: \$name"
  rclone config reconnect "\${name}:"
  echo
}

main() {
  command -v rclone >/dev/null 2>&1 || die "rclone não instalado"
  load_rdrive_conf

  [[ \$# -ge 1 ]] || { usage; exit 1; }

  if [[ "\${1:-}" == "-all" ]]; then
    local i
    for i in "\${!REMOTE_NAMES[@]}"; do
      refresh_one "\$i"
    done
    exit 0
  fi

  local idx
  idx="\$(find_remote_index "\$1")" || die "remote não encontrado: \$1"
  refresh_one "\$idx"
}

main "\$@"
EOS

  chmod +x "${LIB_DIR}/rdrive-mount.sh" "${LIB_DIR}/rdrive-umount.sh" "${LIB_DIR}/rdrive-refresh.sh"

  ln -sf "${LIB_DIR}/rdrive-mount.sh"   "${BIN_DIR}/rdrive-mount.sh"
  ln -sf "${LIB_DIR}/rdrive-umount.sh"  "${BIN_DIR}/rdrive-umount.sh"
  ln -sf "${LIB_DIR}/rdrive-refresh.sh" "${BIN_DIR}/rdrive-refresh.sh"

  echo "ok: scripts em ${LIB_DIR} e links em ${BIN_DIR}"
}

# --------- create/update XDG autostart ----------
install_autostart() {
  echo "[4/4] configurando autostart (xdg)..."
  mkdir -p "$AUTOSTART_DIR"

  # Ensure ~/.local/bin is in PATH for desktop sessions, but call absolute path anyway.
  cat > "$AUTOSTART_DESKTOP" <<EOF
[Desktop Entry]
Type=Application
Version=1.0
Name=RDrive Mount
Comment=Mount RDrive remotes at login
Exec=${BIN_DIR}/rdrive-mount.sh -all
Terminal=false
X-GNOME-Autostart-enabled=true
EOF

  echo "ok: $AUTOSTART_DESKTOP"
}

# --------- create example config if missing ----------
maybe_create_example_conf() {
  mkdir -p "$CONF_DIR"
  if [[ ! -f "$CONF_FILE" ]]; then
    cat > "$CONF_FILE" <<'EOF'
# rdrive.conf (exemplo)
# Linhas KEY=VALUE são globais (opcionais).
# Linhas REMOTE são obrigatórias e definem:
#   REMOTE "remote_rclone","root_folder_or_empty","mount_point_in_~/rdrive","path_to_credentials.json"

MOUNT_BASE=~/rdrive
CACHE_DIR=~/.cache/rdrive-rclone
LOG_DIR=~/.cache/rdrive-logs

VFS_CACHE_MODE=full
VFS_CACHE_MAX_SIZE=2G
VFS_CACHE_MAX_AGE=72h
BUFFER_SIZE=64M
DIR_CACHE_TIME=72h
POLL_INTERVAL=1m
UMASK=002

# Exemplos (ajuste paths e nomes):
REMOTE "UFAM","","ufam","~/.config/rdrive/credentials-ufam.json"
REMOTE "Super","","super","~/.config/rdrive/credentials-super.json"
REMOTE "EspacoLam","","espacolam","~/.config/rdrive/credentials-lam.json"
EOF
    chmod 600 "$CONF_FILE"
    echo "criado: $CONF_FILE"
  fi
}

print_next_steps() {
  cat <<TXT

Pronto.

1) Edite:
   $CONF_FILE

2) Baixe os OAuth client JSON (Google Cloud) e coloque nos paths indicados em cada linha REMOTE:
   Ex.: ~/.config/rdrive/credentials-ufam.json

3) Gere tokens (primeira vez e quando expirar):
   rdrive-refresh.sh -all

4) Monte:
   rdrive-mount.sh -all

5) Desmonte:
   rdrive-umount.sh -all

Autostart XDG configurado em:
  $AUTOSTART_DESKTOP

TXT
}

main() {
  maybe_create_example_conf
  load_rdrive_conf
  install_deps
  ensure_fuse_allow_other
  write_rclone_conf
  write_user_scripts
  install_autostart
  print_next_steps
}

main "$@"

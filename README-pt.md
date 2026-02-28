# RDrive — Remote Drive para Linux

RDrive é uma ferramenta em shell script para montar remotes na nuvem (como Google Drive) em diretórios locais do Linux usando rclone.

## Visão geral

- Funciona em distribuições Linux modernas
- Compatível com desktops XDG (XFCE, KDE, GNOME e similares)
- Configuração declarativa baseada em arquivo (`rdrive.conf`)
- Suporte a múltiplos remotes
- Autorização OAuth manual por remote
- Inicialização automática via XDG Autostart

## Requisitos

- Linux
- `bash`
- `rclone`
- `zenity` (GUI)
- FUSE (`fusermount` ou `fusermount3`)
- `python3` (extração de metadados de credenciais no instalador)

> Nota: neste estágio, a instalação automática de dependências é implementada com `apt`.

## Instalação

```bash
chmod +x rdrive-install.sh
./rdrive-install.sh
```

O instalador:

1. Verifica/instala dependências
2. Garante a existência de `~/.config/rdrive/rdrive.conf`
3. Gera `~/.config/rclone/rclone.conf`
4. Instala scripts auxiliares em `~/.local/lib/rdrive`
5. Cria links em `~/.local/bin`
6. Configura autostart em `~/.config/autostart`

## GUI de configuração

```bash
chmod +x rdrive-gui.sh
./rdrive-gui.sh
```

Fluxo atual da GUI:

1. Boas-vindas e escolha inicial (carregar config atual ou resetar para padrão)
2. Menu principal:
   - Visualizar arquivo atual
   - Editar configurações
   - Instalar scripts
   - Refresh de remote (OAuth) — autorização por remote com orientação de perfil de navegador
   - Desinstalar scripts — com remoção opcional de config e desmontagem
3. Menu de configurações:
   - Variáveis globais
   - Remotes (CRUD em loop)
   - Reverter alterações do menu de edição atual
4. Instalação de scripts executada em terminal interativo (saída visível)
5. Refresh OAuth executado em terminal interativo (abre navegador por remote)

### Regras de caminhos na GUI

- `MOUNT_BASE` é normalizado para um caminho absoluto em runtime
- Pasta de montagem do remote é tratada como string de subcaminho dentro de `MOUNT_BASE`
- Caminho de credencial é tratado como absoluto
- Arquivo de credencial deve existir e ser legível

## `--allow-other` (FUSE)

A montagem usa `--allow-other` por design (por exemplo, para permitir que aplicações como navegadores salvem diretamente em pastas montadas).

O instalador garante que `user_allow_other` esteja habilitado em `/etc/fuse.conf`.

## Layout de diretórios

```text
~/.config/
 ├─ rdrive/
 │   └─ rdrive.conf
 ├─ rclone/
 │   └─ rclone.conf
 └─ autostart/
     └─ rdrive-mount.desktop

~/.cache/
 ├─ rdrive-rclone/
 └─ rdrive-logs/

~/.local/
 ├─ lib/
 │   └─ rdrive/
 │       ├─ rdrive-mount.sh
 │       ├─ rdrive-umount.sh
 │       └─ rdrive-refresh.sh
 └─ bin/
     ├─ rdrive-mount.sh
     ├─ rdrive-umount.sh
     └─ rdrive-refresh.sh
```

## Formato de `rdrive.conf`

Arquivo principal:

```text
~/.config/rdrive/rdrive.conf
```

Variáveis globais (`KEY=VALUE`) e remotes:

```ini
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

REMOTE "UFAM","","UFAM","/home/user/.Private/credentials-ufam.json"
```

Se `~/.config/rdrive/rdrive.conf` não existir, o instalador cria um template padrão embutido.

Formato REMOTE:

```ini
REMOTE "remote_rclone","root_folder_or_empty","mount_subdir","path_to_credentials.json"
```

## Uso

Autorizar/atualizar OAuth:

```bash
rdrive-refresh.sh -all
# ou
rdrive-refresh.sh <REMOTE>
```

Montar:

```bash
rdrive-mount.sh -all
# ou
rdrive-mount.sh <REMOTE>
```

Desmontar:

```bash
rdrive-umount.sh -all
```

## Desinstalação

Use a GUI para desinstalar:

```bash
./rdrive-gui.sh
```

Selecione "Desinstalar scripts" no menu principal. O fluxo:

1. Prompt de confirmação
2. Opcional: desmontar todos os remotes antes de desinstalar
3. Opcional: remover arquivo de configuração (`~/.config/rdrive/rdrive.conf`)
4. Remoção de:
   - `~/.local/lib/rdrive/`
   - `~/.local/bin/rdrive-*.sh` (links simbólicos)
   - `~/.config/autostart/rdrive.desktop`

Desinstalação manual:

```bash
fusermount3 -u ~/rdrive/*  # desmontar tudo
rm -rf ~/.local/lib/rdrive
rm -f ~/.local/bin/rdrive-*.sh
rm -f ~/.config/autostart/rdrive.desktop
rm -f ~/.config/rdrive/rdrive.conf  # opcional
```

## Licença

Veja `LICENSE.md`.

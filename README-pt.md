# RDrive — Remote Drive para Linux

RDrive é uma ferramenta em shell script para montar remotes (como Google Drive) em diretórios locais no Linux usando rclone.

## Visão geral

- Funciona em distribuições Linux modernas
- Compatível com desktops XDG (XFCE, KDE, GNOME e similares)
- Configuração declarativa em arquivo (`rdrive.conf`)
- Suporte a múltiplos remotes
- Autorização OAuth manual por remote
- Inicialização automática via XDG Autostart

## Requisitos

- Linux
- `bash`
- `rclone`
- `zenity` (GUI)
- FUSE (`fusermount` ou `fusermount3`)
- `python3` (extração de dados de credenciais no instalador)

> Observação: neste momento o instalador automático de dependências usa `apt`.

## Instalação

```bash
chmod +x rdrive-install.sh
./rdrive-install.sh
```

O instalador:

1. Verifica/instala dependências
2. Garante `~/.config/rdrive/rdrive.conf`
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

1. Boas-vindas e escolha inicial (carregar configuração atual ou resetar configuração padrão)
2. Menu principal:
   - Visualizar arquivo atual
   - Editar configurações
   - Instalar scripts
   - Instalar remotes
3. Edição de configurações:
   - Variáveis globais
   - Remotes
   - Reverter alterações do menu de edição
4. Instalação de scripts com exibição de log ao final
5. Autorização de remote selecionado com orientação de perfil do navegador

### Regras de caminho na GUI

- `MOUNT_BASE` é normalizado para caminho absoluto no runtime
- Pasta de montagem do remote é tratada como string (subcaminho dentro de `MOUNT_BASE`)
- Credencial é tratada como caminho absoluto
- O arquivo de credencial deve existir e ser legível

## `--allow-other` (FUSE)

O mount usa `--allow-other` por necessidade funcional (por exemplo, permitir que aplicações como o navegador salvem diretamente nas pastas montadas).

O instalador garante `user_allow_other` em `/etc/fuse.conf`.

## Estrutura de diretórios

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

## Formato do rdrive.conf

Arquivo:

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

Se `~/.config/rdrive/rdrive.conf` não existir, o instalador cria um modelo padrão embutido.

Formato REMOTE:

```ini
REMOTE "remote_rclone","root_folder_or_empty","mount_subdir","path_to_credentials.json"
```

## Uso

Autorizar/renovar OAuth:

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

## Licença

Consulte `LICENSE.md`.

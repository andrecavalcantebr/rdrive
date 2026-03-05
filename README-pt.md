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
- `yad` (GUI)
- `jq`
- FUSE (`fusermount` ou `fusermount3`)
- `python3` (extração de metadados de credenciais)

## Instalação

Você pode instalar o RDrive de forma global para o seu usuário rodando o script de instalação pelo Tarball da Release do GitHub:

```bash
wget -qO- https://github.com/andrecavalcantebr/rdrive/archive/refs/tags/vX.Y.tar.gz | tar xz -C /tmp && /tmp/rdrive/install.sh
```

Ou, caso tenha clonado o repositório localmente:

```bash
./install.sh --install
```

O instalador:

1. Verifica dependências (usando `apt-get` ou `dnf` se necessário).
2. Copia os binários (`rdrive`, `rdrive-gui`) para `~/.local/bin/`.
3. Copia assets de atalho (`rdrive.desktop`, icons) para suas pastas XDG (`~/.local/share/applications`, `~/.local/share/icons`).
4. Atualiza o banco de dados do desktop environment.

## Geração do Setup

Primeiro inicie o motor via linha de comando para gerar as ferramentas auxiliares:

```bash
rdrive
```

Ele irá:
1. Garantir a existência de `~/.config/rdrive/rdrive.conf`.
2. Gerar o `~/.config/rclone/rclone.conf`.
3. Instalar scripts auxiliares em `~/.local/lib/rdrive`.
4. Criar links executáveis em `~/.local/bin` (`rdrive-mount.sh`, etc.).
5. Configurar o autostart em `~/.config/autostart`.

## GUI de configuração

Inicie pelo menu de aplicativos ou pelo terminal com o comando:

```bash
rdrive-gui
```

Fluxo atual da GUI:

1. Boas-vindas e escolha inicial (carregar config atual ou resetar para padrão)
2. Menu principal:
   - Visualizar arquivo atual
   - Editar configurações
   - Instalar scripts (reexecuta o `rdrive`)
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
Durante a primeira execução o script `rdrive` pode requerer permissão para garantir que `user_allow_other` esteja habilitado em `/etc/fuse.conf`.

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
 ├─ share/
 │   ├─ applications/
 │   │   └─ rdrive.desktop
 │   └─ icons/hicolor/scalable/apps/
 │       └─ rdrive-gui-icon.svg
 ├─ lib/
 │   └─ rdrive/
 │       ├─ rdrive-mount.sh
 │       ├─ rdrive-umount.sh
 │       └─ rdrive-refresh.sh
 └─ bin/
     ├─ rdrive
     ├─ rdrive-gui
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

Se `~/.config/rdrive/rdrive.conf` não existir, o motor `rdrive` cria um template padrão embutido.

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

Realize a limpeza no nível do pacote desinstalando pelo terminal:

```bash
./install.sh --uninstall
```

Para remover configurações e scripts gerados, você pode usar a interface yad:

```bash
rdrive-gui
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
./install.sh --uninstall   # apaga wrappers rdrive e rdrive-gui
rm -rf ~/.local/lib/rdrive
rm -f ~/.local/bin/rdrive-*.sh
rm -f ~/.config/autostart/rdrive.desktop
rm -f ~/.config/rdrive/rdrive.conf  # opcional
```

## Licença

Veja `LICENSE.md`.

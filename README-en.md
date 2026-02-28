# RDrive — Remote Drive for Linux

RDrive is a shell-script tool to mount cloud remotes (such as Google Drive) into local Linux directories using rclone.

## Overview

- Works on modern Linux distributions
- Compatible with XDG desktops (XFCE, KDE, GNOME, and similar)
- Declarative file-based configuration (`rdrive.conf`)
- Multiple remotes support
- Manual per-remote OAuth authorization
- Automatic startup via XDG Autostart

## Requirements

- Linux
- `bash`
- `rclone`
- `zenity` (GUI)
- FUSE (`fusermount` or `fusermount3`)
- `python3` (credentials metadata extraction in installer)

> Note: at this stage, automatic dependency installation is implemented with `apt`.

## Installation

```bash
chmod +x rdrive-install.sh
./rdrive-install.sh
```

The installer:

1. Checks/installs dependencies
2. Ensures `~/.config/rdrive/rdrive.conf`
3. Generates `~/.config/rclone/rclone.conf`
4. Installs helper scripts in `~/.local/lib/rdrive`
5. Creates links in `~/.local/bin`
6. Configures autostart in `~/.config/autostart`

## Configuration GUI

```bash
chmod +x rdrive-gui.sh
./rdrive-gui.sh
```

Current GUI flow:

1. Welcome and startup choice (load current config or reset to default config)
2. Main menu:
   - View current file
   - Edit settings
   - Install scripts
   - Install remotes
3. Settings menu:
   - Global variables
   - Remotes
   - Revert changes from the current edit menu
4. Script installation with log view at the end
5. Selected remote authorization with browser-profile guidance

### Path rules in GUI

- `MOUNT_BASE` is normalized to an absolute runtime path
- Remote mount folder is treated as a plain subpath string inside `MOUNT_BASE`
- Credential path is handled as absolute
- Credential file must exist and be readable

## `--allow-other` (FUSE)

Mount uses `--allow-other` by design (for example, to allow applications such as browsers to save directly into mounted folders).

The installer ensures `user_allow_other` is enabled in `/etc/fuse.conf`.

## Directory layout

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

## `rdrive.conf` format

Main file:

```text
~/.config/rdrive/rdrive.conf
```

Global variables (`KEY=VALUE`) and remotes:

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

If `~/.config/rdrive/rdrive.conf` does not exist, the installer creates an embedded default template.

REMOTE format:

```ini
REMOTE "remote_rclone","root_folder_or_empty","mount_subdir","path_to_credentials.json"
```

## Usage

Authorize/refresh OAuth:

```bash
rdrive-refresh.sh -all
# or
rdrive-refresh.sh <REMOTE>
```

Mount:

```bash
rdrive-mount.sh -all
# or
rdrive-mount.sh <REMOTE>
```

Unmount:

```bash
rdrive-umount.sh -all
```

## License

See `LICENSE.md`.

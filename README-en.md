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
- `yad` (GUI)
- `jq`
- FUSE (`fusermount` or `fusermount3`)
- `python3` (credentials metadata extraction)

## Installation

You can install RDrive globally for your user by running the install script from the GitHub release tarball:

```bash
wget -qO- https://github.com/andrecavalcantebr/rdrive/archive/refs/tags/vX.Y.tar.gz | tar xz -C /tmp && /tmp/rdrive/install.sh
```

Or, if you cloned the repository locally:

```bash
./install.sh --install
```

The installer:

1. Checks for dependencies (using `apt-get` or `dnf` if required).
2. Copies executables (`rdrive`, `rdrive-gui`) to `~/.local/bin/`.
3. Copies desktop assets (`rdrive.desktop`, icons) to XDG directories (`~/.local/share/applications`, `~/.local/share/icons`).
4. Updates the desktop environment database.

## Generating the setup

First, trigger the engine tool to generate the configuration files:

```bash
rdrive
```

It:
1. Ensures `~/.config/rdrive/rdrive.conf` exists.
2. Generates `~/.config/rclone/rclone.conf`.
3. Installs helper scripts in `~/.local/lib/rdrive`.
4. Creates executable links in `~/.local/bin` (`rdrive-mount.sh`, etc.).
5. Configures autostart in `~/.config/autostart`.

## Configuration GUI

Launch the GUI from your application menu or the terminal:

```bash
rdrive-gui
```

Current GUI flow:

1. Welcome and startup choice (load current config or reset to default config)
2. Main menu:
   - View current file
   - Edit settings
   - Install scripts (re-runs `rdrive`)
   - Refresh remote (OAuth) — per-remote authorization with browser-profile guidance
   - Uninstall scripts — with optional config removal and unmount
3. Settings menu:
   - Global variables
   - Remotes (CRUD with loop)
   - Revert changes from the current edit menu
4. Script installation runs in an interactive terminal (visible output)
5. OAuth refresh runs in an interactive terminal (opens browser per remote)

### Path rules in GUI

- `MOUNT_BASE` is normalized to an absolute runtime path
- Remote mount folder is treated as a plain subpath string inside `MOUNT_BASE`
- Credential path is handled as absolute
- Credential file must exist and be readable

## `--allow-other` (FUSE)

Mount uses `--allow-other` by design (for example, to allow applications such as browsers to save directly into mounted folders).

If triggered during initial `rdrive` execution, the system may prompt for sudo to ensure `user_allow_other` is enabled in `/etc/fuse.conf`.

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

If `~/.config/rdrive/rdrive.conf` does not exist, the `rdrive` engine creates an embedded default template.

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

## Uninstallation

Use the package level uninstall to clear root binaries and icons:

```bash
./install.sh --uninstall
```

To remove configuration and generated script logic, you can use the Yad GUI:

```bash
rdrive-gui
```

Select "Uninstall scripts". The flow:

1. Confirmation prompt
2. Optional: unmount all remotes before uninstalling
3. Optional: remove configuration file (`~/.config/rdrive/rdrive.conf`)
4. Removal of:
   - `~/.local/lib/rdrive/`
   - `~/.local/bin/rdrive-*.sh` (symlinks)
   - `~/.config/autostart/rdrive.desktop`

Manual uninstall:

```bash
fusermount3 -u ~/rdrive/*  # unmount all
./install.sh --uninstall   # remove rdrive and rdrive-gui wrappers
rm -rf ~/.local/lib/rdrive
rm -f ~/.local/bin/rdrive-*.sh
rm -f ~/.config/autostart/rdrive.desktop
rm -f ~/.config/rdrive/rdrive.conf  # optional
```

## License

See `LICENSE.md`.

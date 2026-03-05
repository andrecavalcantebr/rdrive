#!/usr/bin/env bash

# RDrive - Installer Script (Baseado em Release/Tarball)
#
# Uso:
# wget -qO- https://github.com/andrecavalcantebr/rdrive/archive/refs/tags/vX.Y.tar.gz | tar xz -C /tmp && sudo /tmp/rdrive/install.sh

set -e

# ==========================================
# 1. VALIDAÇÃO DE USUÁRIO
# ==========================================
if [ "$EUID" -eq 0 ]; then
    echo "❌ Erro: Não execute como root! O RDrive é instalado a nível de usuário ($HOME)."
    exit 1
fi

# Função para rodar com sudo sem sair do script do usuário
sudo_run() {
    # Tenta rodar sem senha se possível
    if sudo -n true >/dev/null 2>&1; then
        sudo "$@"
        return
    fi
    # Senão, se temos zenity (o que provavelmente temos) pedimos senha visual
    if command -v zenity >/dev/null; then
        local pass
        pass="$(yad --entry --hide-text --title --title="Autorização Necessária" --text="Digite sua senha sudo para instalar dependências (rclone/fuse3/etc)")" || exit 1
        echo "$pass" | sudo -S -p "" "$@"
    else
        sudo "$@"
    fi
}

# ==========================================
# 2. DIRETÓRIOS DE DESTINO (Nível do Usuário)
# ==========================================
BIN_DIR="$HOME/.local/bin"
DESKTOP_DIR="$HOME/.local/share/applications"
ICONS_DIR="$HOME/.local/share/icons/hicolor/scalable/apps"

# ==========================================
# 2.1 TRATAMENTO DE ARGUMENTOS
# ==========================================
if [[ "$#" -gt 0 ]]; then
    if [[ "$1" == "--uninstall" || "$1" == "uninstall" ]]; then
        echo "🗑️ Iniciando desinstalação..."
        
        # Mata o processo se estiver rodando
        pkill -f "rdrive-gui.sh" || true
        
        # Remove atalhos
        rm -f "$DESKTOP_DIR/rdrive.desktop"
        
        # Remove binários
        rm -f "$BIN_DIR/rdrive"
        rm -f "$BIN_DIR/rdrive-gui"
        
        rm -f "$ICONS_DIR/rdrive-gui-icon.svg"
        
        # Atualiza DB Desktop
        update-desktop-database "$DESKTOP_DIR" || true
        gtk-update-icon-cache -f "$HOME/.local/share/icons/hicolor" || true

        echo "✅ Desinstalação concluída!"
        exit 0
    elif [[ "$1" == "--install" || "$1" == "install" ]]; then
        # Prossegue com a instalação normal
        shift
    else
        echo "❌ Argumento não reconhecido: $1"
        echo "Uso: $0 [--install | --uninstall]"
        exit 1
    fi
fi

echo "🚀 Iniciando instalação do RDrive para o usuário $USER..."

# Resolvemos o diretório base (onde o instalador está rodando)
SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"

# Garantir que diretórios existam
mkdir -p "$BIN_DIR" "$DESKTOP_DIR" "$ICONS_DIR"

# ==========================================
# 3. VERIFICAÇÃO DE DEPENDÊNCIAS
# ==========================================
echo "📦 Verificando dependências do sistema..."

MISSING_DEPS=()
# Mapeamento <nome do comando> -> <nome do pacote>
command -v rclone >/dev/null 2>&1 || MISSING_DEPS+=("rclone")
command -v fusermount3 >/dev/null 2>&1 || MISSING_DEPS+=("fuse3")
command -v yad >/dev/null 2>&1 || MISSING_DEPS+=("yad")
command -v jq >/dev/null 2>&1 || MISSING_DEPS+=("jq")

if [ ${#MISSING_DEPS[@]} -gt 0 ]; then
    echo "⚠️ Dependências ausentes encontradas: ${MISSING_DEPS[*]}"
    echo "Instalando..."
    
    if command -v apt-get >/dev/null 2>&1; then
        sudo_run apt-get update -qq
        sudo_run apt-get install -y -qq "${MISSING_DEPS[@]}"
    elif command -v dnf >/dev/null 2>&1; then
        sudo_run dnf install -y -q "${MISSING_DEPS[@]}"
    else
        echo "❌ Gerenciador de pacotes não suportado. Por favor, instale manualmente: ${MISSING_DEPS[*]}"
        exit 1
    fi
else
    echo "✅ Todas as dependências (rclone, fuse3, yad, jq) já estão instaladas!"
fi

# ==========================================
# 4. INSTALAÇÃO DOS ARQUIVOS (Cópia e Permissões)
# ==========================================
echo "⚙️  Instalando executáveis (rdrive, rdrive-gui)..."
cp "$SRC_DIR/src/rdrive.sh" "$BIN_DIR/rdrive"
cp "$SRC_DIR/src/rdrive-gui.sh" "$BIN_DIR/rdrive-gui"
chmod +x "$BIN_DIR/rdrive" "$BIN_DIR/rdrive-gui"

echo "🖼️  Instalando atalhos e ícones..."
if [ -f "$SRC_DIR/assets/rdrive-gui-icon.svg" ]; then
    cp "$SRC_DIR/assets/rdrive-gui-icon.svg" "$ICONS_DIR/"
    chmod 644 "$ICONS_DIR/rdrive-gui-icon.svg"
    
    # Atualiza cache de ícones (GNOME/GTK/KDE)
    if command -v gtk-update-icon-cache >/dev/null 2>&1; then
        gtk-update-icon-cache -f -t "$HOME/.local/share/icons/hicolor" >/dev/null 2>&1 || true
    fi
fi

if [ -f "$SRC_DIR/assets/rdrive.desktop" ]; then
    cp "$SRC_DIR/assets/rdrive.desktop" "$DESKTOP_DIR/"
    chmod 644 "$DESKTOP_DIR/rdrive.desktop"
    
    # Atualiza o banco de dados de aplicativos do ambiente de trabalho (GNOME/KDE)
    if command -v update-desktop-database >/dev/null 2>&1; then
        update-desktop-database "$DESKTOP_DIR" >/dev/null 2>&1 || true
    fi
fi

# ==========================================
# 5. FINALIZAÇÃO
# ==========================================
echo "✅ Instalação concluída com sucesso!"
echo "--------------------------------------------------------"
echo "O RDrive foi instalado. Você já pode usar os comandos:"
echo "  rdrive      -> Utilitário de linha de comando (CLI)"
echo "  rdrive-gui  -> Assistente gráfico (disponível no menu de apps)"
echo ""
echo "Recomendamos que você abra pelo seu Menu de Aplicativos ou rode:"
echo "  rdrive-gui"
echo "--------------------------------------------------------"

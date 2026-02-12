#!/bin/bash

# Останавливаем скрипт при любой ошибке
set -e

# Цвета для вывода
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() { echo -e "${BLUE}=== $1 ===${NC}"; }
log_step() { echo -e "${GREEN}>>> $1${NC}"; }
log_warn() { echo -e "${YELLOW}[WARN] $1${NC}"; }
log_error() { echo -e "${RED}[ERROR] $1${NC}"; }

# Функция для идемпотентного добавления строк в файлы
append_if_missing() {
    local file="$1"
    local line="$2"
    if [ -f "$file" ]; then
        if ! grep -qF "$line" "$file"; then
            echo "$line" >> "$file"
        fi
    else
        echo "$line" >> "$file"
    fi
}

log_info "Запуск полной настройки VPS (Zsh + Tmux + Nvim + Security)"

# 1. ОБНОВЛЕНИЕ И БАЗОВЫЕ УТИЛИТЫ
log_step "[1/6] Обновление системы и установка зависимостей..."
sudo apt update && sudo apt upgrade -y
sudo apt install -y curl git wget unzip ufw fail2ban build-essential htop tar zsh software-properties-common

# 2. УСТАНОВКА MODERN TOOLS (Ripgrep, Bat, FZF)
log_step "[2/6] Установка современных утилит..."

# Ripgrep & FD
sudo apt install -y ripgrep fd-find

# На Ubuntu fd устанавливается как fdfind, делаем симлинк если его нет
if ! command -v fd &> /dev/null; then
    if command -v fdfind &> /dev/null; then
        sudo ln -sf $(which fdfind) /usr/local/bin/fd
    fi
fi

# Bat (cat с подсветкой)
sudo apt install -y bat
if ! command -v bat &> /dev/null; then
    if command -v batcat &> /dev/null; then
        mkdir -p ~/.local/bin
        ln -sf /usr/bin/batcat ~/.local/bin/bat
    fi
fi

# FZF (Fuzzy Finder)
if [ ! -d "$HOME/.fzf" ]; then
    git clone --depth 1 https://github.com/junegunn/fzf.git ~/.fzf
    ~/.fzf/install --all
else
    log_warn "FZF уже установлен, обновляем..."
    cd ~/.fzf && git pull && ./install --all
fi

# 3. УСТАНОВКА ZSH & OH-MY-ZSH
log_step "[3/6] Настройка Zsh и Oh-My-Zsh..."

# Установка OMZ (если нет)
if [ ! -d "$HOME/.oh-my-zsh" ]; then
    sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
else
    log_warn "Oh-My-Zsh уже установлен."
fi

# Плагины Zsh
ZSH_CUSTOM=${ZSH_CUSTOM:-~/.oh-my-zsh/custom}
mkdir -p "$ZSH_CUSTOM/plugins"

install_zsh_plugin() {
    local repo_url=$1
    local plugin_dir=$2
    if [ ! -d "$plugin_dir" ]; then
        git clone "$repo_url" "$plugin_dir"
    else
        log_warn "Плагин $(basename "$plugin_dir") уже существует, пропускаем клон."
    fi
}

install_zsh_plugin "https://github.com/zsh-users/zsh-autosuggestions" "${ZSH_CUSTOM}/plugins/zsh-autosuggestions"
install_zsh_plugin "https://github.com/zsh-users/zsh-syntax-highlighting.git" "${ZSH_CUSTOM}/plugins/zsh-syntax-highlighting"
install_zsh_plugin "https://github.com/agkozak/zsh-z" "${ZSH_CUSTOM}/plugins/zsh-z"

# Настройка .zshrc
sed -i 's/plugins=(git)/plugins=(git zsh-autosuggestions zsh-syntax-highlighting zsh-z)/' ~/.zshrc

append_if_missing ~/.zshrc 'export PATH="$HOME/.local/bin:/usr/local/bin:$PATH"'
append_if_missing ~/.zshrc 'alias vim="nvim"'
append_if_missing ~/.zshrc 'alias v="nvim"'
append_if_missing ~/.zshrc 'alias cat="bat"'

# Смена шелла на zsh
if [ "$SHELL" != "$(which zsh)" ]; then
    sudo chsh -s $(which zsh) $USER
fi

# 4. НАСТРОЙКА TMUX (TPM + Resurrect + Continuum)
log_step "[4/6] Настройка Tmux..."
sudo apt install -y tmux

# Установка TPM
if [ ! -d "$HOME/.tmux/plugins/tpm" ]; then
    git clone https://github.com/tmux-plugins/tpm ~/.tmux/plugins/tpm
fi

# Конфиг Tmux
cat > ~/.tmux.conf <<EOF
unbind C-b
set -g prefix C-a
bind C-a send-prefix

set -g mouse on
set -g history-limit 50000
set -g default-terminal "screen-256color"
set -g base-index 1
setw -g pane-base-index 1
set -g renumber-windows on

# Плагины
set -g @plugin 'tmux-plugins/tpm'
set -g @plugin 'tmux-plugins/tmux-sensible'
set -g @plugin 'tmux-plugins/tmux-resurrect'
set -g @plugin 'tmux-plugins/tmux-continuum'

# Авто-сохранение и восстановление
set -g @continuum-restore 'on'
set -g @continuum-save-interval '15'
set -g @resurrect-strategy-nvim 'session'

run '~/.tmux/plugins/tpm/tpm'
EOF

# Инсталляция плагинов Tmux (Headless)
~/.tmux/plugins/tpm/bin/install_plugins

# 5. УСТАНОВКА NEOVIM (Универсальный метод)
log_step "[5/6] Установка Neovim..."

# Удаляем старые версии, чтобы избежать конфликтов
sudo rm -rf /opt/nvim* /usr/local/bin/nvim

# Определение архитектуры
ARCH=$(uname -m)
if [[ "$ARCH" == "x86_64" ]]; then
    NVIM_URL="https://github.com/neovim/neovim/releases/download/stable/nvim-linux-x86_64.tar.gz"
    NVIM_ARCHIVE="nvim-linux-x86_64.tar.gz"
elif [[ "$ARCH" == "aarch64" ]]; then
    NVIM_URL="https://github.com/neovim/neovim/releases/download/stable/nvim-linux-arm64.tar.gz"
    NVIM_ARCHIVE="nvim-linux-arm64.tar.gz"
else
    log_warn "Архитектура $ARCH не поддерживается для авто-загрузки бинарника. Устанавливаем через apt (версия может быть старой)."
    sudo apt install -y neovim
fi

if [[ -n "$NVIM_URL" ]]; then
    cd /opt
    log_info "Скачивание Neovim для $ARCH..."
    sudo wget -q --show-progress -O "$NVIM_ARCHIVE" "$NVIM_URL"
    
    sudo tar -xzf "$NVIM_ARCHIVE"
    sudo rm "$NVIM_ARCHIVE"

    # Находим папку (она меняется в зависимости от версии/архитектуры)
    NVIM_DIR=$(find . -maxdepth 1 -type d -name "nvim-linux*" | head -n 1 | sed 's|./||')
    
    if [ -n "$NVIM_DIR" ]; then
        echo "Обнаружена папка установки: $NVIM_DIR"
        sudo ln -sf "/opt/$NVIM_DIR/bin/nvim" /usr/local/bin/nvim
    else
        log_error "Не удалось найти распакованную папку Neovim"
        exit 1
    fi
fi

# Установка vim-plug
sh -c 'curl -fLo "${XDG_DATA_HOME:-$HOME/.local/share}"/nvim/site/autoload/plug.vim --create-dirs \
       https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim'

# === КОНФИГУРАЦИЯ NEOVIM (С ПЛАГИНАМИ И КЛАВИШАМИ) ===
mkdir -p ~/.config/nvim

# Создаем init.vim только если его нет или перезаписываем (по желанию пользователя - тут перезапись)
cat > ~/.config/nvim/init.vim <<EOF
call plug#begin()
Plug 'nvim-lua/plenary.nvim'
Plug 'nvim-telescope/telescope.nvim'
Plug 'nvim-treesitter/nvim-treesitter', {'do': ':TSUpdate'}
Plug 'itchyny/lightline.vim'
Plug 'junegunn/fzf', { 'do': { -> fzf#install() } }
Plug 'dracula/vim', { 'as': 'dracula' }
call plug#end()

" --- Базовые настройки ---
set number
set relativenumber
set tabstop=4 shiftwidth=4 expandtab
set clipboard+=unnamedplus
set termguicolors
set ignorecase
set smartcase
syntax on

" --- Цветовая схема ---
try
    colorscheme dracula
catch
    colorscheme default
endtry

" --- ГОРЯЧИЕ КЛАВИШИ ---
let mapleader = " " " Пробел - главная клавиша

" Telescope (Поиск)
nnoremap <leader>ff <cmd>Telescope find_files<cr>
nnoremap <leader>fg <cmd>Telescope live_grep<cr>
nnoremap <leader>fb <cmd>Telescope buffers<cr>
nnoremap <leader>fh <cmd>Telescope help_tags<cr>

" Удобная навигация по окнам (Ctrl+h/j/k/l)
nnoremap <C-h> <C-w>h
nnoremap <C-j> <C-w>j
nnoremap <C-k> <C-w>k
nnoremap <C-l> <C-w>l

" Выход из insert mode по jk
inoremap jk <Esc>

" Treesitter (сворачивание кода)
set foldmethod=expr
set foldexpr=nvim_treesitter#foldexpr()
set nofoldenable
EOF

# Установка плагинов Nvim
log_info "Инсталляция плагинов Neovim..."
/usr/local/bin/nvim --headless +PlugInstall +qall

# 6. БЕЗОПАСНОСТЬ
log_step "[6/6] Hardening сервера..."
sudo ufw allow OpenSSH
# Не включаем force enable бездумно, чтобы не выкинуть юзера, если SSH на нестандартном порту
# sudo ufw --force enable 
# Лучше просто разрешить и включить
echo "y" | sudo ufw enable

# SSH Hardening (только если есть ключи у ТЕКУЩЕГО пользователя)
if [ -s ~/.ssh/authorized_keys ]; then
    log_info "SSH ключи найдены. Отключаем вход по паролю..."
    # Бэкап конфига
    sudo cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak
    
    sudo sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
    sudo sed -i 's/^#*PermitRootLogin.*/PermitRootLogin prohibit-password/' /etc/ssh/sshd_config
    
    # Создаем директорию для privilege separation, если её нет (частая ошибка в контейнерах/VPS)
    sudo mkdir -p /run/sshd

    # Проверка конфигурации перед рестартом
    if sudo sshd -t; then
        sudo systemctl restart ssh
        log_success "SSH перезапущен с новыми настройками безопасности."
    else
        log_error "Ошибка в конфигурации SSH! Восстанавливаем бэкап..."
        sudo cp /etc/ssh/sshd_config.bak /etc/ssh/sshd_config
    fi
else
    log_warn "Ключи в ~/.ssh/authorized_keys не найдены! Вход по паролю оставлен."
fi

# Fail2Ban
if [ ! -f /etc/fail2ban/jail.local ]; then
    sudo cp /etc/fail2ban/jail.conf /etc/fail2ban/jail.local
    sudo systemctl restart fail2ban
fi

log_info "=== Установка завершена! ==="
echo "1. Перезайдите на сервер, чтобы активировать Zsh."
echo "2. Проверьте настройки фаервола: sudo ufw status"

#!/bin/bash

# Останавливаем скрипт при любой ошибке
set -e

# Цвета для вывода
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${BLUE}=== Запуск полной настройки VPS (Zsh + Tmux + Nvim + Security) ===${NC}"

# 1. ОБНОВЛЕНИЕ И БАЗОВЫЕ УТИЛИТЫ
echo -e "${GREEN}[1/6] Обновление системы и установка зависимостей...${NC}"
sudo apt update && sudo apt upgrade -y
sudo apt install -y curl git wget unzip ufw fail2ban build-essential htop tar zsh

# 2. УСТАНОВКА MODERN TOOLS (Ripgrep, Bat, FZF)
echo -e "${GREEN}[2/6] Установка современных утилит...${NC}"
sudo apt install -y ripgrep fd-find
# Bat (cat с подсветкой)
sudo apt install -y bat
mkdir -p ~/.local/bin
ln -sf /usr/bin/batcat ~/.local/bin/bat

# FZF (Fuzzy Finder)
if [ ! -d "$HOME/.fzf" ]; then
    git clone --depth 1 https://github.com/junegunn/fzf.git ~/.fzf
    ~/.fzf/install --all
fi

# 3. УСТАНОВКА ZSH & OH-MY-ZSH
echo -e "${GREEN}[3/6] Настройка Zsh и Oh-My-Zsh...${NC}"
rm -rf ~/.oh-my-zsh
# Установка OMZ
sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended

# Плагины Zsh
ZSH_CUSTOM=${ZSH_CUSTOM:-~/.oh-my-zsh/custom}
git clone https://github.com/zsh-users/zsh-autosuggestions ${ZSH_CUSTOM}/plugins/zsh-autosuggestions 2>/dev/null || true
git clone https://github.com/zsh-users/zsh-syntax-highlighting.git ${ZSH_CUSTOM}/plugins/zsh-syntax-highlighting 2>/dev/null || true

# Настройка .zshrc
sed -i 's/plugins=(git)/plugins=(git zsh-autosuggestions zsh-syntax-highlighting z)/' ~/.zshrc
echo 'export PATH="$HOME/.local/bin:/usr/local/bin:$PATH"' >> ~/.zshrc
echo 'alias vim="nvim"' >> ~/.zshrc
echo 'alias v="nvim"' >> ~/.zshrc

# Смена шелла
sudo chsh -s $(which zsh) $USER

# 4. НАСТРОЙКА TMUX (TPM + Resurrect + Continuum)
echo -e "${GREEN}[4/6] Настройка Tmux...${NC}"
sudo apt install -y tmux
# Установка TPM
if [ ! -d "$HOME/.tmux/plugins/tpm" ]; then
    git clone https://github.com/tmux-plugins/tpm ~/.tmux/plugins/tpm
fi

# Конфиг Tmux
cat > ~/.tmux.conf <<EOF
unbind C-b
set -g prefix C-a

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

# 5. УСТАНОВКА NEOVIM (Робастный метод)
echo -e "${GREEN}[5/6] Установка Neovim (Stable)...${NC}"

# Очистка
sudo rm -rf /opt/nvim* /usr/local/bin/nvim

# Скачивание
cd /opt
sudo wget -q --show-progress -O nvim.tar.gz https://github.com/neovim/neovim/releases/download/stable/nvim-linux-x86_64.tar.gz

# Распаковка
sudo tar -xzf nvim.tar.gz
sudo rm nvim.tar.gz

# Авто-поиск папки (чтобы не зависеть от имени nvim-linux64 vs nvim-linux-x86_64)
NVIM_DIR=$(find . -maxdepth 1 -type d -name "nvim-linux*" | head -n 1 | sed 's|./||')

if [ -z "$NVIM_DIR" ]; then
    echo -e "${RED}ОШИБКА: Не удалось найти папку Neovim после распаковки!${NC}"
    exit 1
fi

echo "Обнаружена папка установки: $NVIM_DIR"
sudo ln -sf "/opt/$NVIM_DIR/bin/nvim" /usr/local/bin/nvim

# Установка vim-plug
sh -c 'curl -fLo "${XDG_DATA_HOME:-$HOME/.local/share}"/nvim/site/autoload/plug.vim --create-dirs \
       https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim'

# === КОНФИГУРАЦИЯ NEOVIM (С ПЛАГИНАМИ И КЛАВИШАМИ) ===
mkdir -p ~/.config/nvim
cat > ~/.config/nvim/init.vim <<EOF
call plug#begin()
Plug 'nvim-lua/plenary.nvim'
Plug 'nvim-telescope/telescope.nvim'
Plug 'nvim-treesitter/nvim-treesitter', {'do': ':TSUpdate'}
Plug 'itchyny/lightline.vim'
Plug 'junegunn/fzf', { 'do': { -> fzf#install() } }
call plug#end()

" --- Базовые настройки ---
set number
set relativenumber
set tabstop=4 shiftwidth=4 expandtab
set clipboard+=unnamedplus
set termguicolors
syntax on

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

" Treesitter (сворачивание кода)
set foldmethod=expr
set foldexpr=nvim_treesitter#foldexpr()
set nofoldenable
EOF

# Установка плагинов Nvim
echo "Инсталляция плагинов Neovim..."
/usr/local/bin/nvim --headless +PlugInstall +qall

# 6. БЕЗОПАСНОСТЬ
echo -e "${GREEN}[6/6] Hardening сервера...${NC}"
sudo ufw allow OpenSSH
sudo ufw --force enable

# SSH Hardening (только если есть ключи)
if [ -s ~/.ssh/authorized_keys ]; then
    echo "SSH ключи найдены. Отключаем вход по паролю..."
    sudo sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
    sudo sed -i 's/^#*PermitRootLogin.*/PermitRootLogin prohibit-password/' /etc/ssh/sshd_config
    sudo systemctl restart ssh
else
    echo -e "${RED}WARNING: Ключи не найдены! Вход по паролю оставлен.${NC}"
fi

# Fail2Ban
if [ ! -f /etc/fail2ban/jail.local ]; then
    sudo cp /etc/fail2ban/jail.conf /etc/fail2ban/jail.local
    sudo systemctl restart fail2ban
fi

echo -e "${BLUE}=== Установка завершена! ===${NC}"
echo "Перезайдите на сервер, чтобы активировать Zsh."
echo "В Neovim используйте ПРОБЕЛ+f+f для поиска файлов."

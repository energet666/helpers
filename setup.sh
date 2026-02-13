#!/bin/bash

# ================================================
# Скрипт первоначальной настройки VPS
# Zsh + Tmux + Neovim + Security Hardening
# Поддержка: Debian / Ubuntu (x86_64, aarch64)
# ================================================

set -euo pipefail

# ── Цвета для вывода ──────────────────────────────────────
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info()    { echo -e "${BLUE}=== $1 ===${NC}"; }
log_step()    { echo -e "${GREEN}>>> $1${NC}"; }
log_warn()    { echo -e "${YELLOW}[WARN] $1${NC}"; }
log_error()   { echo -e "${RED}[ERROR] $1${NC}"; }
log_success() { echo -e "${GREEN}[SUCCESS] $1${NC}"; }

# ── Trap: информативное сообщение при ошибке ──────────────
on_error() {
    local exit_code=$?
    local line_no=$1
    log_error "Скрипт завершился с ошибкой (код: $exit_code) на строке $line_no"
    log_error "Команда: $(sed -n "${line_no}p" "$0")"
    exit "$exit_code"
}
trap 'on_error $LINENO' ERR

# ── Проверка ОС ───────────────────────────────────────────
if [ ! -f /etc/os-release ]; then
    log_error "Не удалось определить ОС. Скрипт предназначен для Debian/Ubuntu."
    exit 1
fi

. /etc/os-release
if [[ "$ID" != "ubuntu" && "$ID" != "debian" ]]; then
    log_error "Скрипт поддерживает только Debian и Ubuntu (обнаружено: $ID $VERSION_ID)"
    exit 1
fi
log_info "ОС: $PRETTY_NAME"

# ── Проверка: не запущен ли скрипт напрямую от root ───────
if [[ "$EUID" -eq 0 ]]; then
    log_warn "Скрипт запущен от root. Все конфиги будут установлены для /root."
    log_warn "Если нужен для другого пользователя — запустите от его имени."
fi

# ── Функция для идемпотентного добавления строк в файлы ───
append_if_missing() {
    local file="$1"
    local line="$2"
    if [ -f "$file" ]; then
        grep -qF "$line" "$file" || echo "$line" >> "$file"
    else
        echo "$line" >> "$file"
    fi
}

# ── Функция для клонирования / обновления git-репо ────────
clone_or_pull() {
    local repo_url="$1"
    local target_dir="$2"
    if [ ! -d "$target_dir" ]; then
        git clone --depth 1 "$repo_url" "$target_dir"
    else
        log_warn "$(basename "$target_dir") уже существует, обновляем..."
        git -C "$target_dir" pull --ff-only 2>/dev/null || true
    fi
}

TOTAL_STEPS=7
STEP=0
next_step() {
    STEP=$((STEP + 1))
    log_step "[$STEP/$TOTAL_STEPS] $1"
}

log_info "Запуск полной настройки VPS (Zsh + Tmux + Nvim + Security)"

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 1. ОБНОВЛЕНИЕ И БАЗОВЫЕ УТИЛИТЫ
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
next_step "Обновление системы и установка зависимостей"
sudo apt update && sudo apt upgrade -y
sudo apt install -y \
    curl git wget unzip ufw fail2ban \
    build-essential htop tar zsh \
    software-properties-common \
    ripgrep fd-find bat

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 2. УСТАНОВКА MODERN TOOLS
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
next_step "Установка современных утилит (fd, bat, fzf)"

# На Ubuntu fd устанавливается как fdfind — делаем симлинк
if ! command -v fd &> /dev/null && command -v fdfind &> /dev/null; then
    sudo ln -sf "$(which fdfind)" /usr/local/bin/fd
    log_info "Создан симлинк: fdfind → fd"
fi

# На Ubuntu bat устанавливается как batcat — делаем симлинк
if ! command -v bat &> /dev/null && command -v batcat &> /dev/null; then
    mkdir -p ~/.local/bin
    ln -sf /usr/bin/batcat ~/.local/bin/bat
    log_info "Создан симлинк: batcat → bat"
fi

# FZF (Fuzzy Finder) — клон или обновление
clone_or_pull "https://github.com/junegunn/fzf.git" "$HOME/.fzf"
"$HOME/.fzf/install" --all --no-update-rc 2>/dev/null || true

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 3. УСТАНОВКА ZSH & OH-MY-ZSH
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
next_step "Настройка Zsh и Oh-My-Zsh"

# Установка OMZ (если нет)
if [ ! -d "$HOME/.oh-my-zsh" ]; then
    RUNZSH=no CHSH=no sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
else
    log_warn "Oh-My-Zsh уже установлен."
fi

# Плагины Zsh
ZSH_CUSTOM="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"
mkdir -p "$ZSH_CUSTOM/plugins"

clone_or_pull "https://github.com/zsh-users/zsh-autosuggestions"       "$ZSH_CUSTOM/plugins/zsh-autosuggestions"
clone_or_pull "https://github.com/zsh-users/zsh-syntax-highlighting"   "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting"
clone_or_pull "https://github.com/agkozak/zsh-z"                       "$ZSH_CUSTOM/plugins/zsh-z"

# Настройка .zshrc — идемпотентная замена плагинов
DESIRED_PLUGINS="plugins=(git zsh-autosuggestions zsh-syntax-highlighting zsh-z fzf)"
if grep -q "^plugins=" ~/.zshrc 2>/dev/null; then
    # Заменяем любую строку plugins=(...) на нужную
    sed -i "s/^plugins=(.*)/$DESIRED_PLUGINS/" ~/.zshrc
else
    append_if_missing ~/.zshrc "$DESIRED_PLUGINS"
fi

# Добавить PATH и алиасы (идемпотентно)
append_if_missing ~/.zshrc 'export PATH="$HOME/.local/bin:/usr/local/bin:$PATH"'
append_if_missing ~/.zshrc 'alias vim="nvim"'
append_if_missing ~/.zshrc 'alias v="nvim"'
# bat alias только для интерактивного режима, чтобы не ломать скрипты
append_if_missing ~/.zshrc 'alias cat="bat --paging=never"'

# Настройка FZF-интеграции для Zsh
append_if_missing ~/.zshrc '[ -f ~/.fzf.zsh ] && source ~/.fzf.zsh'

# Смена шелла на zsh
ZSH_PATH="$(which zsh)"
if [ "$SHELL" != "$ZSH_PATH" ]; then
    sudo chsh -s "$ZSH_PATH" "$USER"
    log_info "Шелл изменён на $ZSH_PATH (вступит в силу при следующем входе)"
fi

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 4. НАСТРОЙКА TMUX (TPM + Resurrect + Continuum)
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
next_step "Настройка Tmux"
sudo apt install -y tmux

# Установка TPM
clone_or_pull "https://github.com/tmux-plugins/tpm" "$HOME/.tmux/plugins/tpm"

# Конфиг Tmux
cat > ~/.tmux.conf <<'EOF'
unbind C-b
set -g prefix C-a
bind C-a send-prefix

set -g mouse on
set -g history-limit 50000
set -g default-terminal "screen-256color"
set -ga terminal-overrides ",xterm-256color:Tc"
set -g base-index 1
setw -g pane-base-index 1
set -g renumber-windows on
set -g escape-time 10
set -g focus-events on

# Статус-бар сверху
set -g status-position top

# Быстрое переключение панелей через Alt+стрелки
bind -n M-Left  select-pane -L
bind -n M-Right select-pane -R
bind -n M-Up    select-pane -U
bind -n M-Down  select-pane -D

# Разделение окон — более интуитивные клавиши
bind | split-window -h -c "#{pane_current_path}"
bind - split-window -v -c "#{pane_current_path}"

# Reload конфига
bind r source-file ~/.tmux.conf \; display "Config reloaded!"

# Плагины
set -g @plugin 'tmux-plugins/tpm'
set -g @plugin 'tmux-plugins/tmux-sensible'
set -g @plugin 'tmux-plugins/tmux-resurrect'
set -g @plugin 'tmux-plugins/tmux-continuum'
set -g @plugin 'catppuccin/tmux#v2.1.3'

# Catppuccin — настройки (до загрузки TPM)
set -g @catppuccin_flavor 'mocha'
set -g @catppuccin_window_status_style 'rounded'
set -g @catppuccin_window_text " #W"
set -g @catppuccin_window_current_text " #W"
set -g @catppuccin_window_number_position "left"
set -g @catppuccin_date_time_text " %d.%m %H:%M"

# Авто-сохранение и восстановление
set -g @continuum-restore 'on'
set -g @continuum-save-interval '15'
set -g @resurrect-strategy-nvim 'session'

# Загрузка TPM и плагинов (catppuccin определит свои переменные)
run '~/.tmux/plugins/tpm/tpm'

# Статус-бар (ПОСЛЕ загрузки catppuccin, чтобы переменные были доступны)
set -g status-left-length 100
set -g status-right-length 100
set -g status-left "#{E:@catppuccin_status_session} "
set -g status-right "#{E:@catppuccin_status_host}"
set -ag status-right "#{E:@catppuccin_status_date_time}"
EOF

# Инсталляция плагинов Tmux (headless)
if [ -x "$HOME/.tmux/plugins/tpm/bin/install_plugins" ]; then
    "$HOME/.tmux/plugins/tpm/bin/install_plugins" || log_warn "Некоторые tmux-плагины не установились"
fi

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 5. УСТАНОВКА NODE.JS (через NodeSource)
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
next_step "Установка Node.js LTS"

if command -v node &> /dev/null; then
    log_warn "Node.js уже установлен: $(node --version). Пропускаем."
else
    # Установка через NodeSource (LTS)
    curl -fsSL https://deb.nodesource.com/setup_lts.x | sudo -E bash -
    sudo apt install -y nodejs
    log_success "Node.js установлен: $(node --version), npm: $(npm --version)"
fi



# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 6. УСТАНОВКА NEOVIM (из официального бинарника)
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
next_step "Установка Neovim"

ARCH=$(uname -m)
NVIM_URL=""
NVIM_DIR_NAME=""

case "$ARCH" in
    x86_64)
        NVIM_URL="https://github.com/neovim/neovim/releases/download/stable/nvim-linux-x86_64.tar.gz"
        NVIM_DIR_NAME="nvim-linux-x86_64"
        ;;
    aarch64)
        NVIM_URL="https://github.com/neovim/neovim/releases/download/stable/nvim-linux-arm64.tar.gz"
        NVIM_DIR_NAME="nvim-linux-arm64"
        ;;
    *)
        log_warn "Архитектура $ARCH не поддерживается для бинарника. Устанавливаем через apt."
        sudo apt install -y neovim
        ;;
esac

if [[ -n "$NVIM_URL" ]]; then
    # Удаляем старую установку
    sudo rm -rf /opt/nvim-linux-* /usr/local/bin/nvim

    log_info "Скачивание Neovim для $ARCH..."
    # Скачиваем во временную директорию, чтобы не менять cwd
    NVIM_TMP=$(mktemp -d)
    wget -q --show-progress -O "$NVIM_TMP/nvim.tar.gz" "$NVIM_URL"

    sudo tar -xzf "$NVIM_TMP/nvim.tar.gz" -C /opt
    rm -rf "$NVIM_TMP"

    if [ -d "/opt/$NVIM_DIR_NAME" ]; then
        sudo ln -sf "/opt/$NVIM_DIR_NAME/bin/nvim" /usr/local/bin/nvim
        log_success "Neovim установлен: $(nvim --version | head -1)"
    else
        log_error "Не найдена распакованная папка /opt/$NVIM_DIR_NAME"
        exit 1
    fi
fi

# --- Установка LazyVim ---
# Бэкап существующей конфигурации (если есть)
for dir in ~/.config/nvim ~/.local/share/nvim ~/.local/state/nvim ~/.cache/nvim; do
    if [ -d "$dir" ]; then
        backup="${dir}.bak.$(date +%Y%m%d_%H%M%S)"
        mv "$dir" "$backup"
        log_warn "Старая конфигурация перемещена: $backup"
    fi
done

# Клонируем LazyVim starter
git clone https://github.com/LazyVim/starter ~/.config/nvim
# Удаляем .git чтобы можно было вести свой репозиторий
rm -rf ~/.config/nvim/.git
log_success "LazyVim starter установлен в ~/.config/nvim"

# Первый запуск — lazy.nvim скачает и установит все плагины
log_info "Первый запуск Neovim (установка плагинов LazyVim)..."
timeout 180 nvim --headless '+Lazy! sync' +qa 2>/dev/null || {
    log_warn "Установка плагинов не завершилась за 180 секунд."
    log_warn "Запустите nvim вручную — плагины доустановятся автоматически."
}



# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 7. БЕЗОПАСНОСТЬ
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
next_step "Hardening сервера"

# UFW — разрешаем SSH и включаем
sudo ufw allow OpenSSH
if sudo ufw status | grep -q "inactive"; then
    echo "y" | sudo ufw enable
    log_success "UFW активирован."
else
    log_warn "UFW уже активен."
fi

# SSH Hardening (только если есть ключи у ТЕКУЩЕГО пользователя)
if [ -s ~/.ssh/authorized_keys ]; then
    log_info "SSH ключи найдены. Отключаем вход по паролю..."

    # Бэкап конфига
    sudo cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak.$(date +%Y%m%d_%H%M%S)

    sudo sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config
    sudo sed -i 's/^#*PermitRootLogin.*/PermitRootLogin prohibit-password/' /etc/ssh/sshd_config

    # Директория для privilege separation
    if [ ! -d "/run/sshd" ]; then
        log_warn "Директория /run/sshd отсутствует. Создаём..."
        sudo mkdir -p /run/sshd
        sudo chmod 0755 /run/sshd
    fi

    # Проверка конфигурации перед рестартом
    if sudo sshd -t 2>/dev/null; then
        sudo systemctl restart ssh
        log_success "SSH перезапущен с новыми настройками безопасности."
    else
        log_error "Ошибка в конфигурации SSH! Восстанавливаем последний бэкап..."
        LATEST_BACKUP=$(ls -t /etc/ssh/sshd_config.bak.* 2>/dev/null | head -1)
        if [ -n "$LATEST_BACKUP" ]; then
            sudo cp "$LATEST_BACKUP" /etc/ssh/sshd_config
            log_warn "Восстановлен бэкап: $LATEST_BACKUP"
        fi
    fi
else
    log_warn "Ключи в ~/.ssh/authorized_keys не найдены! Вход по паролю оставлен."
    log_warn "Рекомендуется: добавьте ключ и перезапустите скрипт."
fi

# Fail2Ban
if systemctl is-enabled fail2ban &>/dev/null; then
    if [ ! -f /etc/fail2ban/jail.local ]; then
        sudo cp /etc/fail2ban/jail.conf /etc/fail2ban/jail.local
        # Базовая настройка: защита SSH
        sudo tee -a /etc/fail2ban/jail.local > /dev/null <<'JAIL'

[sshd]
enabled = true
port = ssh
filter = sshd
logpath = /var/log/auth.log
maxretry = 5
bantime = 3600
findtime = 600
JAIL
        sudo systemctl restart fail2ban
        log_success "Fail2Ban настроен и запущен."
    else
        log_warn "Fail2Ban jail.local уже существует."
    fi
else
    log_warn "Fail2Ban не найден в systemd. Проверьте установку."
fi

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# ИТОГ
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
echo ""
log_info "=== Установка завершена! ==="
echo ""
echo -e "${GREEN}Что установлено:${NC}"
echo "  • Zsh + Oh-My-Zsh (autosuggestions, syntax-highlighting, z)"
echo "  • Tmux + TPM (resurrect, continuum)"
echo "  • Neovim (stable) + LazyVim (LSP, Treesitter, Telescope, и др.)"
echo "  • FZF, Ripgrep, fd, bat"
echo "  • Node.js LTS"
echo "  • UFW + Fail2Ban + SSH hardening"
echo ""
echo -e "${YELLOW}Следующие шаги:${NC}"
echo "  1. Перезайдите на сервер, чтобы активировать Zsh"
echo "  2. Проверьте фаервол: sudo ufw status"
echo "  3. В tmux нажмите Prefix+I для установки плагинов"
echo "  4. В nvim плагины доустановятся автоматически при первом запуске"
echo ""

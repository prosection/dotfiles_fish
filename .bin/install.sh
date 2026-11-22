#!/bin/bash

# ==============================================================================
# Fish Shell Dotfiles Installation Script
# ==============================================================================
# このスクリプトはFish shellの自動インストールと設定を行います。
# 対応OS: macOS, Ubuntu/Debian, Raspberry Pi (Zero 2 W含む)
# ==============================================================================

set -e  # エラー時に即座に終了
set -u  # 未定義変数の使用でエラー
set -o pipefail  # パイプラインのエラーを検出

# Linux / macOS は USER、一部の環境は USERNAME だけを渡す
if [[ -z "${USER:-}" ]]; then
    USER="${USERNAME:-}"
fi
if [[ -z "${USER:-}" ]]; then
    USER="$(id -un 2>/dev/null || true)"
fi
if [[ -z "${USER:-}" ]]; then
    echo "ユーザー名を取得できません。" >&2
    exit 1
fi
export USER

# 設定可能な変数
SCRIPT_NAME="$(basename "$0")"
readonly CONFIG_DIR="$HOME/.config/fish"
readonly CONFIG_FILE="$CONFIG_DIR/config.fish"
readonly BACKUP_SUFFIX="backup.$(date +%Y%m%d_%H%M%S)"
readonly LOCK_FILE="/tmp/fish_install_${USER}.lock"
readonly LOG_FILE="/tmp/fish_install_${USER}.log"
DRY_RUN=${DRY_RUN:-false}
AUTO_YES=${AUTO_YES:-false}
VERBOSE=${VERBOSE:-false}
SKIP_SHELL_CHANGE=${SKIP_SHELL_CHANGE:-false}

# カラー出力用
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly NC='\033[0m' # No Color

# ログ関数
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
    echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') $1" >> "$LOG_FILE"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
    echo "[SUCCESS] $(date '+%Y-%m-%d %H:%M:%S') $1" >> "$LOG_FILE"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
    echo "[WARN] $(date '+%Y-%m-%d %H:%M:%S') $1" >> "$LOG_FILE"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
    echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') $1" >> "$LOG_FILE"
}

log_debug() {
    if [[ "$VERBOSE" == "true" ]]; then
        echo -e "${CYAN}[DEBUG]${NC} $1"
        echo "[DEBUG] $(date '+%Y-%m-%d %H:%M:%S') $1" >> "$LOG_FILE"
    fi
}

# クリーンアップ関数
cleanup() {
    local exit_code=$?
    log_debug "クリーンアップを実行中..."

    # sudo更新プロセスの停止
    if [[ -n "${SUDO_REFRESH_PID:-}" ]]; then
        kill "$SUDO_REFRESH_PID" 2>/dev/null || true
    fi

    # ロックファイルの削除
    if [[ -f "$LOCK_FILE" ]]; then
        rm -f "$LOCK_FILE"
    fi

    # この実行が作った一時ファイルだけを削除する
    rm -f "/tmp/fish_install_$$.tmp" \
          "/tmp/fish_opensuse_$$.key" \
          "/tmp/eza_gierens_$$.gpg" \
          "/tmp/homebrew_install_$$.sh" 2>/dev/null || true

    if [[ $exit_code -ne 0 ]]; then
        log_error "スクリプトがエラーコード $exit_code で終了しました。"
        log_error "詳細はログファイルを確認してください: $LOG_FILE"
    fi
}

# エラーハンドリング関数
handle_error() {
    local line_no=$1
    local error_code=${2:-1}
    log_error "スクリプトの実行中にエラーが発生しました。行: $line_no, エラーコード: $error_code"
    log_error "実行を中止します。"
    cleanup
    exit "$error_code"
}

trap cleanup EXIT
trap 'handle_error $LINENO $?' ERR

# ロック取得（多重実行防止）
acquire_lock() {
    if [[ -f "$LOCK_FILE" ]]; then
        local pid
        pid=$(cat "$LOCK_FILE" 2>/dev/null || echo "")
        if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
            log_error "別のインスタンスが実行中です (PID: $pid)"
            exit 1
        else
            log_warn "古いロックファイルを削除します"
            rm -f "$LOCK_FILE"
        fi
    fi
    echo $$ > "$LOCK_FILE"
    log_debug "ロックを取得しました (PID: $$)"
}

# 使用方法を表示
show_usage() {
    cat << EOF
使用方法: $SCRIPT_NAME [オプション]

オプション:
  -h, --help           この使用方法を表示
  --dry-run            実際にインストールせずに実行予定の処理を表示
  -y, --yes            確認プロンプトをスキップ
  -v, --verbose        詳細なデバッグ出力を表示
  --skip-shell-change  デフォルトシェルの変更をスキップ

環境変数:
  DRY_RUN=true         ドライランモードで実行
  VERBOSE=true         詳細モードで実行
  SKIP_SHELL_CHANGE=true  シェル変更をスキップ

標準入力が端末でない場合（パイプ実行で TTY が無い場合）は -y を付けてください。
確認プロンプトは /dev/tty から読みます。

例:
  $SCRIPT_NAME                    # 通常のインストール
  $SCRIPT_NAME --dry-run          # ドライランモード
  $SCRIPT_NAME -y                 # 確認をスキップしてインストール
  $SCRIPT_NAME --skip-shell-change  # シェル変更なしでインストール
EOF
}

# システム情報の収集
collect_system_info() {
    log_info "システム情報を収集しています..."

    echo "=== System Information ===" >> "$LOG_FILE"
    echo "Date: $(date)" >> "$LOG_FILE"
    echo "Hostname: $(hostname)" >> "$LOG_FILE"
    echo "User: $USER" >> "$LOG_FILE"
    echo "OSTYPE: ${OSTYPE:-unknown}" >> "$LOG_FILE"
    echo "uname -a: $(uname -a)" >> "$LOG_FILE"
    echo "uname -m: $(uname -m)" >> "$LOG_FILE"

    if [[ -f /etc/os-release ]]; then
        echo "--- /etc/os-release ---" >> "$LOG_FILE"
        cat /etc/os-release >> "$LOG_FILE"
    fi

    if command -v dpkg &>/dev/null; then
        echo "dpkg --print-architecture: $(dpkg --print-architecture 2>/dev/null || echo 'N/A')" >> "$LOG_FILE"
    fi

    if [[ -f /proc/device-tree/model ]]; then
        echo "Device Model: $(tr -d '\0' < /proc/device-tree/model 2>/dev/null || echo 'N/A')" >> "$LOG_FILE"
    fi

    echo "===========================" >> "$LOG_FILE"
}

# 依存関係チェック関数
check_dependencies() {
    log_info "必要なコマンドの確認を行っています..."
    local missing_commands=()

    for cmd in curl git; do
        if ! command -v "$cmd" &> /dev/null; then
            missing_commands+=("$cmd")
        fi
    done

    if [[ ${#missing_commands[@]} -gt 0 ]]; then
        log_warn "以下のコマンドが見つかりません: ${missing_commands[*]}"

        if [[ "$DRY_RUN" == "true" ]]; then
            log_info "[DRY RUN] 不足しているコマンドのインストールを実行する予定: ${missing_commands[*]}"
            return 0
        fi

        log_info "必要なパッケージをインストールしています..."

        if command -v apt &>/dev/null; then
            sudo apt update
            sudo apt install -y curl git || {
                log_error "依存パッケージのインストールに失敗しました。"
                exit 1
            }
        else
            log_error "これらのコマンドを手動でインストールしてから再実行してください。"
            exit 1
        fi
    fi

    log_success "依存関係の確認が完了しました。"
}

# sudo権限の確認
check_sudo() {
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] sudo権限の確認を実行する予定"
        return 0
    fi

    log_info "sudo権限の確認を行っています..."
    if ! sudo -n true 2>/dev/null; then
        log_warn "このスクリプトはsudo権限を必要とします。"
        echo "パスワードの入力を求められる場合があります。"
        if ! sudo -v; then
            log_error "sudo権限の取得に失敗しました。"
            exit 1
        fi
    fi

    # sudo のタイムアウトを延長（バックグラウンドで定期的に更新）
    (while true; do sudo -n true; sleep 50; done 2>/dev/null) &
    SUDO_REFRESH_PID=$!
    log_debug "sudo更新プロセス開始: PID $SUDO_REFRESH_PID"

    log_success "sudo権限の確認が完了しました。"
}

# アーキテクチャ検出
detect_architecture() {
    local arch
    arch=$(uname -m)

    case "$arch" in
        x86_64)
            echo "amd64"
            ;;
        aarch64)
            echo "arm64"
            ;;
        armv7l|armv6l)
            echo "armhf"
            ;;
        *)
            echo "$arch"
            ;;
    esac
}

# os-release のキーを取得する。無い場合は空文字
os_release_value() {
    local key="$1"
    local value=""

    if [[ -f /etc/os-release ]]; then
        value=$(grep -E "^${key}=" /etc/os-release 2>/dev/null | head -n 1 | cut -d= -f2- | tr -d '"' | tr -d "'" || true)
    fi

    echo "$value"
}

# OS検出関数
detect_os() {
    local os_type="unsupported"
    local os_id=""

    if [[ "$OSTYPE" == "darwin"* ]]; then
        echo "macos"
        return 0
    fi

    if [[ "$OSTYPE" != "linux-gnu"* && "$OSTYPE" != "linux"* ]]; then
        echo "unsupported"
        return 0
    fi

    os_id=$(os_release_value ID)

    # Ubuntu on Raspberry Pi でも Fish 4 の PPA を使う
    if [[ "$os_id" == "ubuntu" ]]; then
        echo "ubuntu"
        return 0
    fi

    if [[ "$os_id" == "raspbian" || "$os_id" == "raspberrypi" || -f /etc/rpi-issue ]]; then
        echo "raspberrypi"
        return 0
    fi

    # NULLバイトを除去して機種名を見る
    if [[ -f /proc/device-tree/model ]] && tr -d '\0' < /proc/device-tree/model 2>/dev/null | grep -qi "raspberry pi"; then
        echo "raspberrypi"
        return 0
    fi

    if [[ "$os_id" == "debian" || -f /etc/debian_version ]]; then
        echo "debian"
        return 0
    fi

    echo "unsupported_linux"
}

# Debianバージョン検出
detect_debian_version() {
    local version=""
    local codename=""

    version=$(os_release_value VERSION_ID)
    version="${version%%.*}"

    if [[ -z "$version" || ! "$version" =~ ^[0-9]+$ ]]; then
        if [[ -f /etc/debian_version ]]; then
            version=$(cut -d'.' -f1 < /etc/debian_version 2>/dev/null || true)
        fi
    fi

    if [[ -z "$version" || ! "$version" =~ ^[0-9]+$ ]]; then
        codename=$(os_release_value VERSION_CODENAME)
        case "$codename" in
            forky)    version="14" ;;
            trixie)   version="13" ;;
            bookworm) version="12" ;;
            bullseye) version="11" ;;
            buster)   version="10" ;;
            *)        version="" ;;
        esac
    fi

    echo "$version"
}

# 安全なcurlダウンロード関数
safe_curl() {
    local url="$1"
    local output="${2:-}"
    local timeout="${3:-30}"

    local curl_opts=(
        --connect-timeout 10
        --max-time "$timeout"
        --retry 3
        --retry-delay 2
        -fsSL
    )

    if [[ -n "$output" ]]; then
        curl "${curl_opts[@]}" -o "$output" "$url"
    else
        curl "${curl_opts[@]}" "$url"
    fi
}

# 確認プロンプト。パイプ実行でも端末から読む
prompt_yes() {
    local prompt="$1"
    local reply=""

    if [[ ! -r /dev/tty ]]; then
        log_warn "対話端末がありません。非対話で続行するには -y を指定してください。"
        return 1
    fi

    if ! read -rp "$prompt" reply </dev/tty; then
        return 1
    fi

    [[ "$reply" =~ ^[Yy]$ ]]
}

# APT 署名検証用の gpg
ensure_gpg() {
    if command -v gpg &>/dev/null; then
        return 0
    fi

    log_info "パッケージ署名の検証に必要な gpg をインストールしています..."
    if sudo apt install -y gpg; then
        return 0
    fi

    log_warn "gpg のインストールに失敗しました。"
    return 1
}

# ja_JP.UTF-8 が無ければ有効化する。失敗してもインストールは続行する
ensure_ja_locale() {
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] ja_JP.UTF-8 ロケールの確認と有効化を実行する予定"
        return 0
    fi

    if locale -a 2>/dev/null | grep -qiE '^ja_JP\.(utf8|UTF-8)$'; then
        log_info "ja_JP.UTF-8 は既に有効です。"
        return 0
    fi

    log_info "ja_JP.UTF-8 ロケールを有効化しています..."
    if ! sudo apt install -y locales; then
        log_warn "locales のインストールに失敗しました。LANG は利用可能なロケールにフォールバックします。"
        return 0
    fi

    if [[ -f /etc/locale.gen ]]; then
        if grep -qE '^# *ja_JP\.UTF-8 UTF-8' /etc/locale.gen; then
            sudo sed -i 's/^# *\(ja_JP\.UTF-8 UTF-8\)/\1/' /etc/locale.gen
        elif ! grep -qE '^ja_JP\.UTF-8 UTF-8' /etc/locale.gen; then
            echo 'ja_JP.UTF-8 UTF-8' | sudo tee -a /etc/locale.gen >/dev/null
        fi
    fi

    if sudo locale-gen ja_JP.UTF-8; then
        log_success "ja_JP.UTF-8 を有効化しました。"
    else
        log_warn "ja_JP.UTF-8 の生成に失敗しました。LANG は利用可能なロケールにフォールバックします。"
    fi
}

# Debian の fd-find は実体が fdfind なので、fd からも呼べるようにする
link_fd_binary() {
    local fdfind_path=""

    if [[ "$DRY_RUN" == "true" ]]; then
        return 0
    fi

    if command -v fd &>/dev/null; then
        return 0
    fi

    fdfind_path=$(command -v fdfind 2>/dev/null || true)
    if [[ -n "$fdfind_path" ]]; then
        sudo mkdir -p /usr/local/bin
        sudo ln -sfn "$fdfind_path" /usr/local/bin/fd || log_warn "fd へのシンボリックリンク作成に失敗しました。"
    fi
}

# macOS用インストール関数
install_fish_macos() {
    log_info "macOS用のFishインストールを開始します..."

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Homebrewの確認とFishのインストールを実行する予定"
        return 0
    fi

    if ! command -v brew &> /dev/null; then
        if [[ -x /opt/homebrew/bin/brew ]]; then
            eval "$(/opt/homebrew/bin/brew shellenv)"
        elif [[ -x /usr/local/bin/brew ]]; then
            eval "$(/usr/local/bin/brew shellenv)"
        fi
    fi

    if ! command -v brew &> /dev/null; then
        log_info "Homebrewをインストールしています..."
        log_warn "Homebrewのインストールには手動確認が必要な場合があります。"

        # Homebrewインストールスクリプトをダウンロードして確認
        local brew_script="/tmp/homebrew_install_$$.sh"
        if ! safe_curl "https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh" "$brew_script" 60; then
            log_error "Homebrewインストールスクリプトのダウンロードに失敗しました。"
            return 1
        fi

        # スクリプトを実行
        /bin/bash "$brew_script" || {
            log_error "Homebrewのインストールに失敗しました。"
            rm -f "$brew_script"
            return 1
        }
        rm -f "$brew_script"

        # Homebrewのパスを追加
        if [[ -f /opt/homebrew/bin/brew ]]; then
            eval "$(/opt/homebrew/bin/brew shellenv)"
        elif [[ -f /usr/local/bin/brew ]]; then
            eval "$(/usr/local/bin/brew shellenv)"
        fi
    fi

    log_info "fishをインストールしています..."
    brew install fish || {
        log_error "fishのインストールに失敗しました。"
        return 1
    }

    # ezaのインストール（exaの後継）
    log_info "eza（モダンなlsの代替）をインストールしています..."
    brew install eza || log_warn "ezaのインストールに失敗しました。"

    # その他のツール
    for pkg in bat fd ripgrep fzf; do
        log_info "$pkg をインストール中..."
        brew install "$pkg" 2>/dev/null || log_warn "$pkg のインストールに失敗しました（オプション）"
    done

    log_success "macOS用のFishインストールが完了しました。"
}

# ezaのインストール（Debian/Ubuntu用）
install_eza_debian() {
    log_info "ezaをインストールしています..."

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] ezaリポジトリの追加とインストールを実行する予定"
        return 0
    fi

    if ! ensure_gpg; then
        log_warn "eza をスキップします。標準の ls を使用します。"
        return 1
    fi

    # GPGキーディレクトリの作成
    sudo mkdir -p /etc/apt/keyrings

    # GPGキーのダウンロードと追加
    local gpg_key_file="/tmp/eza_gierens_$$.gpg"
    if safe_curl "https://raw.githubusercontent.com/eza-community/eza/main/deb.asc" "$gpg_key_file"; then
        # 既存のキーを削除
        sudo rm -f /etc/apt/keyrings/gierens.gpg

        sudo gpg --batch --yes --dearmor -o /etc/apt/keyrings/gierens.gpg < "$gpg_key_file" 2>/dev/null || {
            log_warn "GPGキーの追加に失敗しました。"
            rm -f "$gpg_key_file"
            return 1
        }
        rm -f "$gpg_key_file"

        # リポジトリの追加
        echo "deb [signed-by=/etc/apt/keyrings/gierens.gpg] http://deb.gierens.de stable main" | \
            sudo tee /etc/apt/sources.list.d/gierens.list > /dev/null

        # パーミッションの設定
        sudo chmod 644 /etc/apt/keyrings/gierens.gpg /etc/apt/sources.list.d/gierens.list

        # パッケージリストの更新とインストール
        if sudo apt update >>"$LOG_FILE" 2>&1 && sudo apt install -y eza >>"$LOG_FILE" 2>&1; then
            log_success "ezaのインストールが完了しました。"
            return 0
        fi
    fi

    log_warn "ezaのインストールに失敗しました。標準のlsを使用します。"
    return 1
}

# Ubuntu/Debian用インストール関数
install_fish_ubuntu() {
    log_info "Ubuntu/Debian用のFishインストールを開始します..."

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] apt updateとFish及び関連パッケージのインストールを実行する予定"
        return 0
    fi

    local os_type
    os_type=$(detect_os)

    log_info "パッケージリストを更新しています..."
    sudo apt update || {
        log_error "パッケージリストの更新に失敗しました。"
        return 1
    }

    # Ubuntuの場合のみ Fish 4 の PPA を使用
    if [[ "$os_type" == "ubuntu" ]]; then
        log_info "Fish 4 PPAを追加しています..."
        sudo apt install -y software-properties-common 2>/dev/null || true

        local add_repo=""
        if command -v add-apt-repository &>/dev/null; then
            add_repo="add-apt-repository"
        elif command -v apt-add-repository &>/dev/null; then
            add_repo="apt-add-repository"
        fi

        if [[ -n "$add_repo" ]]; then
            if ! sudo "$add_repo" -y ppa:fish-shell/release-4; then
                log_warn "Fish PPAの追加に失敗しました。標準リポジトリを使用します。"
            fi
            sudo apt update || log_warn "PPA追加後のパッケージリスト更新に失敗しました。"
        else
            log_warn "add-apt-repository が見つかりません。標準リポジトリを使用します。"
        fi
    fi

    log_info "fishをインストールしています..."
    if ! sudo apt install -y fish; then
        log_error "fishのインストールに失敗しました。"
        return 1
    fi

    # eza のインストール
    install_eza_debian || true

    # 必須パッケージ
    local essential_packages=("git" "curl" "fontconfig")
    for package in "${essential_packages[@]}"; do
        if sudo apt install -y "$package" 2>/dev/null; then
            log_success "$package のインストールが完了しました。"
        else
            log_warn "$package のインストールに失敗しました。"
        fi
    done

    # オプションパッケージ
    local optional_packages=("fzf" "bat" "fd-find" "ripgrep")
    local installed_optional=0

    for package in "${optional_packages[@]}"; do
        if sudo apt install -y "$package" 2>/dev/null; then
            log_success "$package のインストールが完了しました。"
            installed_optional=$((installed_optional + 1))
        else
            log_warn "$package のインストールに失敗しました（オプション）。"
        fi
    done

    link_fd_binary
    ensure_ja_locale

    log_success "Ubuntu/Debian用のFishインストールが完了しました。"
    log_info "オプションパッケージ: $installed_optional/${#optional_packages[@]} インストール済み"
}

# Raspberry Pi用インストール関数
install_fish_raspberrypi() {
    log_info "Raspberry Pi用のFishインストールを開始します..."

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Fishと関連パッケージのインストールを実行する予定"
        return 0
    fi

    local arch
    arch=$(detect_architecture)
    log_info "検出されたアーキテクチャ: $arch"

    local debian_version
    debian_version=$(detect_debian_version)
    log_info "検出されたDebianバージョン: ${debian_version:-不明}"

    log_info "パッケージリストを更新しています..."
    sudo apt update || {
        log_warn "パッケージリストの更新に警告がありました。続行します..."
    }

    # まず標準リポジトリからfishのインストールを試行
    log_info "標準リポジトリからFishのインストールを試行しています..."
    local fish_installed=false

    if sudo apt install -y fish 2>&1 | tee -a "$LOG_FILE"; then
        # インストール後に実際に存在するか確認
        if dpkg -l fish 2>/dev/null | grep -q "^ii"; then
            log_success "標準リポジトリからのFishインストールが完了しました。"
            fish_installed=true
        fi
    fi

    if [[ "$fish_installed" != "true" ]]; then
        log_warn "標準リポジトリからのインストールに失敗しました。"

        if [[ -z "$debian_version" ]]; then
            log_error "Debianバージョンの取得に失敗しました。"
            log_error "手動で以下を試してください: sudo apt install fish"
            return 1
        fi

        # Debian 12 以降は Fish 4、それより前は Fish 3 の OBS リポジトリを使う
        local fish_series="3"
        if [[ "$debian_version" -ge 12 ]]; then
            fish_series="4"
        fi

        log_info "openSUSE Build Service (fish ${fish_series}.x) からのインストールを試行します..."

        if ! ensure_gpg; then
            log_error "GPG が無いため、外部リポジトリから fish をインストールできません。"
            return 1
        fi

        local repo_url="https://download.opensuse.org/repositories/shells:/fish:/release:/${fish_series}/Debian_${debian_version}"
        local gpg_key_file="/tmp/fish_opensuse_$$.key"
        local keyring="/etc/apt/keyrings/shells_fish_release_${fish_series}.gpg"
        local list_file="/etc/apt/sources.list.d/shells_fish_release_${fish_series}.list"

        log_debug "リポジトリURL: $repo_url"

        if ! safe_curl "${repo_url}/Release.key" "$gpg_key_file" 30; then
            log_error "GPGキーのダウンロードに失敗しました。"
            log_error "URL: ${repo_url}/Release.key"
            rm -f "$gpg_key_file"
            return 1
        fi

        sudo mkdir -p /etc/apt/keyrings
        sudo rm -f "$keyring" \
            /etc/apt/trusted.gpg.d/shells_fish_release_3.gpg \
            /etc/apt/sources.list.d/shells_fish_release_3.list

        if ! gpg --batch --yes --dearmor < "$gpg_key_file" | sudo tee "$keyring" > /dev/null; then
            log_error "GPGキーの変換に失敗しました。"
            rm -f "$gpg_key_file"
            return 1
        fi
        rm -f "$gpg_key_file"
        sudo chmod 644 "$keyring"

        echo "deb [signed-by=${keyring}] ${repo_url}/ /" | sudo tee "$list_file" > /dev/null
        sudo chmod 644 "$list_file"

        if ! sudo apt update; then
            log_warn "パッケージリストの更新に警告がありました。"
        fi

        if sudo apt install -y fish; then
            log_success "openSUSE Build ServiceからのFishインストールが完了しました。"
            fish_installed=true
        else
            log_error "すべてのfishインストール方法が失敗しました。"
            return 1
        fi
    fi

    # eza のインストール試行
    install_eza_debian || true

    # 必須パッケージ
    local essential_packages=("git" "curl" "fontconfig")
    for package in "${essential_packages[@]}"; do
        sudo apt install -y "$package" 2>/dev/null || log_warn "$package のインストールに失敗しました。"
    done

    # オプションパッケージ（Raspberry Pi用に最適化）
    local optional_packages=("fzf")
    for package in "${optional_packages[@]}"; do
        sudo apt install -y "$package" 2>/dev/null || log_warn "$package のインストールに失敗しました（オプション）。"
    done

    ensure_ja_locale

    log_success "Raspberry Pi用のFishインストールが完了しました。"
}

# Fish パス取得と検証（複数の場所を確認）
get_fish_path() {
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "/usr/bin/fish"
        return 0
    fi

    local fish_path=""

    # 複数の場所を確認
    local possible_paths=(
        "/usr/bin/fish"
        "/usr/local/bin/fish"
        "/opt/homebrew/bin/fish"
        "/bin/fish"
    )

    # まず which で検索
    fish_path=$(which fish 2>/dev/null || echo "")

    if [[ -z "$fish_path" ]] || [[ ! -x "$fish_path" ]]; then
        # 既知のパスを順番に確認
        for path in "${possible_paths[@]}"; do
            if [[ -x "$path" ]]; then
                fish_path="$path"
                break
            fi
        done
    fi

    if [[ -z "$fish_path" ]]; then
        # dpkg で確認
        if command -v dpkg &>/dev/null; then
            fish_path=$(dpkg -L fish 2>/dev/null | grep "bin/fish$" | head -1 || echo "")
        fi
    fi

    if [[ -z "$fish_path" ]] || [[ ! -x "$fish_path" ]]; then
        log_error "fishコマンドが見つかりません。"
        log_error "インストールの確認:"
        log_error "  dpkg -l fish"
        log_error "  apt-cache policy fish"

        # 追加のデバッグ情報
        log_debug "PATH: $PATH"
        log_debug "which fish: $(which fish 2>&1 || echo 'not found')"
        log_debug "dpkg -L fish: $(dpkg -L fish 2>&1 || echo 'not installed')"

        return 1
    fi

    log_debug "Fish path found: $fish_path"
    echo "$fish_path"
}

# fishの動作確認
verify_fish_works() {
    local fish_path="$1"

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] fishの動作確認を実行する予定: $fish_path"
        return 0
    fi

    log_info "fishの動作確認を行っています..."

    # fishが実行可能か確認
    if [[ ! -x "$fish_path" ]]; then
        log_error "fishが実行可能ではありません: $fish_path"
        return 1
    fi

    # fishのバージョンを取得
    local fish_version
    fish_version=$("$fish_path" --version 2>&1) || {
        log_error "fishのバージョン取得に失敗しました。"
        log_error "出力: $fish_version"
        return 1
    }

    log_success "Fish動作確認完了: $fish_version"

    # 簡単なコマンド実行テスト
    if ! "$fish_path" -c "echo 'Fish is working'" &>/dev/null; then
        log_warn "fishの簡易テストに失敗しましたが、続行します。"
    fi

    return 0
}

# 現在のシェルを取得（クロスプラットフォーム対応）
get_current_shell() {
    local current_shell=""

    if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS用
        current_shell=$(dscl . -read "/Users/$USER" UserShell 2>/dev/null | awk '{print $2}' || echo "")
    else
        # Linux用
        current_shell=$(getent passwd "$USER" 2>/dev/null | cut -d: -f7 || echo "")
    fi

    echo "$current_shell"
}

# /etc/shellsへの追加
add_fish_to_shells() {
    local fish_path="$1"

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] /etc/shellsへのfish追加を実行する予定: $fish_path"
        return 0
    fi

    if ! grep -qxF "$fish_path" /etc/shells 2>/dev/null; then
        log_info "fishを/etc/shellsに追加しています..."
        echo "$fish_path" | sudo tee -a /etc/shells > /dev/null || {
            log_error "/etc/shellsへの追加に失敗しました。"
            return 1
        }
        log_success "fishを/etc/shellsに追加しました。"
    else
        log_info "fishは既に/etc/shellsに登録されています。"
    fi
}

# デフォルトシェルの変更
change_default_shell() {
    local fish_path="$1"

    if [[ "$SKIP_SHELL_CHANGE" == "true" ]]; then
        log_info "デフォルトシェルの変更をスキップします。"
        log_info "後で手動で変更する場合: chsh -s $fish_path"
        return 0
    fi

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] デフォルトシェルをfishに変更する予定: $fish_path"
        return 0
    fi

    local current_shell
    current_shell=$(get_current_shell)

    if [[ "$current_shell" == "$fish_path" ]]; then
        log_info "デフォルトシェルは既にfishに設定されています。"
        return 0
    fi

    # Raspberry Piでの警告
    local os_type
    os_type=$(detect_os)
    if [[ "$os_type" == "raspberrypi" ]]; then
        log_warn "========================================"
        log_warn "Raspberry Piでのシェル変更に関する注意:"
        log_warn "デフォルトシェルを変更すると、ログイン問題が"
        log_warn "発生する可能性があります。"
        log_warn "問題が発生した場合の復旧方法:"
        log_warn "  1. SDカードを別のPCにマウント"
        log_warn "  2. /etc/passwd を編集して /bin/bash に戻す"
        log_warn "========================================"

        if [[ "$AUTO_YES" != "true" ]]; then
            if ! prompt_yes "デフォルトシェルを変更しますか? (y/N): "; then
                log_info "シェル変更をスキップします。"
                log_info "fishを使用するには: exec fish"
                return 0
            fi
        fi
    fi

    log_info "デフォルトシェルをfishに変更しています..."

    if [[ "$OSTYPE" == "darwin"* ]]; then
        chsh -s "$fish_path" || {
            log_error "デフォルトシェルの変更に失敗しました。"
            return 1
        }
    else
        # Linux: chshが対話的になる場合があるため、sudo chshを使用
        sudo chsh -s "$fish_path" "$USER" || {
            log_error "デフォルトシェルの変更に失敗しました。"
            log_info "手動で変更する場合: sudo chsh -s $fish_path $USER"
            return 1
        }
    fi

    log_success "デフォルトシェルをfishに変更しました。"
}

# 設定ファイルのバックアップ
backup_existing_config() {
    if [[ -f "$CONFIG_FILE" ]]; then
        local backup_file="${CONFIG_FILE}.${BACKUP_SUFFIX}"

        if [[ "$DRY_RUN" == "true" ]]; then
            log_info "[DRY RUN] 既存の設定ファイルをバックアップする予定: $backup_file"
            return 0
        fi

        log_info "既存の設定ファイルをバックアップしています..."
        cp "$CONFIG_FILE" "$backup_file" || {
            log_error "設定ファイルのバックアップに失敗しました。"
            return 1
        }
        log_success "設定ファイルをバックアップしました: $backup_file"
    fi
}

# fisherとプラグインのインストール
install_fisher_and_plugins() {
    local fish_path="$1"

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] fisherとプラグインのインストールを実行する予定"
        return 0
    fi

    log_info "fisherをインストールしています..."

    # 設定ディレクトリの作成
    mkdir -p "$CONFIG_DIR/functions"
    mkdir -p "$CONFIG_DIR/completions"
    mkdir -p "$CONFIG_DIR/conf.d"

    # Fisher のインストール（最新の公式方法）
    local fisher_installed=false

    # 方法1: 公式のインストール方法
    log_debug "Fisher インストール方法1を試行..."
    if "$fish_path" -c 'curl -sL https://raw.githubusercontent.com/jorgebucaran/fisher/main/functions/fisher.fish | source && fisher install jorgebucaran/fisher' 2>&1 | tee -a "$LOG_FILE"; then
        if "$fish_path" -c "type -q fisher" 2>/dev/null; then
            log_success "fisherのインストールが完了しました。"
            fisher_installed=true
        fi
    fi

    if [[ "$fisher_installed" != "true" ]]; then
        log_warn "標準方法でのfisherインストールに失敗しました。代替方法を試行します..."

        # 方法2: 手動ダウンロード
        local fisher_file="$CONFIG_DIR/functions/fisher.fish"
        log_debug "Fisher インストール方法2を試行: $fisher_file"

        if safe_curl "https://raw.githubusercontent.com/jorgebucaran/fisher/main/functions/fisher.fish" "$fisher_file"; then
            if "$fish_path" -c "source $fisher_file && fisher install jorgebucaran/fisher" 2>&1 | tee -a "$LOG_FILE"; then
                if "$fish_path" -c "type -q fisher" 2>/dev/null; then
                    log_success "手動方式でfisherのインストールが完了しました。"
                    fisher_installed=true
                fi
            fi
        fi
    fi

    if [[ "$fisher_installed" != "true" ]]; then
        log_warn "fisherのインストールに失敗しました。"
        log_warn "後で手動でインストールしてください:"
        log_warn "  curl -sL https://raw.githubusercontent.com/jorgebucaran/fisher/main/functions/fisher.fish | source && fisher install jorgebucaran/fisher"
        return 0  # エラーにしない（fishは使える）
    fi

    log_info "fisherプラグインをインストールしています..."

    # プラグインリスト（最新の推奨プラグイン）- 軽量なものだけ
    local plugins=(
        "jethrokuan/z"
    )

    # fzfがインストールされている場合のみfzf.fishを追加
    if command -v fzf &>/dev/null; then
        plugins+=("PatrickF1/fzf.fish")
    fi

    local plugin_success=0
    local plugin_total=${#plugins[@]}

    for plugin in "${plugins[@]}"; do
        log_info "プラグインをインストール中: $plugin"
        if "$fish_path" -c "fisher install $plugin" 2>&1 | tee -a "$LOG_FILE"; then
            log_success "プラグイン $plugin のインストールが完了しました。"
            plugin_success=$((plugin_success + 1))
        else
            log_warn "プラグイン $plugin のインストールに失敗しました。"
        fi
    done

    # テーマのインストール
    log_info "テーマをインストールしています..."
    if "$fish_path" -c "fisher install oh-my-fish/theme-bobthefish" 2>&1 | tee -a "$LOG_FILE"; then
        log_success "theme-bobthefish のインストールが完了しました。"
    else
        log_warn "theme-bobthefish のインストールに失敗しました。デフォルトテーマを使用します。"
    fi

    log_success "fisherとプラグインのセットアップが完了しました ($plugin_success/$plugin_total プラグイン)。"
}

# fish設定ファイルの作成
create_fish_config() {
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] fish設定ファイルの作成を実行する予定"
        return 0
    fi

    log_info "fish設定ディレクトリを作成しています..."
    mkdir -p "$CONFIG_DIR" || {
        log_error "設定ディレクトリの作成に失敗しました。"
        return 1
    }

    log_info "fish設定ファイルを作成しています..."
    cat > "$CONFIG_FILE" << 'FISHCONFIG'
# ==============================================================================
# Fish Shell Configuration
# Generated by dotfiles_fish installation script
# ==============================================================================

# ------------------------------------
# Abbreviations (エイリアス)
# ------------------------------------

# ファイル操作 - eza (exaの後継) を優先使用
# --icons は Nerd Font が必要。有効化例は README を参照
if command -q eza
    abbr --add ll "eza -l --git"
    abbr --add la "eza -la --git"
    abbr --add lt "eza -la --git --tree --level=2"
    abbr --add ee "eza -aal --git"
else if command -q exa
    abbr --add ll "exa -l"
    abbr --add la "exa -la"
    abbr --add lt "exa -la --tree --level=2"
    abbr --add ee "exa -aal"
else
    abbr --add ll "ls -lh"
    abbr --add la "ls -lah"
    abbr --add lt "ls -lahR"
end

# bat (catの代替)
if command -q bat
    abbr --add cat "bat"
else if command -q batcat
    abbr --add cat "batcat"
end

# システム管理
switch (uname)
    case Darwin
        if command -q brew
            abbr --add update "brew update && brew upgrade"
        end
    case '*'
        if command -q apt
            abbr --add update "sudo apt update && sudo apt upgrade -y"
        end
end
abbr --add grep "grep --color=auto"
abbr --add .. "cd .."
abbr --add ... "cd ../.."
abbr --add .... "cd ../../.."

# Docker
abbr --add dps "docker ps"
abbr --add dpa "docker ps -a"
abbr --add docup "docker compose up -d"
abbr --add docdown "docker compose down"
abbr --add docfdown "docker compose down --rmi all --volumes --remove-orphans"
abbr --add doclog "docker compose logs -f"

# Git abbreviations
abbr --add gs "git status"
abbr --add ga "git add"
abbr --add gaa "git add --all"
abbr --add gc "git commit"
abbr --add gcm "git commit -m"
abbr --add gp "git push"
abbr --add gpl "git pull"
abbr --add gl "git log --oneline --graph"
abbr --add gd "git diff"
abbr --add gco "git checkout"
abbr --add gb "git branch"

# ------------------------------------
# Theme settings (bobthefish theme)
# ------------------------------------
set -g theme_display_date yes
set -g theme_date_format "+%F %H:%M"
set -g theme_display_git_default_branch yes
set -g theme_color_scheme dark
# 端末フォントに依存しない表示にする。Nerd Font 利用時は README の手順で切り替える
set -g theme_powerline_fonts no
set -g theme_nerd_fonts no
set -g theme_display_cmd_duration yes

# ------------------------------------
# FZF settings
# ------------------------------------
if command -q fzf
    set -gx FZF_DEFAULT_OPTS "--height 40% --layout=reverse --border"
end

# ------------------------------------
# Key bindings
# ------------------------------------
# Ctrl+R はここでは割り当てない。
# fzf.fish がある場合は履歴のあいまい検索、無い場合は Fish 標準のままにする。

# ------------------------------------
# Environment variables
# ------------------------------------
if command -q nvim
    set -gx EDITOR nvim
else if command -q vim
    set -gx EDITOR vim
else
    set -gx EDITOR nano
end

# ja_JP.UTF-8 が生成済みのときだけ使う。無い環境では警告の出ないロケールに落とす
if command -q locale
    if locale -a 2>/dev/null | string match -qiq 'ja_JP.utf*'
        set -gx LANG ja_JP.UTF-8
    else if locale -a 2>/dev/null | string match -qiq 'C.utf*'
        set -gx LANG C.UTF-8
    else if locale -a 2>/dev/null | string match -qiq 'en_US.utf*'
        set -gx LANG en_US.UTF-8
    end
end

# ------------------------------------
# PATH settings
# ------------------------------------
if test -d ~/.local/bin
    fish_add_path ~/.local/bin
end

if test -d ~/.cargo/bin
    fish_add_path ~/.cargo/bin
end

# ------------------------------------
# Utility functions
# ------------------------------------
function mkcd
    mkdir -p $argv[1] && cd $argv[1]
end

function backup
    cp $argv[1] $argv[1].backup.(date +%Y%m%d_%H%M%S)
end

# ==============================================================================
FISHCONFIG

    if [[ $? -ne 0 ]]; then
        log_error "設定ファイルの作成に失敗しました。"
        return 1
    fi

    log_success "fish設定ファイルを作成しました: $CONFIG_FILE"
}

# 確認プロンプト
confirm_installation() {
    local os_type="$1"

    if [[ "$AUTO_YES" == "true" || "$DRY_RUN" == "true" ]]; then
        return 0
    fi

    echo
    log_info "以下の処理を実行します:"
    echo "  - OS: $os_type"
    echo "  - Fish shell のインストール"
    echo "  - 関連パッケージのインストール"
    if [[ "$SKIP_SHELL_CHANGE" != "true" ]]; then
        echo "  - デフォルトシェルの変更"
    fi
    echo "  - Fisher とプラグインのインストール"
    echo "  - 設定ファイルの作成"
    echo

    if ! prompt_yes "続行しますか? (y/N): "; then
        log_info "インストールがキャンセルされました。"
        exit 0
    fi
}

# インストール検証
verify_installation() {
    local fish_path="${1:-}"

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] インストール結果の検証を実行する予定"
        return 0
    fi

    log_info "インストールの検証を行っています..."

    local errors=0

    # fish パスが渡されていない場合は取得
    if [[ -z "$fish_path" ]]; then
        fish_path=$(get_fish_path 2>/dev/null || echo "")
    fi

    # fish コマンドの確認
    if [[ -n "$fish_path" ]] && [[ -x "$fish_path" ]]; then
        local fish_version
        fish_version=$("$fish_path" --version 2>/dev/null || echo "unknown")
        log_success "Fish shell: $fish_version (パス: $fish_path)"
    else
        log_error "Fish shell が見つかりません"
        errors=$((errors + 1))
    fi

    # 設定ファイルの確認
    if [[ -f "$CONFIG_FILE" ]]; then
        log_success "設定ファイル: $CONFIG_FILE"
    else
        log_warn "設定ファイルが見つかりません: $CONFIG_FILE"
    fi

    # fisher の確認
    if [[ -n "$fish_path" ]] && "$fish_path" -c "type -q fisher" 2>/dev/null; then
        log_success "Fisher: インストール済み"
    else
        log_warn "Fisher がインストールされていない可能性があります"
    fi

    # eza/exa の確認
    if command -v eza &> /dev/null; then
        log_success "eza: インストール済み"
    elif command -v exa &> /dev/null; then
        log_info "exa: インストール済み"
    else
        log_info "eza/exa: 未インストール（標準lsを使用）"
    fi

    # /etc/shells の確認
    if [[ -n "$fish_path" ]] && grep -qxF "$fish_path" /etc/shells 2>/dev/null; then
        log_success "/etc/shells: fishが登録済み"
    else
        log_warn "/etc/shells: fishが登録されていません"
    fi

    # デフォルトシェルの確認
    local current_shell
    current_shell=$(get_current_shell)

    if [[ "$current_shell" == "$fish_path" ]]; then
        log_success "デフォルトシェル: fish"
    else
        log_info "デフォルトシェル: $current_shell (fishではありません)"
        log_info "fishを起動するには: exec fish"
    fi

    if [[ $errors -gt 0 ]]; then
        return 1
    fi

    return 0
}

# メイン関数
main() {
    local os_type
    local fish_path

    echo "=============================================================================="
    echo "Fish Shell Dotfiles Installation Script"
    echo "=============================================================================="
    echo

    # ロック取得
    acquire_lock

    # ログファイル初期化
    echo "=== Fish Shell Installation Log ===" > "$LOG_FILE"
    echo "Started at: $(date)" >> "$LOG_FILE"
    echo "" >> "$LOG_FILE"

    # システム情報の収集
    collect_system_info

    # 依存関係チェック
    check_dependencies

    # OS検出
    log_info "OSの検出を行っています..."
    os_type=$(detect_os)
    log_success "検出されたOS: $os_type"

    # アーキテクチャ
    local arch
    arch=$(detect_architecture)
    log_info "アーキテクチャ: $arch"

    case "$os_type" in
        "unsupported"|"unsupported_linux")
            log_error "サポートされていないOSです: $OSTYPE"
            log_error "サポートOS: macOS, Ubuntu, Debian, Raspberry Pi"
            exit 1
            ;;
    esac

    # 確認プロンプト
    confirm_installation "$os_type"

    # sudo権限チェック (macOS以外)
    if [[ "$os_type" != "macos" ]]; then
        check_sudo
    fi

    # OS別インストール
    case "$os_type" in
        "macos")
            install_fish_macos
            ;;
        "ubuntu")
            install_fish_ubuntu
            ;;
        "debian")
            install_fish_ubuntu
            ;;
        "raspberrypi")
            install_fish_raspberrypi
            ;;
    esac

    # Fish パス取得と検証
    fish_path=$(get_fish_path) || {
        log_error "fishのインストールに問題があります。"
        log_error "ログファイルを確認してください: $LOG_FILE"
        exit 1
    }
    log_success "Fish パス: $fish_path"

    # fishの動作確認
    verify_fish_works "$fish_path" || {
        log_error "fishが正常に動作していません。"
        exit 1
    }

    # /etc/shells への追加
    add_fish_to_shells "$fish_path"

    # デフォルトシェル変更
    change_default_shell "$fish_path"

    # 既存設定のバックアップ
    backup_existing_config

    # 設定ファイル作成（fisher より先に作成）
    create_fish_config

    # Fisher とプラグインのインストール
    install_fisher_and_plugins "$fish_path"

    # インストール検証
    echo
    verify_installation "$fish_path"

    # 完了メッセージ
    echo
    log_success "=============================================="
    log_success "Fish shell のインストールと設定が完了しました！"
    log_success "=============================================="
    echo
    echo "次のステップ:"
    echo "  1. 新しいターミナルを開く、または以下を実行:"
    echo "     exec $fish_path"
    echo "  2. fishの動作確認:"
    echo "     fish --version"
    echo "  3. 設定を確認:"
    echo "     fish_config"
    echo

    if [[ -f "${CONFIG_FILE}.${BACKUP_SUFFIX}" ]]; then
        echo "既存の設定はバックアップされました:"
        echo "  ${CONFIG_FILE}.${BACKUP_SUFFIX}"
        echo
    fi

    echo "ログファイル: $LOG_FILE"
    echo

    if [[ "$SKIP_SHELL_CHANGE" == "true" ]] || [[ "$(get_current_shell)" != "$fish_path" ]]; then
        echo "========================================"
        echo "fishをデフォルトシェルにするには:"
        echo "  chsh -s $fish_path"
        echo ""
        echo "または、bashから一時的にfishを使用:"
        echo "  exec fish"
        echo "========================================"
    fi
}

# コマンドライン引数の処理
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_usage
            exit 0
            ;;
        --dry-run)
            DRY_RUN=true
            log_info "ドライランモードで実行します。"
            ;;
        -y|--yes)
            AUTO_YES=true
            ;;
        -v|--verbose)
            VERBOSE=true
            log_info "詳細モードで実行します。"
            ;;
        --skip-shell-change)
            SKIP_SHELL_CHANGE=true
            log_info "デフォルトシェルの変更をスキップします。"
            ;;
        *)
            log_error "不明なオプション: $1"
            show_usage
            exit 1
            ;;
    esac
    shift
done

# メイン関数の実行
main "$@"

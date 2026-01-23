#!/bin/bash

# ==============================================================================
# Fish Shell Dotfiles Installation Script
# ==============================================================================
# このスクリプトはFish shellの自動インストールと設定を行います。
# 対応OS: macOS, Ubuntu/Debian, Raspberry Pi
# ==============================================================================

set -e  # エラー時に即座に終了
set -u  # 未定義変数の使用でエラー
set -o pipefail  # パイプラインのエラーを検出

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

    # ロックファイルの削除
    if [[ -f "$LOCK_FILE" ]]; then
        rm -f "$LOCK_FILE"
    fi

    # 一時ファイルの削除
    rm -f /tmp/fish_install_*.tmp 2>/dev/null || true

    if [[ $exit_code -ne 0 ]]; then
        log_error "スクリプトがエラーコード $exit_code で終了しました。"
        log_error "詳細はログファイルを確認してください: $LOG_FILE"
    fi

    exit $exit_code
}

# エラーハンドリング関数
handle_error() {
    local line_no=$1
    local error_code=${2:-1}
    log_error "スクリプトの実行中にエラーが発生しました。行: $line_no, エラーコード: $error_code"
    log_error "実行を中止します。"
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
  -h, --help      この使用方法を表示
  --dry-run       実際にインストールせずに実行予定の処理を表示
  -y, --yes       確認プロンプトをスキップ
  -v, --verbose   詳細なデバッグ出力を表示

環境変数:
  DRY_RUN=true    ドライランモードで実行
  VERBOSE=true    詳細モードで実行

例:
  $SCRIPT_NAME            # 通常のインストール
  $SCRIPT_NAME --dry-run  # ドライランモード
  $SCRIPT_NAME -y         # 確認をスキップしてインストール
  $SCRIPT_NAME -v         # 詳細モードでインストール
EOF
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
        log_error "以下のコマンドが見つかりません: ${missing_commands[*]}"
        log_error "これらのコマンドをインストールしてから再実行してください。"
        exit 1
    fi

    log_success "依存関係の確認が完了しました。"
}

# sudo権限の確認
check_sudo() {
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
    (while true; do sudo -n true; sleep 50; done) &
    SUDO_REFRESH_PID=$!
    log_debug "sudo更新プロセス開始: PID $SUDO_REFRESH_PID"

    log_success "sudo権限の確認が完了しました。"
}

# sudo更新プロセスの停止
stop_sudo_refresh() {
    if [[ -n "${SUDO_REFRESH_PID:-}" ]]; then
        kill "$SUDO_REFRESH_PID" 2>/dev/null || true
        log_debug "sudo更新プロセス停止: PID $SUDO_REFRESH_PID"
    fi
}

# OS検出関数
detect_os() {
    local os_type="unsupported"

    if [[ "$OSTYPE" == "darwin"* ]]; then
        os_type="macos"
    elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
        if [[ -f /etc/debian_version ]]; then
            # Raspberry Pi の堅牢な検出（NULLバイト対策）
            if [[ -f /etc/rpi-issue ]]; then
                os_type="raspberrypi"
            elif [[ -f /proc/device-tree/model ]]; then
                # NULLバイトを除去して検索
                if tr -d '\0' < /proc/device-tree/model 2>/dev/null | grep -qi "raspberry pi"; then
                    os_type="raspberrypi"
                else
                    os_type="debian"
                fi
            else
                # Ubuntu と Debian を区別
                if command -v lsb_release &>/dev/null; then
                    local distro
                    distro=$(lsb_release -is 2>/dev/null || echo "")
                    case "$distro" in
                        Ubuntu)
                            os_type="ubuntu"
                            ;;
                        Debian)
                            os_type="debian"
                            ;;
                        *)
                            os_type="debian"
                            ;;
                    esac
                else
                    os_type="debian"
                fi
            fi
        else
            os_type="unsupported_linux"
        fi
    fi

    echo "$os_type"
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

# macOS用インストール関数
install_fish_macos() {
    log_info "macOS用のFishインストールを開始します..."

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Homebrewの確認とFishのインストールを実行する予定"
        return 0
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

    # インストール後にfishが正しく利用可能か確認
    if ! command -v fish &> /dev/null; then
        log_error "fishのインストールは完了しましたが、fishコマンドが見つかりません。"
        log_error "PATHの更新が必要な可能性があります。新しいターミナルセッションで再試行してください。"
        return 1
    fi

    log_success "macOS用のFishインストールが完了しました。"
}

# ezaのインストール（Debian/Ubuntu用）
install_eza_debian() {
    log_info "ezaをインストールしています..."

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] ezaリポジトリの追加とインストールを実行する予定"
        return 0
    fi

    # GPGキーディレクトリの作成
    sudo mkdir -p /etc/apt/keyrings

    # GPGキーのダウンロードと追加
    local gpg_key_file="/tmp/eza_gierens_$$.gpg"
    if safe_curl "https://raw.githubusercontent.com/eza-community/eza/main/deb.asc" "$gpg_key_file"; then
        sudo gpg --dearmor -o /etc/apt/keyrings/gierens.gpg < "$gpg_key_file" 2>/dev/null || {
            # 既存のキーがある場合は削除して再作成
            sudo rm -f /etc/apt/keyrings/gierens.gpg
            sudo gpg --dearmor -o /etc/apt/keyrings/gierens.gpg < "$gpg_key_file"
        }
        rm -f "$gpg_key_file"

        # リポジトリの追加
        echo "deb [signed-by=/etc/apt/keyrings/gierens.gpg] http://deb.gierens.de stable main" | \
            sudo tee /etc/apt/sources.list.d/gierens.list > /dev/null

        # パーミッションの設定
        sudo chmod 644 /etc/apt/keyrings/gierens.gpg /etc/apt/sources.list.d/gierens.list

        # パッケージリストの更新とインストール
        sudo apt update
        if sudo apt install -y eza; then
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

    # Ubuntuの場合のみPPAを使用
    if [[ "$os_type" == "ubuntu" ]]; then
        log_info "Fish PPAを追加しています..."
        # software-properties-commonが必要
        sudo apt install -y software-properties-common 2>/dev/null || true

        if command -v apt-add-repository &>/dev/null; then
            sudo apt-add-repository ppa:fish-shell/release-3 -y 2>/dev/null || {
                log_warn "Fish PPAの追加に失敗しました。標準リポジトリを使用します。"
            }
            sudo apt update
        fi
    fi

    log_info "fishをインストールしています..."
    if ! sudo apt install -y fish; then
        log_error "fishのインストールに失敗しました。"
        return 1
    fi

    # fishインストール後の確認
    if ! command -v fish &> /dev/null; then
        log_error "fishのインストールは完了しましたが、fishコマンドが見つかりません。"
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

    log_info "パッケージリストを更新しています..."
    sudo apt update

    # まず標準リポジトリからfishのインストールを試行
    log_info "標準リポジトリからFishのインストールを試行しています..."
    local fish_installed=false

    if sudo apt install -y fish 2>/dev/null; then
        log_success "標準リポジトリからのFishインストールが完了しました。"
        fish_installed=true
    else
        log_warn "標準リポジトリからのインストールに失敗しました。openSUSE Build Serviceを試行します..."

        local debian_version
        debian_version=$(cut -d'.' -f1 < /etc/debian_version 2>/dev/null || echo "")

        if [[ -z "$debian_version" ]]; then
            log_error "Debianバージョンの取得に失敗しました。"
            return 1
        fi

        log_info "openSUSE Build ServiceからFishをインストールしています..."

        # GPGキーの取得と検証
        local gpg_key_file="/tmp/fish_opensuse_$$.key"
        if ! safe_curl "https://download.opensuse.org/repositories/shells:fish:release:3/Debian_${debian_version}/Release.key" "$gpg_key_file"; then
            log_error "GPGキーのダウンロードに失敗しました。"
            return 1
        fi

        gpg --dearmor < "$gpg_key_file" | sudo tee /etc/apt/trusted.gpg.d/shells_fish_release_3.gpg > /dev/null
        rm -f "$gpg_key_file"

        echo "deb http://download.opensuse.org/repositories/shells:/fish:/release:/3/Debian_${debian_version}/ /" | \
            sudo tee /etc/apt/sources.list.d/shells:fish:release:3.list > /dev/null

        if ! sudo apt update; then
            log_error "パッケージリストの更新に失敗しました。"
            return 1
        fi

        if sudo apt install -y fish; then
            log_success "openSUSE Build ServiceからのFishインストールが完了しました。"
            fish_installed=true
        else
            log_error "すべてのfishインストール方法が失敗しました。"
            return 1
        fi
    fi

    # fishインストール後の確認
    if ! command -v fish &> /dev/null; then
        log_error "fishのインストールは完了しましたが、fishコマンドが見つかりません。"
        return 1
    fi

    # eza のインストール試行
    install_eza_debian || true

    # 必須パッケージ
    local essential_packages=("git" "curl" "fontconfig")
    for package in "${essential_packages[@]}"; do
        sudo apt install -y "$package" 2>/dev/null || log_warn "$package のインストールに失敗しました。"
    done

    # オプションパッケージ（Raspberry Pi用に最適化）
    local optional_packages=("fzf" "bat" "fd-find")
    for package in "${optional_packages[@]}"; do
        sudo apt install -y "$package" 2>/dev/null || log_warn "$package のインストールに失敗しました（オプション）。"
    done

    log_success "Raspberry Pi用のFishインストールが完了しました。"
}

# Fish パス取得と検証
get_fish_path() {
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "/usr/bin/fish"
        return 0
    fi

    local fish_path
    fish_path=$(command -v fish 2>/dev/null || echo "")

    if [[ -z "$fish_path" ]]; then
        log_error "fishコマンドが見つかりません。"
        return 1
    fi

    if [[ ! -x "$fish_path" ]]; then
        log_error "fishが実行可能ではありません: $fish_path"
        return 1
    fi

    echo "$fish_path"
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
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] fisherとプラグインのインストールを実行する予定"
        return 0
    fi

    log_info "fisherをインストールしています..."

    # 設定ディレクトリの作成
    mkdir -p "$CONFIG_DIR/functions"

    # Fisher のインストール（最新の公式方法）
    local fisher_installed=false

    # 方法1: 公式のインストール方法
    if fish -c "curl -sL https://raw.githubusercontent.com/jorgebucaran/fisher/main/functions/fisher.fish | source && fisher install jorgebucaran/fisher" 2>/dev/null; then
        log_success "fisherのインストールが完了しました。"
        fisher_installed=true
    else
        log_warn "標準方法でのfisherインストールに失敗しました。代替方法を試行します..."

        # 方法2: 手動ダウンロード
        local fisher_file="$CONFIG_DIR/functions/fisher.fish"
        if safe_curl "https://raw.githubusercontent.com/jorgebucaran/fisher/main/functions/fisher.fish" "$fisher_file"; then
            if fish -c "source $fisher_file && fisher install jorgebucaran/fisher" 2>/dev/null; then
                log_success "手動方式でfisherのインストールが完了しました。"
                fisher_installed=true
            fi
        fi
    fi

    if [[ "$fisher_installed" != "true" ]]; then
        log_error "fisherのインストールに失敗しました。"
        log_error "手動でインストールしてください:"
        log_error "  curl -sL https://raw.githubusercontent.com/jorgebucaran/fisher/main/functions/fisher.fish | source && fisher install jorgebucaran/fisher"
        return 1
    fi

    # fisherが利用可能か確認
    if ! fish -c "type -q fisher" 2>/dev/null; then
        log_error "fisherがインストールされましたが、関数が見つかりません。"
        return 1
    fi

    log_info "fisherプラグインをインストールしています..."

    # プラグインリスト（最新の推奨プラグイン）
    local plugins=(
        "jorgebucaran/fisher"
        "PatrickF1/fzf.fish"
        "jethrokuan/z"
    )

    local plugin_success=0
    local plugin_total=${#plugins[@]}

    for plugin in "${plugins[@]}"; do
        log_info "プラグインをインストール中: $plugin"
        if fish -c "fisher install $plugin" 2>/dev/null; then
            log_success "プラグイン $plugin のインストールが完了しました。"
            plugin_success=$((plugin_success + 1))
        else
            log_warn "プラグイン $plugin のインストールに失敗しました。"
        fi
    done

    # テーマのインストール（bobthefish または tide）
    log_info "テーマをインストールしています..."
    if fish -c "fisher install oh-my-fish/theme-bobthefish" 2>/dev/null; then
        log_success "theme-bobthefish のインストールが完了しました。"
    else
        log_warn "theme-bobthefish のインストールに失敗しました。"
        log_info "代替テーマ(tide)を試行します..."
        fish -c "fisher install IlanCosman/tide@v5" 2>/dev/null || \
            log_warn "tideのインストールにも失敗しました。デフォルトテーマを使用します。"
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
if command -q eza
    abbr --add ll "eza -l --icons --git"
    abbr --add la "eza -la --icons --git"
    abbr --add lt "eza -la --icons --git --tree --level=2"
    abbr --add ee "eza -aal --icons --git"
else if command -q exa
    abbr --add ll "exa -l --icons"
    abbr --add la "exa -la --icons"
    abbr --add lt "exa -la --icons --tree --level=2"
    abbr --add ee "exa -aal --icons"
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
abbr --add update "sudo apt update && sudo apt upgrade -y"
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
abbr --add docexec "docker compose exec"

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
abbr --add gst "git stash"

# ------------------------------------
# Theme settings (bobthefish theme)
# ------------------------------------
set -g theme_display_date yes
set -g theme_date_format "+%F %H:%M"
set -g theme_display_git_default_branch yes
set -g theme_color_scheme dark
set -g theme_nerd_fonts yes
set -g theme_display_cmd_duration yes
set -g theme_title_display_process yes
set -g theme_title_display_path yes

# ------------------------------------
# FZF settings
# ------------------------------------
if command -q fzf
    set -gx FZF_DEFAULT_OPTS "--height 40% --layout=reverse --border --inline-info"

    # fd が利用可能な場合は使用
    if command -q fd
        set -gx FZF_DEFAULT_COMMAND "fd --type f --hidden --follow --exclude .git"
        set -gx FZF_CTRL_T_COMMAND "$FZF_DEFAULT_COMMAND"
    else if command -q fdfind
        set -gx FZF_DEFAULT_COMMAND "fdfind --type f --hidden --follow --exclude .git"
        set -gx FZF_CTRL_T_COMMAND "$FZF_DEFAULT_COMMAND"
    end
end

# ------------------------------------
# Key bindings
# ------------------------------------
function fish_user_key_bindings
    # fzf.fish プラグインが利用可能な場合は自動設定される
    # そうでない場合は、標準の履歴検索を使用
    if not functions -q fzf_key_bindings
        bind \cr history-search-backward
    end
end

# ------------------------------------
# Environment variables
# ------------------------------------
# エディタ設定
if command -q nvim
    set -gx EDITOR nvim
    set -gx VISUAL nvim
else if command -q vim
    set -gx EDITOR vim
    set -gx VISUAL vim
else
    set -gx EDITOR nano
    set -gx VISUAL nano
end

set -gx LANG ja_JP.UTF-8
set -gx LC_ALL ja_JP.UTF-8

# ------------------------------------
# PATH settings
# ------------------------------------
# ローカルbin
if test -d ~/.local/bin
    fish_add_path ~/.local/bin
end

# Cargo (Rust)
if test -d ~/.cargo/bin
    fish_add_path ~/.cargo/bin
end

# Go
if test -d ~/go/bin
    fish_add_path ~/go/bin
end

# Homebrew (macOS)
if test -d /opt/homebrew/bin
    fish_add_path /opt/homebrew/bin
end

# ------------------------------------
# Utility functions
# ------------------------------------

# ディレクトリ作成と移動を同時に
function mkcd
    mkdir -p $argv[1] && cd $argv[1]
end

# ファイルのバックアップを作成
function backup
    cp $argv[1] $argv[1].backup.(date +%Y%m%d_%H%M%S)
end

# 指定秒後にアラート
function timer
    set -l seconds $argv[1]
    set -l message $argv[2]
    if test -z "$message"
        set message "Timer finished!"
    end
    sleep $seconds && echo $message && if command -q notify-send
        notify-send "Timer" "$message"
    end
end

# ------------------------------------
# Fisher plugin management (参考)
# ------------------------------------
# fisher list                    # インストール済みプラグインを表示
# fisher install <plugin>        # プラグインをインストール
# fisher remove <plugin>         # プラグインを削除
# fisher update                  # すべてのプラグインを更新

# ==============================================================================
# Custom configurations can be added below
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
    echo "  - eza (モダンなls代替) のインストール"
    echo "  - その他の関連パッケージのインストール"
    echo "  - デフォルトシェルの変更"
    echo "  - Fisher とプラグインのインストール"
    echo "  - 設定ファイルの作成"
    echo

    read -rp "続行しますか? (y/N): " reply

    if [[ ! "$reply" =~ ^[Yy]$ ]]; then
        log_info "インストールがキャンセルされました。"
        exit 0
    fi
}

# インストール検証
verify_installation() {
    log_info "インストールの検証を行っています..."

    local errors=0

    # fish コマンドの確認
    if command -v fish &> /dev/null; then
        local fish_version
        fish_version=$(fish --version 2>/dev/null || echo "unknown")
        log_success "Fish shell: $fish_version"
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
    if fish -c "type -q fisher" 2>/dev/null; then
        log_success "Fisher: インストール済み"
    else
        log_warn "Fisher がインストールされていない可能性があります"
    fi

    # eza/exa の確認
    if command -v eza &> /dev/null; then
        log_success "eza: インストール済み"
    elif command -v exa &> /dev/null; then
        log_warn "exa: インストール済み（ezaへの移行を推奨）"
    else
        log_warn "eza/exa: 未インストール（標準lsを使用）"
    fi

    # デフォルトシェルの確認
    local current_shell
    current_shell=$(get_current_shell)
    local fish_path
    fish_path=$(command -v fish 2>/dev/null || echo "")

    if [[ "$current_shell" == "$fish_path" ]]; then
        log_success "デフォルトシェル: fish"
    else
        log_warn "デフォルトシェルはfishではありません: $current_shell"
        log_info "新しいターミナルセッションを開くか、以下を実行してください:"
        log_info "  chsh -s $fish_path"
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

    # 依存関係チェック
    check_dependencies

    # OS検出
    log_info "OSの検出を行っています..."
    os_type=$(detect_os)
    log_success "検出されたOS: $os_type"

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
            install_fish_ubuntu  # Debianも同じ処理
            ;;
        "raspberrypi")
            install_fish_raspberrypi
            ;;
    esac

    # sudo更新プロセスの停止
    if [[ "$os_type" != "macos" ]]; then
        stop_sudo_refresh
    fi

    # Fish パス取得と検証
    fish_path=$(get_fish_path) || exit 1
    log_success "Fish パス: $fish_path"

    # /etc/shells への追加
    add_fish_to_shells "$fish_path"

    # デフォルトシェル変更
    change_default_shell "$fish_path"

    # 既存設定のバックアップ
    backup_existing_config

    # 設定ファイル作成（fisher より先に作成）
    create_fish_config

    # Fisher とプラグインのインストール
    install_fisher_and_plugins

    # インストール検証
    echo
    verify_installation

    # 完了メッセージ
    echo
    log_success "=============================================="
    log_success "Fish shell のインストールと設定が完了しました！"
    log_success "=============================================="
    echo
    echo "次のステップ:"
    echo "  1. 新しいターミナルを開く、または以下を実行:"
    echo "     exec fish"
    echo "  2. 設定を確認:"
    echo "     fish_config"
    echo "  3. プラグインの確認:"
    echo "     fisher list"
    echo

    if [[ -f "${CONFIG_FILE}.${BACKUP_SUFFIX}" ]]; then
        echo "既存の設定はバックアップされました:"
        echo "  ${CONFIG_FILE}.${BACKUP_SUFFIX}"
        echo
    fi

    echo "ログファイル: $LOG_FILE"
    echo
    echo "問題が発生した場合は、バックアップから復元できます。"
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

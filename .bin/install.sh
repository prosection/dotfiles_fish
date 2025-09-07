#!/bin/bash

# ==============================================================================
# Fish Shell Dotfiles Installation Script
# ==============================================================================
# このスクリプトはFish shellの自動インストールと設定を行います。
# 対応OS: macOS, Ubuntu/Debian, Raspberry Pi
# ==============================================================================

set -e  # エラー時に即座に終了

# 設定可能な変数
readonly SCRIPT_NAME="$(basename "$0")"
readonly CONFIG_DIR="$HOME/.config/fish"
readonly CONFIG_FILE="$CONFIG_DIR/config.fish"
readonly BACKUP_SUFFIX="backup.$(date +%Y%m%d_%H%M%S)"
DRY_RUN=${DRY_RUN:-false}

# カラー出力用
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# ログ関数
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

# エラーハンドリング関数
handle_error() {
    log_error "スクリプトの実行中にエラーが発生しました。行: $1"
    log_error "実行を中止します。"
    exit 1
}

trap 'handle_error $LINENO' ERR

# 使用方法を表示
show_usage() {
    cat << EOF
使用方法: $SCRIPT_NAME [オプション]

オプション:
  -h, --help      この使用方法を表示
  --dry-run       実際にインストールせずに実行予定の処理を表示
  -y, --yes       確認プロンプトをスキップ

環境変数:
  DRY_RUN=true    ドライランモードで実行

例:
  $SCRIPT_NAME            # 通常のインストール
  $SCRIPT_NAME --dry-run  # ドライランモード
  $SCRIPT_NAME -y         # 確認をスキップしてインストール
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
    log_success "sudo権限の確認が完了しました。"
}

# OS検出関数
detect_os() {
    if [[ "$OSTYPE" == "darwin"* ]]; then
        echo "macos"
    elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
        if [[ -f /etc/debian_version ]]; then
            # Raspberry Pi の堅牢な検出
            if [[ -f /etc/rpi-issue ]] || grep -q "Raspberry Pi" /proc/device-tree/model 2>/dev/null; then
                echo "raspberrypi"
            else
                echo "ubuntu"
            fi
        else
            echo "unsupported_linux"
        fi
    else
        echo "unsupported"
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
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
        
        # Homebrewのパスを追加
        if [[ -f /opt/homebrew/bin/brew ]]; then
            eval "$(/opt/homebrew/bin/brew shellenv)"
        fi
    fi

    log_info "fishをインストールしています..."
    brew install fish || {
        log_error "fishのインストールに失敗しました。"
        return 1
    }
    
    # インストール後にfishが正しく利用可能か確認
    if ! command -v fish &> /dev/null; then
        log_error "fishのインストールは完了しましたが、fishコマンドが見つかりません。"
        log_error "PATHの更新が必要な可能性があります。新しいターミナルセッションで再試行してください。"
        return 1
    fi
    
    log_success "macOS用のFishインストールが完了しました。"
}

# Ubuntu/Debian用インストール関数
install_fish_ubuntu() {
    log_info "Ubuntu/Debian用のFishインストールを開始します..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] apt updateとFish及び関連パッケージのインストールを実行する予定"
        return 0
    fi
    
    log_info "パッケージリストを更新しています..."
    sudo apt-add-repository ppa:fish-shell/release-3 -y || {
        log_error "Fish PPAの追加に失敗しました。"
        return 1
    }
    
    sudo apt update || {
        log_error "パッケージリストの更新に失敗しました。"
        return 1
    }
    
    log_info "fishと関連パッケージをインストールしています..."
    sudo apt install fish git curl peco neovim fontconfig exa duf bat xsel -y || {
        log_error "パッケージのインストールに失敗しました。"
        return 1
    }
    
    # インストール後にfishが正しく利用可能か確認
    if ! command -v fish &> /dev/null; then
        log_error "fishのインストールは完了しましたが、fishコマンドが見つかりません。"
        log_error "PATHの更新が必要な可能性があります。新しいターミナルセッションで再試行してください。"
        return 1
    fi
    
    log_success "Ubuntu/Debian用のFishインストールが完了しました。"
}

# Raspberry Pi用インストール関数
install_fish_raspberrypi() {
    log_info "Raspberry Pi用のFishインストールを開始します..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Fishのインストールを実行する予定（標準リポジトリまたはopenSUSEリポジトリ）"
        return 0
    fi
    
    # まず標準リポジトリからのインストールを試行
    log_info "標準リポジトリからFishのインストールを試行しています..."
    sudo apt update
    
    if sudo apt install fish -y 2>/dev/null; then
        log_success "標準リポジトリからのFishインストールが完了しました。"
        
        # インストール後にfishが正しく利用可能か確認
        if command -v fish &> /dev/null; then
            log_success "Raspberry Pi用のFishインストールが完了しました。"
            return 0
        fi
    fi
    
    # 標準リポジトリで失敗した場合、openSUSE Build Serviceを試行
    log_warn "標準リポジトリからのインストールに失敗しました。openSUSE Build Serviceを試行します..."
    
    local debian_version
    debian_version=$(cat /etc/debian_version | cut -d'.' -f1)
    
    if [[ -z "$debian_version" ]]; then
        log_error "Debianバージョンの取得に失敗しました。"
        return 1
    fi
    
    log_info "openSUSE Build ServiceからFishをインストールしています..."
    echo "deb http://download.opensuse.org/repositories/shells:/fish:/release:/3/Debian_${debian_version}/ /" | sudo tee /etc/apt/sources.list.d/shells:fish:release:3.list > /dev/null
    
    if ! curl -fsSL "https://download.opensuse.org/repositories/shells:fish:release:3/Debian_${debian_version}/Release.key" | gpg --dearmor | sudo tee /etc/apt/trusted.gpg.d/shells_fish_release_3.gpg > /dev/null; then
        log_error "GPGキーの追加に失敗しました。"
        return 1
    fi
    
    if ! sudo apt update; then
        log_error "パッケージリストの更新に失敗しました。"
        return 1
    fi
    
    if ! sudo apt install fish -y; then
        log_error "openSUSEリポジトリからのfishインストールにも失敗しました。"
        log_error "手動でのインストールをお試しください:"
        log_error "  1. sudo apt update"
        log_error "  2. sudo apt install fish"
        return 1
    fi
    
    # インストール後にfishが正しく利用可能か確認
    if ! command -v fish &> /dev/null; then
        log_error "fishのインストールは完了しましたが、fishコマンドが見つかりません。"
        log_error "PATHの更新が必要な可能性があります。以下を実行してください:"
        log_error "  1. 新しいターミナルセッションを開く"
        log_error "  2. または、source ~/.bashrc を実行"
        log_error "  3. fish --version で確認"
        return 1
    fi
    
    log_success "Raspberry Pi用のFishインストールが完了しました。"
}

# Fish パス取得と検証
get_fish_path() {
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "/usr/bin/fish"  # ドライラン用のダミーパス
        return 0
    fi
    
    local fish_path
    fish_path=$(command -v fish 2>/dev/null)
    
    if [[ -z "$fish_path" ]]; then
        log_error "fishコマンドが見つかりません。"
        log_error "fishのインストールが完了していない可能性があります。"
        log_error "新しいターミナルセッションを開いて再実行するか、以下を実行してください:"
        log_error "  source ~/.bashrc  # または source ~/.profile"
        return 1
    fi
    
    if [[ ! -x "$fish_path" ]]; then
        log_error "fishが実行可能ではありません: $fish_path"
        return 1
    fi
    
    echo "$fish_path"
}

# /etc/shellsへの追加
add_fish_to_shells() {
    local fish_path="$1"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] /etc/shellsへのfish追加を実行する予定: $fish_path"
        return 0
    fi
    
    if ! grep -q "^$fish_path$" /etc/shells 2>/dev/null; then
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
    current_shell=$(getent passwd "$USER" | cut -d: -f7)
    
    if [[ "$current_shell" == "$fish_path" ]]; then
        log_info "デフォルトシェルは既にfishに設定されています。"
        return 0
    fi
    
    log_info "デフォルトシェルをfishに変更しています..."
    chsh -s "$fish_path" || {
        log_error "デフォルトシェルの変更に失敗しました。"
        return 1
    }
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
    
    # 最新のfisherインストール方法を使用（複数の方法を試行）
    local fisher_installed=false
    
    # 方法1: 最新の公式URL (推奨)
    if fish -c "curl -sL https://raw.githubusercontent.com/jorgebucaran/fisher/main/functions/fisher.fish | source && fisher install jorgebucaran/fisher" 2>/dev/null; then
        log_success "最新のfisherインストールが完了しました。"
        fisher_installed=true
    else
        log_warn "最新のfisher URLからのインストールに失敗しました。代替方法を試行します..."
        
        # 方法2: 手動ダウンロード方式
        fish -c "
            mkdir -p ~/.config/fish/functions
            curl -sL -o ~/.config/fish/functions/fisher.fish https://raw.githubusercontent.com/jorgebucaran/fisher/main/functions/fisher.fish
            source ~/.config/fish/functions/fisher.fish
            fisher install jorgebucaran/fisher
        " 2>/dev/null && {
            log_success "手動ダウンロード方式でfisherインストールが完了しました。"
            fisher_installed=true
        } || {
            log_warn "手動ダウンロード方式も失敗しました。古いURLを試行します..."
            
            # 方法3: 古いURL（フォールバック）
            fish -c "curl -sL git.io/fisher | source && fisher update" 2>/dev/null && {
                log_success "古いfisher URLでインストールが完了しました。"
                fisher_installed=true
            } || {
                log_error "すべてのfisherインストール方法が失敗しました。"
                log_error "手動でfisherをインストールしてください:"
                log_error "  1. curl -sL https://raw.githubusercontent.com/jorgebucaran/fisher/main/functions/fisher.fish -o ~/.config/fish/functions/fisher.fish"
                log_error "  2. fish"
                log_error "  3. fisher install jorgebucaran/fisher"
                return 1
            }
        }
    fi
    
    if [[ "$fisher_installed" != "true" ]]; then
        return 1
    fi
    
    # fisherがインストールされているか確認
    if ! fish -c "functions -q fisher" 2>/dev/null; then
        log_error "fisherのインストールは実行されましたが、fisher関数が見つかりません。"
        log_error "fish shellを再起動してから再実行してください。"
        return 1
    fi
    
    log_info "fisherプラグインをインストールしています..."
    
    # プラグインを一つずつインストールしてエラーハンドリング
    local plugins=("oh-my-fish/theme-bobthefish" "oh-my-fish/plugin-peco")
    local plugin_success=0
    local plugin_total=${#plugins[@]}
    
    for plugin in "${plugins[@]}"; do
        log_info "プラグインをインストール中: $plugin"
        if fish -c "fisher install $plugin" 2>/dev/null; then
            log_success "プラグイン $plugin のインストールが完了しました。"
            ((plugin_success++))
        else
            log_warn "プラグインのインストールに失敗しました: $plugin"
            log_warn "このプラグインをスキップして続行します。"
            # ネットワークの問題の可能性を示唆
            log_warn "ネットワーク接続やGitHubアクセスを確認してください。"
        fi
    done
    
    if [[ $plugin_success -eq $plugin_total ]]; then
        log_success "すべてのfisherプラグインのインストールが完了しました。"
    elif [[ $plugin_success -gt 0 ]]; then
        log_warn "fisherプラグインの一部（$plugin_success/$plugin_total）がインストールされました。"
    else
        log_warn "fisherプラグインのインストールに失敗しましたが、fisher自体は使用可能です。"
        log_warn "後で手動でプラグインをインストールできます:"
        log_warn "  fisher install oh-my-fish/theme-bobthefish"
        log_warn "  fisher install oh-my-fish/plugin-peco"
    fi
    
    log_success "fisherとプラグインのセットアップが完了しました。"
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
    cat > "$CONFIG_FILE" << 'EOL'
# ==============================================================================
# Fish Shell Configuration
# Generated by dotfiles_fish installation script
# ==============================================================================

# Abbreviations (エイリアス)
abbr ee "exa -aal --icons"
abbr ll "exa -l --icons"
abbr la "exa -la --icons"
abbr update "sudo apt update; sudo apt upgrade -y"
abbr docup "docker compose up -d"
abbr docdown "docker compose down"
abbr docfdown "docker compose down --rmi all --volumes --remove-orphans"
abbr doclog "docker compose logs -f"
abbr grep "grep --color=auto"
abbr ..  "cd .."
abbr ... "cd ../.."

# Git abbreviations
abbr gs "git status"
abbr ga "git add"
abbr gc "git commit"
abbr gp "git push"
abbr gl "git log --oneline"
abbr gd "git diff"

# Theme settings (bobthefish theme)
# Note: テーマが正しく表示されない場合は、以下を実行してください:
#   fisher install oh-my-fish/theme-bobthefish
set -g theme_display_date yes
set -g theme_date_format "+%F %H:%M"
set -g theme_display_git_default_branch yes
set -g theme_color_scheme dark
set -g theme_nerd_fonts yes

# Peco settings (for history search)
# Note: pecoが動作しない場合は、以下を実行してください:
#   fisher install oh-my-fish/plugin-peco
set fish_plugins theme peco

# Key bindings
function fish_user_key_bindings
    # Ctrl+r でヒストリ検索 (peco使用)
    # pecoが利用できない場合は、fish標準のCtrl+rを使用
    if command -q peco
        bind \cr peco_select_history
    else
        # 標準のfish履歴検索にフォールバック
        bind \cr history-search-backward
    end
end

# Fisher plugin management commands (参考)
# fisher list                    # インストール済みプラグインを表示
# fisher install <plugin>        # プラグインをインストール
# fisher remove <plugin>         # プラグインを削除
# fisher update                  # すべてのプラグインを更新

# Environment variables
set -gx EDITOR nvim
set -gx LANG ja_JP.UTF-8

# PATH settings
if test -d ~/.local/bin
    set -gx PATH ~/.local/bin $PATH
end

if test -d ~/.cargo/bin
    set -gx PATH ~/.cargo/bin $PATH
end

# Custom functions can be added below
# ==============================================================================
EOL

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
    echo "  - デフォルトシェルの変更"
    echo "  - Fisher と プラグインのインストール"
    echo "  - 設定ファイルの作成"
    echo
    
    read -p "続行しますか? (y/N): " -n 1 -r
    echo
    
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "インストールがキャンセルされました。"
        exit 0
    fi
}

# メイン関数
main() {
    local os_type
    local fish_path
    
    echo "=============================================================================="
    echo "Fish Shell Dotfiles Installation Script"
    echo "=============================================================================="
    
    # 依存関係チェック
    check_dependencies
    
    # OS検出
    log_info "OSの検出を行っています..."
    os_type=$(detect_os)
    log_success "検出されたOS: $os_type"
    
    case "$os_type" in
        "unsupported"|"unsupported_linux")
            log_error "サポートされていないOSです: $OSTYPE"
            log_error "サポートOS: macOS, Ubuntu/Debian, Raspberry Pi"
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
        "raspberrypi")
            install_fish_raspberrypi
            ;;
    esac
    
    # Fish パス取得と検証
    fish_path=$(get_fish_path)
    log_success "Fish パス: $fish_path"
    
    # /etc/shells への追加
    add_fish_to_shells "$fish_path"
    
    # デフォルトシェル変更
    change_default_shell "$fish_path"
    
    # 既存設定のバックアップ
    backup_existing_config
    
    # Fisher とプラグインのインストール
    install_fisher_and_plugins
    
    # 設定ファイル作成
    create_fish_config
    
    # 完了メッセージ
    echo
    log_success "Fish shell のインストールと設定が完了しました！"
    echo
    echo "次のステップ:"
    echo "  1. 新しいターミナルを開く、または以下を実行:"
    echo "     exec fish"
    echo "  2. 設定を確認:"
    echo "     fish_config"
    echo
    
    if [[ -f "${CONFIG_FILE}.${BACKUP_SUFFIX}" ]]; then
        echo "既存の設定はバックアップされました:"
        echo "  ${CONFIG_FILE}.${BACKUP_SUFFIX}"
        echo
    fi
    
    echo "問題が発生した場合は、バックアップから復元できます。"
    echo "詳細は README.md を参照してください。"
}

# コマンドライン引数の処理
AUTO_YES=false

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

#!/bin/bash

# OSの検出
if [[ "$OSTYPE" == "darwin"* ]]; then
    # macOS
    if ! command -v brew &> /dev/null; then
        echo "Homebrewをインストールしています..."
        /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    fi

    echo "fishをインストールしています..."
    brew install fish

    FISH_PATH=$(which fish)
elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
    # Debian/Ubuntu系
    if [[ -f /etc/debian_version ]]; then
        echo "fishをインストールしています..."
        sudo apt-add-repository ppa:fish-shell/release-3 -y
        sudo apt update
        sudo apt install fish git curl peco neovim fontconfig exa duf bat xsel -y
    # Raspberry Pi (Raspbian)
    elif [[ -f /etc/rpi-issue ]]; then
        echo "Raspberry Pi用にfishをインストールしています..."
        DEBIAN_VERSION=$(cat /etc/debian_version | cut -d'.' -f1)
        echo "deb http://download.opensuse.org/repositories/shells:/fish:/release:/3/Debian_${DEBIAN_VERSION}/ /" | sudo tee /etc/apt/sources.list.d/shells:fish:release:3.list
        curl -fsSL https://download.opensuse.org/repositories/shells:fish:release:3/Debian_${DEBIAN_VERSION}/Release.key | gpg --dearmor | sudo tee /etc/apt/trusted.gpg.d/shells_fish_release_3.gpg > /dev/null
        sudo apt update
        sudo apt install fish -y
    else
        echo "サポートされていないLinuxディストリビューションです。"
        exit 1
    fi

    FISH_PATH=$(which fish)
else
    echo "サポートされていないOSです。"
    exit 1
fi

# /etc/shellsにfishを追加
if ! grep -q "$FISH_PATH" /etc/shells; then
    echo "fishを/etc/shellsに追加しています..."
    echo "$FISH_PATH" | sudo tee -a /etc/shells
fi

# デフォルトシェルをfishに変更
echo "デフォルトシェルをfishに変更しています..."
chsh -s "$FISH_PATH"

# fisherをインストール
fish -c "curl -sL git.io/fisher | source && fisher update"

# fisher pluginをインストール
fish -c "fisher install oh-my-fish/theme-bobthefish"
fish -c "fisher install oh-my-fish/plugin-peco"

# fish設定ファイルの作成
mkdir -p ~/.config/fish
cat > ~/.config/fish/config.fish << EOL
# Alias
abbr ee "exa -aal --icons"
abbr update "sudo apt update;sudo apt upgrade -y"
abbr docup "docker compose up -d"
abbr docdown "docker compose down"
abbr docfdown "docker compose down --rmi all --volumes --remove-orphans"
abbr doclog "docker compose logs -f"

#view
set -g theme_display_date yes
set -g theme_date_format "+%F %H:%M"
set -g theme_display_git_default_branch yes
set -g theme_color_scheme dark

#peco setting
set fish_plugins theme peco

function fish_user_key_bindings
  bind \cr peco_select_history
end
EOL

echo "fishのインストールと設定が完了しました。新しいターミナルを開くか、'exec fish'を実行してfishシェルを使用開始してください。"

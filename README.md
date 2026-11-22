# dotfiles_fish

Fish shell の導入から設定までを、macOS・Ubuntu・Debian・Raspberry Pi OS で自動化するインストーラです。

設定ファイルはこのリポジトリには置かず、`.bin/install.sh` が `~/.config/fish/config.fish` を生成します。

## 目次

- [概要](#概要)
- [対応環境](#対応環境)
- [システム要件](#システム要件)
- [インストール方法](#インストール方法)
- [機能](#機能)
- [設定内容](#設定内容)
- [トラブルシューティング](#トラブルシューティング)
- [アンインストール](#アンインストール)
- [カスタマイズ](#カスタマイズ)
- [よくある質問](#よくある質問)

## 概要

このスクリプトは次をまとめて行います。

- Fish shell のインストール
- fisher と軽量なプラグイン、bobthefish テーマのセットアップ
- `eza` などの補助コマンドのインストール
- abbreviation と環境変数の設定
- 既存の `config.fish` のバックアップ

インストーラ自体は Bash で動きます。Fish が未導入の状態から実行できます。

## 対応環境

| OS | Fish の入手元 | 備考 |
|---|---|---|
| macOS | Homebrew | Apple Silicon / Intel |
| Ubuntu | `ppa:fish-shell/release-4` | 22.04 / 24.04 / 26.04 を想定。失敗時はディストリビューションのパッケージ |
| Debian | ディストリビューションのパッケージ | 12 (bookworm) / 13 (trixie) を想定 |
| Raspberry Pi OS | ディストリビューションのパッケージ | 標準リポジトリで失敗したときだけ openSUSE Build Service を使う。パッケージは Zero 向けに絞っている |

Raspberry Pi で標準リポジトリからのインストールに失敗した場合:

- Debian 12 以降: `shells:fish:release:4`
- Debian 11 以前: `shells:fish:release:3`

Ubuntu を Raspberry Pi に入れている場合は、Ubuntu として判定し Fish 4 の PPA を使います。

## システム要件

### 実行に必要なもの

- Bash
- `curl`
- `git`
- パッケージインストール用の sudo（macOS で Homebrew 済みの場合を除く）
- ネットワーク接続

`curl` と `git` が無く、`apt` が使える場合はスクリプトが入れます。

### インストールされるもの

| ツール | macOS | Ubuntu / Debian | Raspberry Pi OS | 用途 |
|---|---|---|---|---|
| fish | 入れる | 入れる | 入れる | シェル |
| fisher | 入れる | 入れる | 入れる | プラグイン管理 |
| bobthefish | 入れる | 入れる | 入れる | プロンプト |
| jethrokuan/z | 入れる | 入れる | 入れる | ディレクトリ移動 |
| fzf と fzf.fish | 入れる | 入れる | 入れる | `Ctrl+R` の履歴検索 |
| eza | 入れる | 入れる | 失敗したら `ls` | `ls` の代替 |
| bat | 入れる | 入れる | 入れない | `cat` の代替 |
| fd | 入れる | `fd-find` を `fd` として使えるようにする | 入れない | ファイル検索 |
| ripgrep | 入れる | 入れる | 入れない | 文字列検索 |

Raspberry Pi OS ではメモリの小さい機種を想定し、追加パッケージは `fzf` までにしています。neovim、peco、duf はインストールしません。`EDITOR` は、入っていれば `nvim`、次に `vim`、どちらも無ければ `nano` です。

Debian 系では署名検証用の `gpg` と、可能なら `ja_JP.UTF-8` ロケールも用意します。

## インストール方法

### 1. クローンして実行

```bash
git clone https://github.com/prosection/dotfiles_fish.git
cd dotfiles_fish
chmod +x .bin/install.sh
./.bin/install.sh
```

### 2. ワンライナー

端末から実行してください。確認は `/dev/tty` から読みます。

```bash
curl -fsSL https://raw.githubusercontent.com/prosection/dotfiles_fish/main/.bin/install.sh | bash
```

TTY が無い環境では `-y` を渡します。

```bash
curl -fsSL https://raw.githubusercontent.com/prosection/dotfiles_fish/main/.bin/install.sh | bash -s -- -y
```

### 3. オプション

```bash
# 変更を加えずに予定だけ表示する
./.bin/install.sh --dry-run

# 確認を省略する
./.bin/install.sh -y

# デフォルトシェルは変えない
./.bin/install.sh --skip-shell-change

# ヘルプ
./.bin/install.sh --help
```

`--dry-run` はパッケージのインストール、sudo、設定ファイルの書き込み、シェル変更を行いません。

再実行すると、現在の `config.fish` をタイムスタンプ付きでバックアップしたあと、生成した設定で上書きします。手で足した行は新しいファイルには残りません。

## 機能

- 既存の `config.fish` を `config.fish.backup.YYYYMMDD_HHMMSS` として残す
- `set -e`、`set -u`、`pipefail` で失敗を止める
- 同じユーザーでの多重起動をロックで防ぐ
- ログを `/tmp/fish_install_<ユーザー>.log` に残す
- Raspberry Pi OS では、デフォルトシェルを変える前に確認する

プロンプトは bobthefish を、Powerline フォントも Nerd Font も要らない設定で入れます。記号が欠ける状態で初回起動しないようにするためです。

## 設定内容

### Abbreviations

| 名前 | コマンド | 説明 |
|---|---|---|
| `ll` | `eza -l --git` | 一覧。eza が無ければ `ls -lh` |
| `la` | `eza -la --git` | 隠しファイルを含む一覧 |
| `lt` | `eza -la --git --tree --level=2` | 2階層のツリー |
| `ee` | `eza -aal --git` | 詳細一覧 |
| `cat` | `bat` または `batcat` | 入っているときだけ |
| `update` | macOS は `brew update && brew upgrade`、それ以外で apt があるときは `sudo apt update && sudo apt upgrade -y` | パッケージ更新 |
| `gs` / `ga` / `gc` | `git status` / `git add` / `git commit` | Git |
| `docup` / `docdown` | `docker compose up -d` / `docker compose down` | Docker Compose |
| `docfdown` | `docker compose down --rmi all --volumes --remove-orphans` | イメージとボリュームも削除する |

`docfdown` はデータを消します。

### キーバインド

`Ctrl+R` はスクリプト側では上書きしません。

- `fzf.fish` が入ったあとは、fzf による履歴検索
- 入っていないときは、Fish 本来の履歴検索

### 環境変数

- `EDITOR`: `nvim`、無ければ `vim`、無ければ `nano`
- `LANG`: `ja_JP.UTF-8` が有効なときだけそれにする。無ければ `C.UTF-8`、それも無ければ `en_US.UTF-8`
- `PATH`: `~/.local/bin` と `~/.cargo/bin` があれば追加

### プラグイン

- `jorgebucaran/fisher`
- `jethrokuan/z`
- `PatrickF1/fzf.fish`（`fzf` コマンドがあるとき）
- `oh-my-fish/theme-bobthefish`

## トラブルシューティング

### `curl: command not found`

```bash
# Ubuntu / Debian / Raspberry Pi OS
sudo apt update && sudo apt install curl

# macOS
xcode-select --install
```

### sudo のパスワードを求められる

```bash
sudo -v
./.bin/install.sh
```

### ワンライナーが確認のところで止まった、またはキャンセルされた

パイプの標準入力からは読みません。端末で実行するか、次のようにしてください。

```bash
curl -fsSL https://raw.githubusercontent.com/prosection/dotfiles_fish/main/.bin/install.sh | bash -s -- -y
```

### Fish がデフォルトシェルにならない

```bash
sudo chsh -s "$(which fish)" "$USER"
```

現在のセッションだけ切り替える場合:

```bash
exec fish
```

Raspberry Pi OS では、ログインできなくなったときの復旧手段を表示したあと、明示的に同意した場合だけシェルを変えます。`-y` を付けたときはこの確認も省略します。

### fisher のインストールに失敗した

```bash
curl -sL https://raw.githubusercontent.com/jorgebucaran/fisher/main/functions/fisher.fish | source
fisher install jorgebucaran/fisher
fisher install jethrokuan/z
fisher install PatrickF1/fzf.fish
fisher install oh-my-fish/theme-bobthefish
```

### eza が入らない

`gpg` が無い、リポジトリにそのアーキテクチャのパッケージが無い、といった理由で失敗しても、インストール全体は続行し、abbreviation は `ls` になります。ログは `/tmp/fish_install_<ユーザー>.log` です。

### 日本語ロケールの警告が出る

Debian 系では `ja_JP.UTF-8` の生成を試みます。失敗したときは、生成済みの UTF-8 ロケールに落とします。手動で有効にする場合:

```bash
sudo apt install -y locales
sudo locale-gen ja_JP.UTF-8
```

### アイコンや Powerline 字形を使いたい

端末に Nerd Font を設定したあと、`~/.config/fish/config.fish` で次のように変えます。

```fish
abbr --erase ll la lt ee
abbr --add ll "eza -l --icons --git"
abbr --add la "eza -la --icons --git"
abbr --add lt "eza -la --icons --git --tree --level=2"
abbr --add ee "eza -aal --icons --git"

set -g theme_powerline_fonts yes
set -g theme_nerd_fonts yes
```

フォントの入手先: https://www.nerdfonts.com/

### 設定を戻す

```bash
cp ~/.config/fish/config.fish.backup.YYYYMMDD_HHMMSS ~/.config/fish/config.fish
```

## アンインストール

```bash
# 1. ログインシェルを戻す
sudo chsh -s /bin/bash "$USER"

# 2. Fish の設定を消す
rm -rf ~/.config/fish ~/.local/share/fish

# 3. パッケージを消す
# Ubuntu / Debian / Raspberry Pi OS
sudo apt remove -y fish
# macOS
brew uninstall fish

# 4. このスクリプトが追加した APT ソースを消す場合
sudo add-apt-repository --remove ppa:fish-shell/release-4
sudo rm -f /etc/apt/sources.list.d/gierens.list /etc/apt/keyrings/gierens.gpg
sudo rm -f /etc/apt/sources.list.d/shells_fish_release_3.list \
           /etc/apt/sources.list.d/shells_fish_release_4.list \
           /etc/apt/keyrings/shells_fish_release_3.gpg \
           /etc/apt/keyrings/shells_fish_release_4.gpg \
           /etc/apt/trusted.gpg.d/shells_fish_release_3.gpg

# 5. /etc/shells から fish の行を消す
sudo sed -i '/fish/d' /etc/shells
```

macOS の `/etc/shells` は `sed -i` の書式が異なるため、エディタで該当行を削除してください。

## カスタマイズ

`~/.config/fish/config.fish` に足せます。

```fish
abbr myalias "your-command-here"
abbr work "cd ~/work; and ls"
```

テーマを変える例:

```fish
fisher list
fisher install IlanCosman/tide@v6
```

関数は `~/.config/fish/functions/myfunction.fish` に置けます。

```fish
function myfunction
    echo "Hello from my custom function!"
end
```

## よくある質問

### 既存の bash 設定は消えますか？

消えません。変更するのは Fish の設定、デフォルトシェル、パッケージです。`.bashrc` には触れません。

### 元のシェルに戻せますか？

`sudo chsh -s /bin/bash "$USER"` で bash に戻せます。

### すでに Fish の設定がある場合は？

`config.fish` はバックアップしてから置き換えます。fisher のプラグインディレクトリは削除しません。

### root で実行できますか？

一般ユーザーで実行し、必要なところだけ sudo を使ってください。

### Bash や Zsh から実行できますか？

インストーラは Bash スクリプトです。Bash から実行します。設定される対話シェルは Fish です。

### ネットワークは必要ですか？

必要です。パッケージとプラグインの取得に使います。

## ライセンス

MIT License。詳細は [LICENSE](LICENSE) を参照してください。

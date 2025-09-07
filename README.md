# dotfiles_fish

🐠 **Fish Shell用の自動セットアップスクリプト**

Fish shell の導入から設定まで、macOS・Ubuntu・Raspberry Pi で自動化します。

## 📋 目次

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

## 🎯 概要

このプロジェクトは、Fish shell（Friendly Interactive SHell）を簡単に導入・設定するための自動化スクリプトです。以下の作業を一括で行います：

- Fish shell のインストール
- 関連ツールとプラグインのセットアップ
- 美しいテーマとプロンプトの設定
- 便利なエイリアス（abbreviation）の設定
- 既存設定の安全なバックアップ

## 💻 対応環境

| OS | 検証状況 | 備考 |
|---|---|---|
| **macOS** | ✅ 完全対応 | Homebrew使用 |
| **Ubuntu/Debian** | ✅ 完全対応 | PPA使用 |
| **Raspberry Pi** | ✅ 完全対応 | openSUSE Build Service使用 |

### 検証済みバージョン
- macOS 12.0+ (Monterey以降)
- Ubuntu 20.04 LTS, 22.04 LTS
- Raspberry Pi OS (Debian 11/12 base)

## 🔧 システム要件

### 必須要件
- **curl**: HTTPリクエスト用
- **git**: バージョン管理とクローン用
- **sudo権限**: パッケージインストール用（macOS以外）

### 自動でインストールされるツール
- **fish**: メインシェル
- **fisher**: Fish用プラグインマネージャー
- **exa**: lsコマンドの改良版
- **peco**: インタラクティブフィルタリングツール
- **neovim**: 高機能エディタ
- **bat**: catコマンドの改良版
- **duf**: dfコマンドの改良版

## 🚀 インストール方法

### 1. クイックインストール（推奨）

```bash
# リポジトリをクローンして実行
git clone https://github.com/your-username/dotfiles_fish.git
cd dotfiles_fish
chmod +x .bin/install.sh
./.bin/install.sh
```

### 2. ワンライナーインストール

```bash
curl -fsSL https://raw.githubusercontent.com/your-username/dotfiles_fish/main/.bin/install.sh | bash
```

### 3. オプション付きインストール

```bash
# ドライランモード（実際にはインストールしない）
./.bin/install.sh --dry-run

# 確認をスキップして自動実行
./.bin/install.sh -y

# ヘルプを表示
./.bin/install.sh --help
```

## ✨ 機能

### 🛡️ 安全機能
- **既存設定の自動バックアップ**: タイムスタンプ付きでバックアップ
- **エラー時の即座停止**: `set -e`によるフェイルファスト
- **依存関係の事前チェック**: 必要コマンドの存在確認
- **sudo権限の確認**: 実行前の権限チェック
- **ドライランモード**: 実際の変更前の実行内容確認

### 🎨 テーマと見た目
- **bobthefish テーマ**: 美しく情報豊富なプロンプト
- **Nerd Fonts対応**: アイコン表示（要フォントインストール）
- **Git統合**: ブランチ名、変更状況の表示
- **日時表示**: プロンプトに現在日時を表示

### ⌨️ キーバインド
- `Ctrl+R`: peco による履歴検索
- 標準Fish キーバインド維持

## 📝 設定内容

### エイリアス（Abbreviations）

| エイリアス | コマンド | 説明 |
|---|---|---|
| `ee` | `exa -aal --icons` | 詳細ファイル一覧（アイコン付き） |
| `ll` | `exa -l --icons` | 長い形式一覧 |
| `la` | `exa -la --icons` | 隠しファイル含む一覧 |
| `update` | `sudo apt update; sudo apt upgrade -y` | システム更新（Ubuntu） |
| `gs` | `git status` | Gitステータス |
| `ga` | `git add` | Gitファイル追加 |
| `gc` | `git commit` | Gitコミット |
| `docup` | `docker compose up -d` | Docker Compose起動 |
| `docdown` | `docker compose down` | Docker Compose停止 |

### 環境変数
- `EDITOR`: neovim に設定
- `LANG`: ja_JP.UTF-8 に設定
- `PATH`: ~/.local/bin, ~/.cargo/bin を追加

## 🔧 トラブルシューティング

### よくあるエラーと解決方法

#### 1. `curl: command not found`
```bash
# Ubuntu/Debian
sudo apt update && sudo apt install curl

# macOS
xcode-select --install
```

#### 2. `sudo: a password is required`
```bash
# パスワードを入力してsudo権限を取得
sudo -v
./.bin/install.sh
```

#### 3. Fish がデフォルトシェルにならない
```bash
# 手動でシェル変更
sudo chsh -s $(which fish) $USER

# または現在のセッションのみ
exec fish
```

#### 4. Fisher/プラグインのインストールに失敗
```bash
# 最新のFisherを手動でインストール（推奨）
curl -sL https://raw.githubusercontent.com/jorgebucaran/fisher/main/functions/fisher.fish | source
fisher install jorgebucaran/fisher

# プラグインを手動でインストール
fisher install oh-my-fish/theme-bobthefish
fisher install oh-my-fish/plugin-peco

# 古いURL（フォールバック）
curl -sL git.io/fisher | source && fisher update

# 手動ダウンロード方式
mkdir -p ~/.config/fish/functions
curl -sL -o ~/.config/fish/functions/fisher.fish https://raw.githubusercontent.com/jorgebucaran/fisher/main/functions/fisher.fish
fish -c "source ~/.config/fish/functions/fisher.fish && fisher install jorgebucaran/fisher"
```

#### 5. テーマが正しく表示されない
```bash
# Nerd Fontsをインストール
# 各OS向けの手順はこちら: https://www.nerdfonts.com/
```

### 設定の復元

```bash
# 自動バックアップから復元
cp ~/.config/fish/config.fish.backup.YYYYMMDD_HHMMSS ~/.config/fish/config.fish

# 完全リセット（要注意）
rm -rf ~/.config/fish
```

## 🗑️ アンインストール

### Fish shell の完全削除

```bash
# 1. デフォルトシェルを戻す
sudo chsh -s /bin/bash $USER

# 2. 設定削除
rm -rf ~/.config/fish
rm -rf ~/.local/share/fish

# 3. パッケージ削除（Ubuntu）
sudo apt remove fish -y

# 3. パッケージ削除（macOS）
brew uninstall fish

# 4. /etc/shells から削除
sudo sed -i '/fish/d' /etc/shells
```

## 🎨 カスタマイズ

### 独自エイリアスの追加

`~/.config/fish/config.fish` を編集：

```fish
# 独自エイリアスを追加
abbr myalias "your-command-here"
abbr work "cd ~/work && ls"
```

### テーマの変更

```fish
# 利用可能なテーマを確認
fisher list

# 別のテーマをインストール
fisher install oh-my-fish/theme-agnoster
```

### 関数の追加

```fish
# ~/.config/fish/functions/myfunction.fish に保存
function myfunction
    echo "Hello from my custom function!"
end
```

## ❓ よくある質問

### Q: 既存のbash設定は削除されますか？
A: いいえ。このスクリプトはFishの設定のみを行い、既存のbash設定（.bashrc等）には触れません。

### Q: 元のシェルに戻せますか？
A: はい。`sudo chsh -s /bin/bash $USER`でbashに戻せます。

### Q: 他のFish設定と競合しますか？
A: 既存設定は自動でバックアップされるため、必要に応じて復元可能です。

### Q: ネットワーク接続が必要ですか？
A: はい。パッケージダウンロードとプラグインインストールに必要です。

### Q: root権限で実行できますか？
A: 推奨しません。一般ユーザーで実行し、必要時のみsudoを使用します。

### Q: Fish以外のシェルでも動作しますか？
A: このスクリプトはFish専用です。Bash/Zshでは動作しません。

### Q: fisherやプラグインのインストールに失敗します
A: 複数の原因が考えられます：
- **ネットワーク問題**: GitHubへのアクセスが制限されている
- **Fisher URL変更**: 最新のインストール方法を使用してください
- **手動解決**: `fisher install oh-my-fish/theme-bobthefish` で個別インストール
- **代替ツール**: oh-my-fish (omf) の使用も検討してください

### Q: テーマが表示されないか文字化けします
A: Nerd Fonts のインストールが必要です：
- macOS: `brew tap homebrew/cask-fonts && brew install font-hack-nerd-font`
- Ubuntu: `sudo apt install fonts-firacode fonts-powerline`
- 手動: https://www.nerdfonts.com/ からダウンロード

## 🤝 コントリビューション

バグ報告や機能提案は Issue でお知らせください。プルリクエストも歓迎です。

### 開発者向け

```bash
# テスト実行（Docker使用）
docker run -it ubuntu:latest bash
# ... スクリプトをテスト

# ドライラン確認
./.bin/install.sh --dry-run
```

## 📄 ライセンス

MIT License - 詳細は [LICENSE](LICENSE) ファイルを参照してください。

---

**🎉 Fish shell ライフをお楽しみください！ 🐠**

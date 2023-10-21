#!/bin/sh

# Check if the script is running with root privileges
if [ "$(id -u)" -ne 0 ]; then
    echo "このスクリプトは管理者権限（sudo）が必要です。sudoで実行してください。"
    exit 1
fi

# 引数の数をチェック
if [ $# -ne 1 ]; then
    echo "エラー: 取得したいドメイン名一つが指定されていません。"
    echo "使い方: sudo sh onion.sh <ドメイン名>"
    exit 1
fi

# 引数を変数に格納
domain="$1"

# Check if a package is installed and install if not
check_and_install_package() {
    local package_name="$1"
    local package_command="$2"

    if ! command -v "$package_command" > /dev/null 2>&1; then
        read -p "$package_name がインストールされていません。インストールしますか？（y/n）: " choice
        if [ "$choice" = "y" ]; then
            apt-get update
            apt-get install "$package_name"
            echo "$package_name をインストールしました。"
        else
            echo "$package_name のインストールがキャンセルされました。"
        fi
    fi
}

tor_reinstall() {
    echo "Torの設定が間違っている可能性があります"
    read -p "インストールし直しますか？ (y/n) : " choice
    if [ "$choice" = "y" ]; then
        # Uninstall Tor
        echo "Torをアンインストールします..."
        apt-get remove --purge tor -y
        apt-get autoremove -y
        echo "Torのアンインストールが完了しました。"

        # Install Tor
        echo "Torを再インストールします..."
        apt-get update
        apt-get install tor -y
        echo "Torの再インストールが完了しました。"

        echo "もう一度スクリプトを実行してください。"
        exit 1
    else
        echo "本サービスを利用していただきありがとうございました。"
	echo "Torをインストールしなおすことをおすすめします。"
 	exit 1
    fi
}

download_mkp224o() {
    git clone https://github.com/cathugger/mkp224o
    cd mkp224o
    ./autogen.sh
    ./configure
    make
    ./mkp224o
}

check_and_install_package "tor" "tor"
check_and_install_package "git" "git"

read -p "このディレクトリ内にディレクトリを作成してもよろしいですか？ (y/n) : " choice

if [ "$choice" != "y" ]; then
	exit 1
fi

# ファイルのパスを指定
file_path="/etc/tor/torrc"

# ファイルが存在するか確認
if [ ! -f "$file_path" ]; then
    tor_reinstall
fi

# 行番号を指定
start_line=71
end_line=72

# 行番号の範囲内で#を削除
sed -i "${start_line},${end_line}s/^#//" "$file_path"

echo "行番号 ${start_line} から ${end_line} の#を削除しました。"

#torを再起動してhidden_serviceを出現させる
service tor restart

#必要なもののダウンロード
apt install libsodium-dev autoconf

#mkp224oがすでにダウンロードされているか調べる
directory_path="mkp224o"

if [ -d "$directory_path" ]; then
    echo "mkp224oが既にダウンロードされているようです。"
    read -p "mkp224oをダウンロードしなおしますか？ (y/n) : " choice
    if [ "$choice" = "y" ]; then
        rm -rf mkp224o #rm -rfきもちいぃぃ！！
	    download_mkp224o
    fi
else
    download_mkp224o
fi

#独自onionドメイン取得
./mkp224o -d onion4869 -s -n 1 $domain
file_path="/var/lib/tor/hidden_service"
# ファイルが存在するか確認
if [ ! -d "$file_path" ]; then
    tor_reinstall
fi
rm /var/lib/tor/hidden_service/hostname /var/lib/tor/hidden_service/hs_ed25519_public_key /var/lib/tor/hidden_service/hs_ed25519_secret_key

#独自onionドメイン設定
base_directory="onion4869"

# 指定されたディレクトリ内で最初に見つかった.onionディレクトリを処理
onion_dir=$(find "$base_directory" -maxdepth 1 -type d -name "*.onion" -print -quit)

if [ -n "$onion_dir" ]; then
    onion_name=$(basename "$onion_dir")
    target_file="$onion_dir/hs_ed25519_secret_key"
    if [ -f "$target_file" ]; then
        install -o debian-tor -g debian-tor -m 400 "$target_file" "/var/lib/tor/hidden_service/hs_ed25519_secret_key"
        service tor restart
    else
        echo "$onion_name の hs_ed25519_secret_key が見つかりません。"
        tor_reinstall
    fi
else
    echo ".onion ディレクトリが見つかりません。お手数ですが最初からやり直してください。"
    echo "それでも治らない場合は開発者に問い合わせください"
fi

read -p "サーバーの設定をこちらでしますか？onionドメインは取得しているのでポートは80(http)、servernameはcat /var/lib/tor/hidden_service/hostnameで確認できます。 (y/n) : " choice

if [ "$choice" = "y" ]; then

    #apacheサーバーの設定をしてアクセスできるようにする
    check_and_install_package "apache2" "apache2"
    # ファイルのパスを指定
    file_path="/etc/apache2/sites-available/onion.conf"

    if [ -f "$file_path" ]; then
        echo "すみません$file_path に設定を記述しようとしたのですがもうあるようです。"
        read -p "上書きして良いですか？一度確認することを推奨します。 (y/n) : " choice

    fi

    web_file_path="/var/www/onion4869"

    touch $file_path

    # 追記する内容を指定
    additional_content="<VirtualHost *:80>\nServerName $onion_name\nDocumentRoot '$web_file_path'\n# その他の設定...各自で追加してください\n</VirtualHost>"

    # ファイルに内容を追記
    if [ -e "$file_path" ]; then
        echo "$additional_content" > "$file_path"
        echo "ファイル $file_path にサーバーの設定を記述しました。自分で編集してください。"
        echo "$web_file_path ディレクトリにサイトのコードを記述してください。"
        mkdir $web_file_path
        echo "hello world" > $web_file_path/index.html
        echo "今回はテストで $web_file_path/index.html に「hello world」と記述しました。"
        echo "\e[1;31mサイトを有効化する際はstart.shを実行してください。\e[0m"
    else
        echo "指定されたファイルが存在しません。"
    fi
else
    echo "サイトを表示する際はsystemctl start tor.serviceを忘れず実行してください。"
fi

echo "スクリプトの実行が完了しました！本サービスを利用していただきありがとうございます！"

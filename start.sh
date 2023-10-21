#!/bin/sh

echo "このスクリプトはonionドメインの設定ファイルをyuma4869のサービスを使用した人向けです"

if [ "$(id -u)" -ne 0 ]; then
    echo "このスクリプトは管理者権限（sudo）が必要です。sudoで実行してください。"
    exit 1
fi

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

check_and_install_package "tor" "tor"
check_and_install_package "apache2" "apache2"

a2ensite onion.conf
systemctl start tor.service
systemctl restart apache2.service

#!/bin/bash

# 检查是否以root用户运行脚本
if [ "$(id -u)" != "0" ]; then
    echo "此脚本需要以root用户权限运行。"
    echo "请尝试使用 'sudo -i' 命令切换到root用户，然后再次运行此脚本。"
    exit 1
fi

# 脚本保存路径
SCRIPT_PATH="$HOME/Warden.sh"

# 自动设置快捷键的功能
function check_and_set_alias() {
    local alias_name="war"
    local shell_rc="$HOME/.bashrc"

    # 对于Zsh用户，使用.zshrc
    if [ -n "$ZSH_VERSION" ]; then
        shell_rc="$HOME/.zshrc"
    elif [ -n "$BASH_VERSION" ]; then
        shell_rc="$HOME/.bashrc"
    fi

    # 检查快捷键是否已经设置
    if ! grep -q "$alias_name" "$shell_rc"; then
        echo "设置快捷键 '$alias_name' 到 $shell_rc"
        echo "alias $alias_name='bash $SCRIPT_PATH'" >> "$shell_rc"
        # 添加提醒用户激活快捷键的信息
        echo "快捷键 '$alias_name' 已设置。请运行 'source $shell_rc' 来激活快捷键，或重新打开终端。"
    else
        # 如果快捷键已经设置，提供一个提示信息
        echo "快捷键 '$alias_name' 已经设置在 $shell_rc。"
        echo "如果快捷键不起作用，请尝试运行 'source $shell_rc' 或重新打开终端。"
    fi
}

# 节点安装功能
function install_node() {

# 创建节点名称
read -p "请输入你想设置节点名称: " MONIKER

sudo apt update && sudo apt upgrade -y

# 安装构建工具
sudo apt -qy install curl git jq lz4 build-essential

# 安装 Go
rm -rf $HOME/go
sudo rm -rf /usr/local/go
curl -L https://go.dev/dl/go1.22.0.linux-amd64.tar.gz | sudo tar -xzf - -C /usr/local
echo 'export PATH=$PATH:/usr/local/go/bin:$HOME/go/bin' >> $HOME/.bash_profile
source $HOME/.bash_profile
go version


# 克隆项目仓库
cd $HOME
rm -rf wardenprotocol
git clone --depth 1 --branch v0.1.0 https://github.com/warden-protocol/wardenprotocol/
cd  wardenprotocol/warden/cmd/wardend
go build
chmod +x wardend
sudo mv wardend /usr/local/bin/


# 配置节点
wardend config keyring-backend os
wardend config chain-id alfama
wardend init $MONIKER

# 下载文件和地址簿
wget -O $HOME/.warden/config/genesis.json https://testnet-files.itrocket.net/warden/genesis.json
wget -O $HOME/.warden/config/addrbook.json https://testnet-files.itrocket.net/warden/addrbook.json


# 设置端口到config.toml file
sed -i.bak -e "s%:26658%:$PROXY_APP_PORT%g;
s%:26657%:$RPC_PORT%g;
s%:6060%:$PROF_LISTEN_ADDR%g;
s%:26656%:$P2P_PORT%g;
s%^external_address = \"\"%external_address = \"$(wget -qO- eth0.me):$P2P_PORT\"%;
s%:26660%:$PROMETHEUS_PORT%g" $HOME/.warden/config/config.toml

# 设置种子节点
SEEDS="ff0885377c44d58164f29d356b9d3d3a755c6213@warden-testnet-seed.itrocket.net:18656"
PEERS="f995c84635c099329bfaaa255389d63e052cb0ac@warden-testnet-peer.itrocket.net:18656,0be8cf6de2a01a6dc7adb29a801722fe4d061455@65.109.115.100:27060,f362d57aa6f78e035c8924e7144b7225392b921d@213.239.217.52:38656,9dfe1d1cc0a998351752a63ef8f5d88fb3464fc4@62.171.166.40:26656,89690e4abb78840ad172c8628a50570c9f484797@65.21.233.34:11656,2581489669e7a297fcd9e9d2c050a177b8d82010@85.10.201.125:56656,2d73e907c241774edf2068eebe583742c461aa58@80.65.211.143:11156,00c0b45d650def885fcbcc0f86ca515eceede537@152.53.18.245:15656,c7e29dad47a59d80d40d3daec3936cb9b8238744@185.225.191.31:26656,afede188ca76320b6fe7560560ede13ef63d8b8d@89.117.51.142:26686,ce520fdd9ad9d1d24fb5b3adcc065591f22fc770@65.108.206.118:46656"
sed -i -e "s/^seeds *=.*/seeds = \"$SEEDS\"/; s/^persistent_peers *=.*/persistent_peers = \"$PEERS\"/" $HOME/.warden/config/config.toml

# 设置 pruning
sed -i -e "s/^pruning *=.*/pruning = \"custom\"/" $HOME/.warden/config/app.toml
sed -i -e "s/^pruning-keep-recent *=.*/pruning-keep-recent = \"100\"/" $HOME/.warden/config/app.toml
sed -i -e "s/^pruning-interval *=.*/pruning-interval = \"50\"/" $HOME/.warden/config/app.toml

# 设置最小gas
sed -i 's|minimum-gas-prices =.*|minimum-gas-prices = "0.0025uward"|g' $HOME/.warden/config/app.toml
sed -i -e "s/prometheus = false/prometheus = true/" $HOME/.warden/config/config.toml
sed -i -e "s/^indexer *=.*/indexer = \"null\"/" $HOME/.warden/config/config.toml

# 下载快照
curl https://testnet-files.itrocket.net/warden/snap_warden.tar.lz4 | lz4 -dc - | tar -xf - -C $HOME/.warden

# 设置启动服务
sudo tee /etc/systemd/system/wardend.service > /dev/null <<EOF
[Unit]
Description=Warden daemon
After=network-online.target

[Service]
User=$USER
ExecStart=$(which wardend) start
Restart=always
RestartSec=3
LimitNOFILE=infinity

[Install]
WantedBy=multi-user.target
EOF


sudo systemctl daemon-reload
sudo systemctl enable wardend
sudo systemctl start wardend

    echo '====================== 安装完成 ==========================='
    
}

# 创建钱包
function add_wallet() {
    read -p "请输入钱包名称: " wallet_name
    wardend keys add "$wallet_name"
}

# 创建验证者
function add_validator() {
    pubkey=$(wardend comet show-validator)
    read -p "请输入您的钱包名称: " wallet_name
    read -p "请输入您想设置的验证者的名字: " validator_name
    read -p "请输入您的验证者详情（例如'吊毛资本'）: " details
    sudo tee ~/validator.json > /dev/null <<EOF
{
  "pubkey": ${PUBKEY},
  "amount": "100000ubbn",
  "moniker": "$validator_name",
  "details": "$details",
  "commission-rate": "0.1",
  "commission-max-rate": "0.2",
  "commission-max-change-rate": "0.01",
  "min-self-delegation": "1"
}

EOF
wardend tx staking create-validator validator.json --from $wallet_name  \
--chain-id=alfama \
--fees=500uward
--from=$wallet_name
}

# 导入钱包
function import_wallet() {
    read -p "请输入钱包名称: " wallet_name
    wardend keys add "$wallet_name" --recover
}

# 查询余额
function check_balances() {
    read -p "请输入钱包地址: " wallet_address
    wardend query bank balances "$wallet_address" 
}

# 查看节点同步状态
function check_sync_status() {
    wardend status | jq .sync_info
}

# 查看warden服务状态
function check_service_status() {
    systemctl status wardend
}

# 节点日志查询
function view_logs() {
    sudo journalctl -f -u wardend.service 
}

# 节点日志查询
function reward_test() {
read -p "请输入您的地址: " user_address
curl -X POST -H "Content-Type: application/json" --data "{\"address\": \"${user_address}\"}" https://faucet.alfama.wardenprotocol.org

}

# 卸载节点功能
function uninstall_node() {
    echo "你确定要卸载Warden 节点程序吗？这将会删除所有相关的数据。[Y/N]"
    read -r -p "请确认: " response

    case "$response" in
        [yY][eE][sS]|[yY]) 
            echo "开始卸载节点程序..."
            sudo systemctl stop wardend && sudo systemctl disable wardend && sudo rm /etc/systemd/system/wardend.service && sudo systemctl daemon-reload && rm -rf $HOME/.wardend && rm -rf warden && sudo rm -rf $(which wardend)

            echo "节点程序卸载完成。"
            ;;
        *)
            echo "取消卸载操作。"
            ;;
    esac
}

# 主菜单
function main_menu() {
    while true; do
    clear
    echo "脚本以及教程由推特用户大赌哥 @y95277777 编写，免费开源，请勿相信收费"
    echo "================================================================"
    echo "节点社区 Telegram 群组:https://t.me/niuwuriji"
    echo "节点社区 Telegram 频道:https://t.me/niuwuriji"
    echo "退出脚本，请按键盘ctrl c退出即可"
    echo "请选择要执行的操作:"
    echo "1. 安装节点"
    echo "2. 创建钱包"
    echo "3. 导入钱包"
    echo "4. 创建验证者"
    echo "5. 查看钱包地址余额"
    echo "6. 查看节点同步状态"
    echo "7. 查看当前服务状态"
    echo "8. 运行日志查询"
    echo "9. 卸载脚本"
    echo "10. 设置快捷键"  
    echo "11. 领水"  
    read -p "请输入选项（1-11）: " OPTION

    case $OPTION in
    1) install_node ;;
    2) add_wallet ;;
    3) import_wallet ;;
    4) add_validator ;;
    5) check_balances ;;
    6) check_sync_status ;;
    7) check_service_status ;;
    8) view_logs ;;
    9) uninstall_script ;;
    10) check_and_set_alias ;;  
    11) reward_test ;;  
    *) echo "无效选项。" ;;
    esac
    echo "按任意键返回主菜单..."
    read -n 1
done
}

# 显示主菜单
main_menu

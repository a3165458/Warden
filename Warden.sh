#!/bin/bash

# 检查是否以root用户运行脚本
if [ "$(id -u)" != "0" ]; then
    echo "此脚本需要以root用户权限运行。"
    echo "请尝试使用 'sudo -i' 命令切换到root用户，然后再次运行此脚本。"
    exit 1
fi

# 检查并安装 Node.js 和 npm
function install_nodejs_and_npm() {
    if command -v node > /dev/null 2>&1; then
        echo "Node.js 已安装"
    else
        echo "Node.js 未安装，正在安装..."
        curl -fsSL https://deb.nodesource.com/setup_16.x | sudo -E bash -
        sudo apt-get install -y nodejs
    fi

    if command -v npm > /dev/null 2>&1; then
        echo "npm 已安装"
    else
        echo "npm 未安装，正在安装..."
        sudo apt-get install -y npm
    fi
}

# 检查并安装 PM2
function install_pm2() {
    if command -v pm2 > /dev/null 2>&1; then
        echo "PM2 已安装"
    else
        echo "PM2 未安装，正在安装..."
        npm install pm2@latest -g
    fi
}

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
node_address="tcp://localhost:12457"
install_nodejs_and_npm
install_pm2

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
git clone --depth 1 --branch v0.3.0 https://github.com/warden-protocol/wardenprotocol
cd wardenprotocol
wget https://github.com/warden-protocol/wardenprotocol/releases/download/v0.3.0/wardend_Linux_x86_64.zip
unzip wardend_Linux_x86_64.zip
rm -rf wardend_Linux_x86_64.zip
chmod +x wardend
mv wardend /usr/local/go/bin



# 配置节点
wardend init mynode --chain-id buenavista-1

# 下载文件和地址簿
wget -O $HOME/.warden/config/genesis.json "https://raw.githubusercontent.com/warden-protocol/networks/main/testnets/buenavista/genesis.json"


# 设置种子节点
SEEDS=""
PEERS="61446070887838944c455cb713a7770b41f35ac5@37.60.249.101:26656,0be8cf6de2a01a6dc7adb29a801722fe4d061455@65.109.115.100:27060,8288657cb2ba075f600911685670517d18f54f3b@65.108.231.124:18656,dc0122e37c203dec43306430a1f1879650653479@37.27.97.16:26656"
sed -i -e "s/^seeds *=.*/seeds = \"$SEEDS\"/; s/^persistent_peers *=.*/persistent_peers = \"$PEERS\"/" $HOME/.warden/config/config.toml

# 设置 pruning
sed -i 's|^pruning *=.*|pruning = "custom"|g' $HOME/.warden/config/app.toml
sed -i 's|^pruning-keep-recent  *=.*|pruning-keep-recent = "100"|g' $HOME/.warden/config/app.toml
sed -i 's|^pruning-interval *=.*|pruning-interval = "10"|g' $HOME/.warden/config/app.toml
sed -i 's|^snapshot-interval *=.*|snapshot-interval = 0|g' $HOME/.warden/config/app.toml


# 设置最小gas
sed -i 's|^minimum-gas-prices *=.*|minimum-gas-prices = "0.025uward"|g' $HOME/.warden/config/app.toml
sed -i 's|^prometheus *=.*|prometheus = true|' $HOME/.warden/config/config.toml

# 配置端口
sed -i -e "s%^proxy_app = \"tcp://127.0.0.1:26658\"%proxy_app = \"tcp://127.0.0.1:12458\"%; s%^laddr = \"tcp://127.0.0.1:26657\"%laddr = \"tcp://127.0.0.1:12457\"%; s%^pprof_laddr = \"localhost:6060\"%pprof_laddr = \"localhost:12460\"%; s%^laddr = \"tcp://0.0.0.0:26656\"%laddr = \"tcp://0.0.0.0:12456\"%; s%^prometheus_listen_addr = \":26660\"%prometheus_listen_addr = \":12466\"%" $HOME/.warden/config/config.toml
sed -i -e "s%^address = \"tcp://localhost:1317\"%address = \"tcp://0.0.0.0:12417\"%; s%^address = \":8080\"%address = \":12480\"%; s%^address = \"localhost:9090\"%address = \"0.0.0.0:12490\"%; s%^address = \"localhost:9091\"%address = \"0.0.0.0:12491\"%; s%:8545%:12445%; s%:8546%:12446%; s%:6065%:12465%" $HOME/.warden/config/app.toml
echo "export Warden_RPC_PORT=$node_address" >> $HOME/.bash_profile
source $HOME/.bash_profile   

go install cosmossdk.io/tools/cosmovisor/cmd/cosmovisor@v1.5.0

# 下载快照
curl -L https://t-ss.nodeist.net/warden/snapshot_latest.tar.lz4 | lz4 -dc - | tar -xf - -C $HOME/.warden --strip-components 2

pm2 start wardend -- start && pm2 save && pm2 startup

    echo '====================== 安装完成 ==========================='
    
}

# 创建钱包
function add_wallet() {
    wardend keys add wallet
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
  "amount": "1000000uward",
  "moniker": "$validator_name",
  "details": "$details",
  "commission-rate": "0.1",
  "commission-max-rate": "0.2",
  "commission-max-change-rate": "0.01",
  "min-self-delegation": "1"
}

EOF
wardend tx staking create-validator validator.json --from $wallet_name --node $Warden_RPC_PORT \
--chain-id=buenavista-1 \
--fees=500uward
--from=$wallet_name

}

# 导入钱包
function import_wallet() {
    wardend keys add wallet --recover
}

# 查询余额
function check_balances() {
    read -p "请输入钱包地址: " wallet_address
    wardend query bank balances "$wallet_address" 
}

# 查看节点同步状态
function check_sync_status() {
    wardend status --node $Warden_RPC_PORT | jq .sync_info
}

# 查看warden服务状态
function check_service_status() {
    systemctl status wardend --node $Warden_RPC_PORT
}

# 节点日志查询
function view_logs() {
    sudo journalctl -f -u wardend.service 
}

# 领水
function reward_test() {
read -p "请输入您的地址: " user_address
curl -X POST -H "Content-Type: application/json" --data "{\"address\": \"${user_address}\"}" https://faucet.alfama.wardenprotocol.org

}

# 给自己地址验证者质押
function delegate_self_validator() {
read -p "请输入质押代币数量: " math
read -p "请输入钱包名称: " wallet_name
wardend tx staking delegate $(wardend keys show $wallet_name --bech val -a)  ${math}uward --from $wallet_name --chain-id=buenavista-1 --fees 500uward --node $Artela_RPC_PORT -y

}

# 卸载节点功能
function uninstall_node() {
    echo "你确定要卸载Warden 节点程序吗？这将会删除所有相关的数据。[Y/N]"
    read -r -p "请确认: " response

    case "$response" in
        [yY][eE][sS]|[yY]) 
            echo "开始卸载节点程序..."
            pm2 delete wardend && rm -rf $HOME/.wardend && rm -rf $HOME/.warden && sudo rm -rf $(which wardend) && rm -rf wardenprotocol

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
    echo "12. 给自己质押"  
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
    9) uninstall_node ;;
    10) check_and_set_alias ;;  
    11) reward_test ;;  
    12) delegate_self_validator ;;  
    *) echo "无效选项。" ;;
    esac
    echo "按任意键返回主菜单..."
    read -n 1
done
}

# 显示主菜单
main_menu

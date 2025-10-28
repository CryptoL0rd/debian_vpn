
# Установка
wget -O /root/repo.tar.gz https://codeload.github.com/CryptoL0rd/debian_vpn/tar.gz/refs/heads/main

tar -xzf /root/repo.tar.gz -C /root

cd /root/debian_vpn-main

# Запуск обновления до c debian 12 до debian 13 (требует перезагрузки)
chmod +x ./run-upgrade.sh
./run-upgrade.sh

# Установка впн
cd /root/debian_vpn-main
chmod +x ./install_xray.sh
./install_xray.sh


# Rоманды vpn

mainuser  
newuser  
rmuser   
sharelink 
changesni

nano /root/install_xray.sh
Вставляем install_xray.sh
Ctrl O, потом Enter, потом Ctrl X

nano /root/run-upgrade.sh
Вставляем run-upgrade.sh
Ctrl O, потом Enter, потом Ctrl X

либо просто перекидываем файлы

chmod +x /root/install_xray.sh
chmod +x /root/run-upgrade.sh
./run-upgrade.sh
перезагрузка сервера

chmod +x ./install_xray.sh
./install_xray.sh



# 1) скачать tar.gz архива ветки main
wget -O /root/repo.tar.gz https://codeload.github.com/CryptoL0rd/debian_vpn/tar.gz/refs/heads/main

# 2) распаковать (создаст /root/debian_vpn-main)
tar -xzf /root/repo.tar.gz -C /root
cd /root/debian_vpn-main

chmod +x ./run-upgrade.sh
./run-upgrade.sh

chmod +x ./install_xray.sh
./install_xray.sh




команды

mainuser  
newuser  
rmuser   
sharelink 
changesni

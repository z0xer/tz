```bash
#!/bin/bash

# === 1. обновление системы ===
# Сохраняем список всем пакетов до обновления
dpkg -l > /tmp/packages_before.txt

apt update -y
apt upgrade -y

# Сохраняем список пакетов после обновления
dpkg -l > /tmp/packages_after.txt

# чекаем что изменился 
diff /tmp/packages_before.txt /tmp/packages_after.txt


# === 2. настройка ssh ===
# Зачем: SSH — удаленно подключиься к серверу, надо её укрепить поменять дефолтный порт на какой-то другой

# Делаем бэкап конфига (на всякий случай)
cp /etc/ssh/sshd_config /etc/ssh/sshd_config.backup

# Меняем порт с 22 на 2222 
sed -i 's/#Port 22/Port 2222/' /etc/ssh/sshd_config

юзал sed -i 's/#' 's/'  так как не знал в каком состояние файл sshd_config, может он был в коментах или активно юзался  

# Запрещаем вход под root (тут поменяли так что бы на сервак не могли подключаться через root)
sed -i 's/#PermitRootLogin yes/PermitRootLogin no/' /etc/ssh/sshd_config
sed -i 's/PermitRootLogin yes/PermitRootLogin no/' /etc/ssh/sshd_config

# Отключаем вход по паролю (только по SSH-ключам — их не сбрутишь)
sed -i 's/#PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config
sed -i 's/PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config

# делаем рестарт что бы изменения применились
systemctl restart sshd


# === 3. настройка файрвола (UFW) ===
# Зачем: закрываем все порты кроме нужных
# Принцип: запретить всё, разрешить только то что надо

ufw default deny incoming   # запрещаем всё входящее траффикы , то есть снаружи никто не может к нам достучаться 
ufw default allow outgoing  # исходящее разрешаем (для apt update и тд) , а тут разрешаем машинке что бы у него был доступ к инету 
ufw allow 2222/tcp           # разрешаем ssh на новом порту
ufw allow 8080/tcp           # разрешаем порт веб-приложения
ufw --force enable           # включаем файрвол (--force чтобы не спрашивал)
ufw status                   # проверяем что получилось


# === 4. создаем обычного юзера ===
# Зачем: не работать под root, а дать юзеру sudo только на нужные команды, никто никогда не должен делать что то через root аккаунт, просто создать юзера и дать ему нужные доступа или роли и все 

# Создаём пользователя dev
# к этому юзеру можно подключиться только через ssh (noo password) , а -gecos тут просто что бы не информация об юзера было чисто 
adduser --disabled-password --gecos "" dev

# Даём ему ограниченный sudo (только управление сервисами и обновления)
cat > /etc/sudoers.d/dev << 'EOF'
dev ALL=(ALL) NOPASSWD: /usr/bin/systemctl, /usr/bin/docker, /usr/bin/journalctl, /usr/bin/apt-get update, /usr/bin/apt-get upgrade -y
EOF
chmod 440 /etc/sudoers.d/dev

# Создаём папку для SSH-ключей
# r-4 w-2 x-1
mkdir -p /home/dev/.ssh  # создаеться скрытая папка для юзера дев куда положим ключи а -р гарантиреут нам если даже папка создана то она не выдаст ошибку
chmod 700 /home/dev/.ssh # а тут даем пермишины то есть тут только сам владелец имеет доступ читать писать и делать execute (drwx-) а остальные ничего
touch /home/dev/.ssh/authorized_keys # создаеи файл 
chmod 600 /home/dev/.ssh/authorized_keys # сюда вот закидываем pub key и даем пермишин читать и писать
chown -R dev:dev /home/dev/.ssh # а тут менят пользователя так как все делал через рут если  не сделать этого то юзер не сможет подключиться через ssh 

echo "мой pub_key" > /home/dev/.ssh/authorized_keys


# === 5. авто обновления безопасности  ===
# Зачем: если вышел критический патч — он поставится сам, даже если ты спишь

apt install -y unattended-upgrades

# тут четсно в инете покапался как что сделать
# Включаем автообновления
cat > /etc/apt/apt.conf.d/20auto-upgrades << 'EOF'
APT::Periodic::Update-Package-Lists "1"; # тут как я понял он автоматический в фоновом режимме скачивает свежие пакеты каждый 1 день аналог sudo apt update
APT::Periodic::Unattended-Upgrade "1"; # он скачивает и устанавливает только патчи безопасности.
EOF

# ну тут тоже рестарт делаем что бы конфиги принялись
systemctl enable unattended-upgrades

# тут тоже в инете покапался 
# === 6. отключение не нужным сервисов ===
# Зачем: каждый лишний сервис — лишняя дыра для атаки или путь для атаки 

# посмотрел что было запущено  
systemctl list-units --type=service --state=running

# Отключаем то что серверу не нужно:

# cups — сервер печати (нет принтеров на сервере)
systemctl stop cups 2>/dev/null; systemctl disable cups 2>/dev/null; systemctl mask cups 2>/dev/null

# avahi-daemon — обнаружение устройств в сети (не нужно, уязвим)
systemctl stop avahi-daemon 2>/dev/null; systemctl disable avahi-daemon 2>/dev/null; systemctl mask avahi-daemon 2>/dev/null

# bluetooth — блютуз (на сервере его нет)
systemctl stop bluetooth 2>/dev/null; systemctl disable bluetooth 2>/dev/null; systemctl mask bluetooth 2>/dev/null


# === 7. fail2ban — защита от брутфорса ===
# Зачем: если кто-то 3 раза ввёл неправильный пароль — банит IP на 30 минут или на больше

apt install -y fail2ban

cat > /etc/fail2ban/jail.d/custom_ssh_rule.local << EOF
[sshd]
enabled = true
port = 2222
maxretry = 3
bantime = 1800
findtime = 600
EOF

systemctl enable fail2ban
systemctl restart fail2ban


# === 8. auditd — логирование действий ===
# Зачем: записываем кто что делал для расследования инцидентов

apt install -y auditd
#  обычно в директорий rules.d читает кастомные рулы 
cat > /etc/audit/rules.d/hardening.rules << 'EOF'
# Кто запускал sudo 
# дождаться конца её работы и записать, чем всё закончилось

-a always,exit -F path=/usr/bin/sudo -F perm=x -k sudo_usage

# Кто менял файл паролей
-w /etc/passwd -p wa -k passwd_changes

# Кто менял настройки SSH
-w /etc/ssh/sshd_config -p wa -k sshd_config_change
EOF

systemctl enable auditd
systemctl restart auditd


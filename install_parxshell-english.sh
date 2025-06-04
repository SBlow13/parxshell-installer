#!/bin/bash

set -e

echo "📦 Updating the system..."
sudo apt update && sudo apt upgrade -y

echo "🧱 Installation of the required packages..."
sudo apt install -y php php-cli php-mbstring php-xml php-bcmath php-curl php-mysql php-zip unzip curl git nginx mysql-server php-fpm supervisor

echo "🌐 Downloading the parxshell server project..."
sudo git clone https://gitlab.com/dividi/parx2.git /var/www/parx2
cd /var/www/parx2

echo "🔧 Installing Composer..."
curl -sS https://getcomposer.org/installer | php
sudo mv composer.phar /usr/local/bin/composer
composer install

echo "🔐 Configuring Laravel (.env + key..."
cp .env.example .env
php artisan key:generate

echo "🛡️ Configuring MySQL..."
DB_NAME="parxshell"
DB_USER="parxshell"
DB_PASS="parxshell"

sudo mysql <<EOF
CREATE DATABASE IF NOT EXISTS $DB_NAME;
CREATE USER IF NOT EXISTS '$DB_USER'@'localhost' IDENTIFIED BY '$DB_PASS';
GRANT ALL PRIVILEGES ON $DB_NAME.* TO '$DB_USER'@'localhost';
FLUSH PRIVILEGES;
EOF

sed -i "s/DB_DATABASE=.*/DB_DATABASE=$DB_NAME/" .env
sed -i "s/DB_USERNAME=.*/DB_USERNAME=$DB_USER/" .env
sed -i "s/DB_PASSWORD=.*/DB_PASSWORD=$DB_PASS/" .env

php artisan migrate

echo "🧑‍🏭 Creating permissions..."
sudo chown -R www-data:www-data /var/www/parx2
sudo chmod -R 755 /var/www/parx2

echo "🌐 Configuring NGINX..."
sudo tee /etc/nginx/sites-available/parxshell > /dev/null <<EOF
server {
    listen 80;
    server_name parxshell.local;

    root /var/www/parx2/public;
    index index.php index.html;

    access_log /var/log/nginx/parxshell_access.log;
    error_log  /var/log/nginx/parxshell_error.log;

    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    location ~ \.php\$ {
        include snippets/fastcgi-php.conf;
        fastcgi_pass unix:/var/run/php/php8.1-fpm.sock;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        include fastcgi_params;
    }

    location ~ /\.ht {
        deny all;
    }
}
EOF

sudo ln -sf /etc/nginx/sites-available/parxshell /etc/nginx/sites-enabled/parxshell
sudo nginx -t && sudo systemctl reload nginx

echo "🧩 Systemd Laravel Service (php artisan serve)..."
sudo tee /etc/systemd/system/parxshell.service > /dev/null <<EOF
[Unit]
Description=Laravel ParxShell Development Server
After=network.target

[Service]
Type=simple
User=www-data
Group=www-data
WorkingDirectory=/var/www/parx2
ExecStart=/usr/bin/php artisan serve --host=0.0.0.0 --port=8000
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reexec
sudo systemctl daemon-reload
sudo systemctl enable parxshell
sudo systemctl start parxshell

echo "⏱️ Supervisor - Laravel Schedule..."
sudo tee /etc/supervisor/conf.d/laravel-schedule.conf > /dev/null <<EOF
[program:laravel-schedule]
process_name=%(program_name)s
command=php /var/www/parx2/artisan schedule:run
directory=/var/www/parx2
autostart=true
autorestart=true
user=www-data
stdout_logfile=/var/log/supervisor/laravel-schedule.log
stderr_logfile=/var/log/supervisor/laravel-schedule-error.log
EOF

echo "📥 Supervisor - Laravel Worker..."
sudo tee /etc/supervisor/conf.d/laravel-worker.conf > /dev/null <<EOF
[program:laravel-worker]
process_name=%(program_name)s_%(process_num)02d
command=php /var/www/parx2/artisan queue:work --sleep=3 --tries=3
directory=/var/www/parx2
autostart=true
autorestart=true
user=www-data
numprocs=1
redirect_stderr=true
stdout_logfile=/var/log/supervisor/laravel-worker.log
EOF

sudo supervisorctl reread
sudo supervisorctl update
sudo supervisorctl start laravel-schedule
sudo supervisorctl start laravel-worker

echo "✅ Installation complete of ParxShell !"
echo "🌐 Access : http://$(hostname -I | awk '{print $1}'):8000"

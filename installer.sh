#!/bin/bash
# Exits on error, undefined variables
set -euo pipefail

# Simple print header
clear
echo "=================================================================="
echo "	Pterodactyl + Wings Made Easy - Danielius Navickas"
echo "			Ubuntu - Dec 2025"
echo "=================================================================="
echo

# Asks what to install?
echo "Choose Installation type:"
echo "1) Pterodactyl Panel"
echo "2) Wings Daemon"
echo
read -p "Enter your choice [1-2]: " choice

# Variable initialization 
DOMAIN=""
EMAIL=""
DB_NAME=""
DB_USER=""
DB_PASS=""
FRESH_INSTALL=""
SETUP_MAIL=""

# Pterodactyl Panel User Settings
if [[ $choice == "1" ]]; then
	clear
	echo "=== Pterodactyl Panel Configuration ==="
	echo
	
	# Domain input
	while true; do
		read -p "Enter your domain (e.g. panel.example.com): " DOMAIN
		[[ -n "$DOMAIN" ]] && break
		echo "Slow down, the domain cant be empty!"
	done

	# Email input
	while true; do
		read -p "Enter the admin email for the SSL certificate: " EMAIL
		[[ -n "$EMAIL" ]] && break
		echo "Slow down there! the email cant be left empty."
	done

	# Timezone input
	read -p "Enter your timezone (e.g. Europe/Stockholm) [UTC]: " TIMEZONE
	[[ -z "$TIMEZONE" ]] && TIMEZONE="UTC"

	# Database configuration
	read -p "Database name [panel]: " DB_NAME
	[[ -z "$DB_NAME" ]] && DB_NAME="panel"

	read -p "Database user [pterodactyl]: " DB_USER
	[[ -z "$DB_USER" ]] && DB_USER="pterodactyl"

	# Password input with auto generation if needed!
	while true; do
		read -s -p "Database password (leave empty to auto-generate it): " DB_PASS
		echo
		if [[ -z "$DB_PASS" ]]; then
			DB_PASS=$(openssl rand -base64 32 | tr -d "=+/")
			echo "Auto generated a strong password for you!"
			break
		elif [[ ${#DB_PASS} -ge 8 ]]; then
			break
		else
			echo "Your password must be at least 8 characters!!"
		fi
	done

	# The config summary
	clear
	echo "================================================"
	echo "	Quick Configuration Summary"
	echo "================================================"
	echo "Domain		: $DOMAIN"
	echo "Email		: $EMAIL"
	echo "Timezone		: $TIMEZONE"
	echo "DB Name		: $DB_NAME"
	echo "DB User		: $DB_USER"
	echo "DB Password	: (hidden)"
	echo "================================================"
	echo
	sleep 2
fi

# Main installation part right here..
case $choice in
	1)
		echo "Installing Pterodactyl..."

		# System updates and required dependencies :)
		sudo apt update
		sudo apt -y install software-properties-common curl apt-transport-https ca-certificates gnupg
		LC_ALL=C.UTF-8 add-apt-repository -y ppa:ondrej/php

		# Add redis repo
		curl -fsSL https://packages.redis.io/gpg | sudo gpg --dearmor -o /usr/share/keyrings/redis-archive-keyring.gpg
		echo "deb [signed-by=/usr/share/keyrings/redis-archive-keyring.gpg] https://packages.redis.io/deb $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/redis.list

		sudo apt update

		# PHP, MariaDB, Nginx, Redis and other intallation of stuff!
		sudo apt -y install php8.3 php8.3-{common,cli,gd,mysql,mbstring,bcmath,xml,fpm,curl,zip} mariadb-server nginx tar unzip git redis-server

		# Composer
		curl -sS https://getcomposer.org/installer | sudo php -- --install-dir=/usr/local/bin --filename=composer

		# Download and extract!
		mkdir -p /var/www/pterodactyl
		cd /var/www/pterodactyl

		curl -Lo panel.tar.gz https://github.com/pterodactyl/panel/releases/latest/download/panel.tar.gz
		tar -xzvf panel.tar.gz
		sudo chmod -R 755 storage/* bootstrap/cache/

		#MariaDB config
		echo "Creating MariaDB database and user..."
		sudo mariadb <<EOF
		CREATE DATABASE IF NOT EXISTS \`$DB_NAME\`;
		CREATE USER IF NOT EXISTS \`$DB_USER\`@'127.0.0.1' IDENTIFIED BY '$DB_PASS';
		CREATE USER IF NOT EXISTS \`$DB_USER\`@'localhost' IDENTIFIED BY '$DB_PASS';
		GRANT ALL PRIVILEGES ON \`$DB_NAME\`.* TO '$DB_USER'@'127.0.0.1';
		GRANT ALL PRIVILEGES ON \`$DB_NAME\`.* TO '$DB_USER'@'localhost';
		FLUSH PRIVILEGES;
EOF


		# Copy env files and apply DB settings
		cp .env.example .env

		sed -i "s/^DB_DATABASE=.*/DB_DATABASE=$DB_NAME/" .env
		sed -i "s/^DB_USERNAME=.*/DB_USERNAME=$DB_USER/" .env
		sed -i "s/^DB_PASSWORD=.*/DB_PASSWORD='$DB_PASS'/" .env

		# Install PHP dependencies
		COMPOSER_ALLOW_SUPERUSER=1 composer install --no-dev --optimize-autoloader

		# Pterodactyl panel post install configuration stuff :P
		# Fresh install?!?
		while true; do
			read -p "Is this a FRESH install? (y/n): " FRESH_INSTALL
			case "${FRESH_INSTALL,,}" in
				y|yes )
					FRESH_INSTALL=true
					break
					;;
				n|no )
					FRESH_INSTALL=false
					break
					;;
				* ) echo "please type y or n";;
			esac
		done

		# Run fresh install settings if you picked y/yes 
		if [[ $FRESH_INSTALL == true ]]; then
			echo "First time setup in progress..."
			php artisan key:generate --force
			php artisan migrate --seed --force
			php artisan p:user:make
		fi

		#Optional SMTP email setup!!
		clear
		while true; do
			read -p "Do you want to configure SMTP email now? (y/n): " SETUP_MAIL
			case "${SETUP_MAIL,,}" in
				y|yes)
					echo "Starting the mail setup"
					php artisan p:environment:mail
					break
					;;
				n|no)
					echo "Skipping email setup..."
					break
					;;
				*) echo "Please type y or n";;
			esac
		done

		# Scheduled task runner
		echo "Installing Crontab..."
		(crontab -l 2>/dev/null; echo "* * * * * php /var/www/pterodactyl/artisan schedule:run >> /dev/null 2>&1") | crontab -

		# Create systemd service for queue worker...
		echo "Installing queue worker service..."
		sudo tee /etc/systemd/system/pteroq.service > /dev/null <<EOF

		[Unit]
		Description=Pterodactyl Queue Worker
		After=network.target

		[Service]
		User=www-data
		Group=www-data
		Restart=always
		ExecStart=/usr/bin/php /var/www/pterodactyl/artisan queue:work --sleep=5 --tries=3 --queue=high,standard,low
		WorkingDirectory=/var/www/pterodactyl
		RestartSec=5

		[Install]
		WantedBy=multi-user.target
EOF

		sudo systemctl daemon-reload
		sudo systemctl enable --now pteroq.service

		# Fix permissions
		sudo chown -R www-data:www-data /var/www/pterodactyl
		;;
	2)
		echo "Installing Wings daemon..."

		# Create config directory and download the correct Wings binary
		sudo mkdir -p /etc/pterodactyl
		sudo curl -L -o /usr/local/bin/wings "https://github.com/pterodactyl/wings/releases/latest/download/wings_linux_$([[ "$(uname -m)" == "x86_64" ]] && echo "amd64" || echo "arm64")"
		
		# Make Wings executable
		sudo chmod u+x /usr/local/bin/wings

		# Wings systemd service is not enabled here, config.yml must be placed first!
		;;
	*)
		echo "Thats an invalid choice, exiting..."
		exit 2
		;;
esac

# Final message
clear
echo "================================================="
echo "	The installation is complete!"
echo "================================================="

if [[ $choice == "1" ]]; then
	echo "Panel URL: https://$DOMAIN"
	echo "Admin login: https://$DOMAIN/auth"
	echo "Default Credentials are in the panel (check .env)"
fi
if [[ $choice == "2" ]]; then
	echo
	echo " Next steps are as follows for the final Wings setup:"
	echo " 1. Log into your Pterodactyl Panel."
	echo " 2. Head over to admin, into nodes and create new node."
	echo " 3. Scroll down and download the generated config.yml"
	echo " 4. Place it at: /etc/pterodactyl/config.yml"
	echo
	echo " Once you're all done, start wings with:"
	echo " sudo systemctl restart wings"
	echo " or run it in debug mode if you wish:"
	echo " sudo wings --debug"
	echo
	echo " Wings will NOT start until the config.yml file is in place!!"
fi

echo
echo "==============================================="
echo "	    Made by Danielius Navickas"
echo "==============================================="












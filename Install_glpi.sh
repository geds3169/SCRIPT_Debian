#!/bin/sh

#############################################
# This script install GLPI
#
# For Debian 10 (buster)
#
# based on LAMP & Mariadb & phpMyAdmin
#
# Created by geds3169
#
# guilhemETkarine@hotmail.fr
#
# 29/01/2021
#
##############################################


######################
# Customize the shell
######################

#COLORS
# Reset
Color_Off='\033[0m'       # Text Reset

# Regular Colors
Red='\033[0;31m'          # Red
Green='\033[0;32m'        # Green
Yellow='\033[0;33m'       # Yellow
Purple='\033[0;35m'       # Purple
Cyan='\033[0;36m'         # Cyan

#######################
# Adveritssment
#######################

echo "$Cyan \n This script must be run as root, it requires root identification and the creation of a user who will use mariadb and phpmyadmin and apache $Color_Off"

echo "$Cyan \n If you dont use a graphical interface on the server, comment before running this script the line 238 and 239 and 240 $Color_Off"

###############################
# Check user running the script
###############################

if [ "$(whoami)" != 'root' ]; then
echo "$Red \n You are not root, This script must be run as root $Color_Off"
exit 1;
fi

################################################
# collect info admin and users and database name
################################################

echo "$Green \n Confirm the NAME of the ROOT :$Color_Off"
read root_name

echo "$Green \n Enter the password of the root to update / install / manage user Mariadb :$Color_Off"
read root_passwd

echo "$Purple \n Enter the NAME of the user who will use mariadb/phpmyadmin :$Color_Off"
read user_name

echo "$Purple \n Enter the PASSWORD of the user who will use mariadb/phpmyadmin :$Color_Off"
read user_passwd

echo "$Yellow \n Enter the name of the desired database CMS, exemple 'db_glpi' :$Color_Off"
read database_name

id -u $user_name &>/dev/null || useradd $user_name
adduser www-data $user_name

###############
# Update system
###############

echo "$Cyan \n Update the system and package $Color_Off"
apt update && apt upgrade -y
apt-get update && apt-get upgrade -y
apt-get install nano wget curl gnupg dnsutils openssl tree -y

#####################
# Install APACHE
#####################

echo "$Cyan \n Installing Apache and activating the service at startup $Color_Off"
apt install apache2 libapache2-mod-php -y
systemctl start apache2
systemctl enable apache2
if [[ ! "$(systemctl is-active apache2.service )" =~ "active" ]]
then
        echo "$Red \n Houston, we have a problem $Color_Off"
fi
apache2 -v

############################
# Install PHP
############################

echo "$Cyan \n Installing PHP and dependencies $Color_Off"
apt install php-mysqli php-mbstring php-curl php-gd php-simplexml php-intl php-ldap php-apcu php-xmlrpc php-cas php-zip php-bz2 php-ldap php-imap -y
php --version

############################
# Add rules firewall if exist
############################

echo "$Cyan \n Search for Firewall and create rules if they exist $Color_Off"
/usr/sbin/iptables status >/dev/null 2>&1
if [ $? = 0 ]; then
        echo "$Green \n Iptable firewall is running, we can create the inbound rules on ports 80 and 443 $Color_Off"
        iptables -I INPUT -p tcp --dport 80 -j ACCEPT
        iptables -I INPUT -p tcp --dport 443 -j ACCEPT
else
        echo "$Red \n Iptable firewall is not running or not installed $Color_Off"
fi

if systemctl status ufw.service >/dev/null; then
        echo "$Green \n ufw firewall is running, we can create the inbound rule for the protocols HTTP and HTTPS $Color_Off"
        ufw allow http
        ufw allow https
else
        echo "$Red \n ufw firewall is not running or not installed $Color_Off"
fi

################################
# change www-data to apache user
################################

echo "$Cyan \n We Change the owner for the directory web directory $Color_Off"
chown www-data:www-data /var/www/html/ -R

#################
# Install Mariadb
#################

echo "$Cyan \n Installing Mariadb and activating the service at startup $Color_Off"
apt install mariadb-server -y
if [[ ! "$(systemctl is-active mariadb.service )" =~ "active" ]]
then
        echo "Houston, we have a problem"
fi
systemctl start mariadb
systemctl enable mariadb

###############################
# Bypass secure mysql
###############################

echo "$Cyan \n Bypass the mysql secure configuration, remove root accounts that are accessible from outside the local host, remove anonymous-user accounts, remove the test database $Color_Off"
set -e
mysql_secure_installation << EOF
n
$root_passwd
$root_passwd
y
y
y
y
y
EOF

##################################################
# Check if user and  database exist if not, create
##################################################

echo "$Cyan \n We see if the user, database exists otherwise we create it $Color_Off"
set -e
mysql -u$root_name -p$root_passwd << EOF
CREATE USER IF NOT EXISTS '$user_name'@'localhost' IDENTIFIED BY '$user_passwd';
CREATE DATABASE IF NOT EXISTS $database_name;
GRANT ALL PRIVILEGES ON *.* TO '$user_name'@'localhost' IDENTIFIED BY '$user_passwd';
GRANT ALL PRIVILEGES ON $database_name.* TO '$user_name'@'localhost';
FLUSH PRIVILEGES;
EOF

#################################################
# Download phpMyAdmin / create directory / unpack
#################################################

echo "$Cyan \n Downloading phpmyadmin package from source and unpackage on the final directory web server $Color_Off"
wget -P /root/tmp/ https://www.phpmyadmin.net/downloads/phpMyAdmin-latest-all-languages.tar.gz
mkdir /var/www/html/phpmyadmin
cd /root/tmp/
tar xvf phpMyAdmin-latest-all-languages.tar.gz --strip-components=1 -C /var/www/html/phpmyadmin

############################################################
# Create a random passphrase, see phpmyadmin blowfish_secret
############################################################

echo "$Cyan \n It is required to enter a unique 32 characters long string to fully use the blowfish algorithm used by phpMyAdmin, \nthus preventing the message ERROR: The configuration file now needs a secret passphrase (blowfish_secret), \n it will be auto generated by openssl $Color_Off" 
randomBlowfishSecret=$(openssl rand -base64 32)
sed -e "s|cfg\['blowfish_secret'\] = ''|cfg['blowfish_secret'] = '$randomBlowfishSecret' |" /var/www/html/phpmyadmin/config.sample.inc.php > /var/www/html/phpmyadmin/config.inc.php

######################################
# Change permission of the config file
######################################

echo "$Cyan \n We secure the configuration file by changing its rights $Color_Off"
chmod 660 /var/www/html/phpmyadmin/config.inc.php

############################
# Change owner of phpmyadmin
############################

echo "$Cyan \n We change the owner phpmyadmin directory $Color_Off"
chown www-data:www-data /var/www/html/phpmyadmin -R

################################
# Download GLPI
################################

echo "$Cyan \n Downloading GLPI from source and unpackage on the final directory web server $Color_Off"
wget -P /tmp/ https://github.com/glpi-project/glpi/releases/download/9.5.2/glpi-9.5.2.tgz
mkdir /var/www/html/glpi
cd /tmp/
tar xvf glpi-9.5.2.tgz --strip-components=1 -C /var/www/html/glpi

chown -R www-data /var/www/html

################################
# Download glpi.conf for apache
################################

cd /etc/apache2/sites-available/
wget https://raw.githubusercontent.com/geds3169/SCRIPT_Debian/main/glpi.conf

a2ensite glpi.conf

################################
# Restart Apache and open links
################################

echo "$Cyan \n Finally we restart the Apache service $Color_Off"
systemctl restart apache2

# doesn't work without graphical environment
xdg-open http://127.0.0.1
xdg-open http://127.0.0.1/glpi
xdg-open http://127.0.0.1/phpmyadmin

###########################################
# Clean directory created during the script
###########################################

echo "$Cyan \n Clean up downloaded files and directories created during installation $Color_Off" 
cd ..
rm -R  /root/tmp/

echo "$Green \n end of the script, now you can configure https if you want, but manually ;) $Color_Off"

exit 0



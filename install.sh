#!/bin/bash
echo
echo "************************************************************************************"
echo "************************************************************************************"
echo "** Install Mail server on Ubuntu with Dovecot, postfix, SpamAssassin and MySQL"
echo "************************************************************************************"
echo "************************************************************************************"
echo "This installation is following the tutorial of Thomas Leister found here:"
echo "https://thomas-leister.de/mailserver-unter-ubuntu-16.04/"
echo
echo "You should use this setup on a fresh installation of Ubuntu"
echo
read -p "Press Enter to continue or Ctrl+C to abort"

echo
echo "************************************************************************************"
echo "** Switching to root Context, you might need to enter your user password."
sudo -s
echo

echo "************************************************************************************"
echo "** Bringing the environment up to date."
echo
apt-get -y update
apt-get -y upgrade
apt-get -y dist-upgrade
apt-get -y autoremove

echo "************************************************************************************"
echo "** Setting the hostname and hosts file."
echo
echo "tuxmail" > /etc/hostname
cp ./conf/hosts /etc/hosts
echo $(hostname -f) > /etc/mailname

echo "************************************************************************************"
echo "** Setting up a DH parameter file."
echo
mkdir /etc/myssl
FILE=`mktemp` ; openssl dhparam 2048 -out $FILE && mv -f $FILE /etc/myssl/dh2048.pem

echo "************************************************************************************"
echo "** Install Lets Encrypt Certbot."
echo
apt -y install git
git clone https://github.com/certbot/certbot
mv certbot ~/

echo "************************************************************************************"
echo "** Install local instance of MySQL and setup virtual mail user."
echo "** You might need to enter the MySQL root password twice. Make sure it's the same."
echo
echo -n "Please enter password for local MySQL root [Enter]: "
read pass_mysql
apt-get -y install mysql-server
cat ./sql/creat_vmail.sql | mysql -u root --password=$pass_mysql
mkdir /var/vmail
adduser --disabled-login --disabled-password --home /var/vmail vmail
mkdir /var/vmail/mailboxes
mkdir -p /var/vmail/sieve/global
chown -R vmail /var/vmail
chgrp -R vmail /var/vmail
chmod -R 770 /var/vmail

echo "************************************************************************************"
echo "** Install Dovecot."
echo
apt-get -y install dovecot-core dovecot-imapd dovecot-lmtpd dovecot-mysql dovecot-sieve dovecot-managesieved dovecot-antispam
systemctl stop dovecot
rm -r /etc/dovecot/*
cp ./conf/dovecot.conf /etc/dovecot/
cp ./conf/dovecot-sql.conf /etc/dovecot/
chmod 770 /etc/dovecot/dovecot-sql.conf
cp ./conf/spampipe.sh /var/vmail/
chown vmail:vmail /var/vmail/spampipe.sh
chmod u+x /var/vmail/spampipe.sh
cp ./conf/spam-global.sieve /var/vmail/sieve/global/

echo "************************************************************************************"
echo "** Install Postfix. Please select <No configuration> during installation."
echo
read -p "Press Enter to continue"
echo
apt-get -y install postfix postfix-mysql
systemctl stop postfix
rm -r /etc/postfix/sasl
rm /etc/postfix/master.cf
cp ./conf/main.cf /etc/postfix/
cp ./conf/master.cf /etc/postfix/
cp ./conf/submission_header_cleanup /etc/postfix/
cp ./conf/smtp_auth /etc/postfix/
mkdir /etc/postfix/sql
cp ./conf/accounts.cf /etc/postfix/sql/
cp ./conf/aliases.cf /etc/postfix/sql/
cp ./conf/domains.cf /etc/postfix/sql/
cp ./conf/recipient-access.cf /etc/postfix/sql/
cp ./conf/sender-login-maps.cf /etc/postfix/sql/
cp ./conf/tls-policy.cf /etc/postfix/sql/
chmod -R 660 /etc/postfix/sql
touch /etc/postfix/without_ptr
touch /etc/postfix/postscreen_access
postmap /etc/postfix/without_ptr
postmap /etc/postfix/smtp_auth
newaliases

echo "************************************************************************************"
echo "** Install OpenDKIM."
echo
apt-get -y install opendkim opendkim-tools
systemctl stop opendkim
cp ./conf/opendkim.conf /etc/opendkim.conf
mkdir /etc/opendkim
mkdir /etc/opendkim/keys
opendkim-genkey --selector=key1 --bits=2048 --directory=/etc/opendkim/keys
cp /etc/opendkim/keys/key1.txt .


exit 0

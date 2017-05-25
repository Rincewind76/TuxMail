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
(crontab -l 2>/dev/null; echo "@daily FILE=`mktemp` ; openssl dhparam 2048 -out $FILE && mv -f $FILE /etc/myssl/dh2048.pem") | crontab -
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
cat ./sql/create_vmail.sql | mysql -u root --password=$pass_mysql
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
apt-get -y install dovecot-core dovecot-imapd dovecot-lmtpd dovecot-mysql dovecot-sieve dovecot-managesieved dovecot-antispam dovecot-ldap ldap-utils
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
apt-get -y install postfix postfix-mysql libsasl2-modules postfix-ldap
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
chown opendkim /etc/opendkim/keys/key1.private
usermod -aG opendkim postfix

echo "************************************************************************************"
echo "** Install Amavis."
echo
apt-get -y install amavisd-new libdbi-perl libdbd-mysql-perl
systemctl stop amavisd-new
cp ./conf/50-user /etc/amavis/conf.d/
chmod 770 /etc/amavis/conf.d/50-user
wget 'https://github.com/ThomasLeister/amavisd-milter/archive/master.zip' -O amavisd-milter.zip
apt-get -y install gcc libmilter-dev make unzip
unzip amavisd-milter.zip
cd amavisd-milter-master
./configure
make
make install
make clean
cd ..
rm -r amavisd-milter-master
rm amavisd-milter.zip
cp ./conf/amavisd-milter.service /etc/systemd/system/
systemctl enable amavisd-milter

echo "************************************************************************************"
echo "** Install Spamassassin ."
echo
apt-get -y install spamassassin acl
cat ./sql/create_spamassassin.sql | mysql -u root --password=$pass_mysql
cat /usr/share/doc/spamassassin/sql/bayes_mysql.sql | mysql -u root --password=$pass_mysql spamassassin
cp ./conf/local.cf /etc/mail/spamassassin/
setfacl -m o:--- /etc/mail/spamassassin/local.cf
setfacl -m u:vmail:r /etc/mail/spamassassin/local.cf
setfacl -m u:amavis:r /etc/mail/spamassassin/local.cf
cp ./conf/sa-care.sh /root/
(crontab -l 2>/dev/null; echo "@daily /root/sa-care.sh") | crontab -
/root/sa-care.sh

echo "************************************************************************************"
echo "** Install Razor and Pyzor."
echo
apt-get -y install razor pyzor
sudo -i -u amavis -c razor-admin -create
sudo -i -u amavis -c razor-admin -register
sudo -i -u amavis -c pyzor discover

echo "************************************************************************************"
echo "** Start everything..."
echo
systemctl start dovecot
systemctl start amavisd-new
systemctl start amavisd-milter
systemctl start opendkim
systemctl start postfix

exit 0

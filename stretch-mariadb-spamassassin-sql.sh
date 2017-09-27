#!/bin/bash 

set -e 

#
# Verion 0.1Aplha
# started : 2017-09-27
# 
# SpamAssassin with MariaDB on Debian stretch
# Source: https://p5r.uk/blog/2017/spamassassin-with-mariadb.html 
#
# Added, missing perl files and make it scriptable. 
# Todo, add the correct pyzor and razor configure steps as spamassassin user.
# Goal, setup mailwatch/mailscanner with kopano and share the spamassassin databases.


# Install spamassassin
apt-get install spamassassin pyzor razor -y

systemctl status spamassassin
systemctl stop spamassassin

# Debian Spamd user is : debian-spamd
# configure pyzor razor as the user.
# debug test run : env -i LANG="$LANG" PATH="$PATH" start-stop-daemon --chuid debian-spamd:debian-spamd --start --exec /usr/bin/spamassassin -- -D --lint
# The test shows missing Perl modules.

# This one is optional. 
# module not installed: Digest::SHA1 ('require' failed)
# Debian shows : libdigest-sha-perl - Perl extension for SHA-1/224/256/384/512, SHA-512/224 and SHA-512/256
# apt-get install libdigest-sha-perl
# module not installed: Digest::SHA1 ('require' failed)
# PacketFence.org supplies : libdigest-sha1-perl for Jessie.
# Stretch, create your own deb.
# apt-get install build-essential devscripts dh-make-perl
# wget http://search.cpan.org/CPAN/authors/id/G/GA/GAAS/Digest-SHA1-2.13.tar.gz
# tar -pzxvf Digest-SHA1-2.13.tar.gz
# cd Digest-SHA1-2.13/
# debuild -j8 -sa
# dpkg -i libdigest-sha1-perl_2.13*.deb
# 
# use these 2 lines to cleanup you systems. 
# apt-get remove --purge build-essential devscripts dh-make-perl
# apt-get clean && apt-get autoclean && apt-get autoremove --purge
# result: 
# module installed: Digest::SHA1, version 2.13

# module not installed: Geo::IP ('require' failed)
apt-get install libgeo-ip-perl
# module installed: Geo::IP, version 1.50

# module not installed: Net::CIDR::Lite ('require' failed)
apt-get install libnet-cidr-lite-perl  
# module installed: Net::CIDR::Lite, version 0.21

# module not installed: Encode::Detect::Detector ('require' failed)
apt-get install libencode-detect-perl
# module installed: Encode::Detect::Detector, version 1.01

# module not installed: Net::Patricia ('require' failed)
apt-get install libnet-patricia-perl
# module installed: Net::Patricia, version 1.22


# This post is about how to configure SpamAssassin to store its volatile data in a MariaDB database. 
# Most of the information is based on the documentation in  /usr/share/doc/spamassassin/sql, the SpamAssassin SQL wiki. 
# As the title suggests these instructions are heavily Debian-based. 

# In /etc/default/spamassassin add the options --sql-config (-q), --nouser-config (-x) and -u mail to the OPTIONS configuration. 
# ( mail changed to spamassassin username , debian-spamd )
sed 's/OPTIONS=\"--create-prefs --max-children 5 --helper-home-dir\"/OPTIONS=\"--create-prefs --max-children 5 --helper-home-dir --sql-config --nouser-config -u debian-spamd\"/g' /etc/default/spamassassin

# First, create a database and a user in MariaDB: 
mysql -u root <<-EOF
        CREATE DATABASE spamassassin;
        CREATE USER 'spamassassin'@'localhost' IDENTIFIED BY 'my_spamassassin_password';
        GRANT ALL ON spamassassin.* TO 'spamassassin'@'localhost';
        FLUSH PRIVILEGES;
EOF

###   Setting up users' score
#SpamAssassin can load user specific settings from the database, if the user_scores_dsn variable is set (and spamd is started with the --sql-config option). On the file 
cat << EOF >> /etc/spamassassin/local-sql.cf
# 
# Enable SQL Database for SpamAssassin
user_scores_dsn              dbi:mysql:spamassassin:localhost
user_scores_sql_username     spamassassin
user_scores_sql_password     my_spamassassin_password
# Optional, custom_query, this MUST BE ONE LINE.
# user_scores_sql_custom_query SELECT preference, value FROM _TABLE_ WHERE username = _USERNAME_ OR username = '$GLOBAL' OR username = CONCAT('%',_DOMAIN_) ORDER BY username ASC
EOF

# Since a password is used here, adjust the rights. 
chown root:debian-spamd /etc/spamassassin/local-sql.cf
chmod 640 /etc/spamassassin/local-sql.cf

#For the default query to work the userpref table must have at least the username, preference and value fields. The username field contains the username whose e-mail is being #filtered or “@GLOBAL” for a global option. Example layouts are in /usr/share/doc/spamassassin/sql/ 

#mysql -u root
#use spamassassin;

mysql -u root spamassassin <<-EOF
CREATE TABLE userpref (
        username varchar(100) NOT NULL default '',
        preference varchar(50) NOT NULL default '',
        value varchar(100) NOT NULL default '',
        prefid int(11) NOT NULL auto_increment,
        PRIMARY KEY (prefid),
        KEY username (username));
INSERT INTO userpref (username, preference, value) VALUES ('@GLOBAL', 'required_hits', '4.0');
EOF
# Optional 
# INSERT INTO userpref (username, preference, value) VALUES ('alice', 'whitelist_from', '*@example.com');


# Setting up the auto-whitelist configuration
# Make sure the AWL plugin is enabled in /etc/spamassassin/v310.pre: 
sed -i 's/#loadplugin Mail::SpamAssassin::Plugin::AWL/loadplugin Mail::SpamAssassin::Plugin::AWL/g' /etc/spamassassin/v310.pre


# The setting below tells SpamAssassin to use the auto-whitelist in the SQL database. 
cat << EOF >> /etc/spamassassin/local-sql.cf

auto_whitelist_factory       Mail::SpamAssassin::SQLBasedAddrList

user_awl_dsn                 dbi:mysql:spamassassin:localhost
user_awl_sql_username        spamassassin
user_awl_sql_password        my_spamassassin_password
user_awl_sql_table           awl
EOF


# The default table layout in /usr/share/doc/spamassassin/sql/awl_mysql.sql
# creates a unique key that is too long for the InnoDB engine. 
# You can use only a subset of the fields in the key like this: 

#mysql -u root
#use spamassassin;

mysql -u root spamassassin <<-EOF
CREATE TABLE awl (
  username varchar(100) NOT NULL default '',
  email varbinary(255) NOT NULL default '',
  ip varchar(40) NOT NULL default '',
  count int(11) NOT NULL default '0',
  totscore float NOT NULL default '0',
  signedby varchar(255) NOT NULL default '',
  PRIMARY KEY (username,email(150),signedby(150),ip)
) ENGINE=InnoDB;
EOF

# SpamAssassin only adds data to the auto-whitelist table and does not delete from it. 
# Hence it is suggested to change the table to include a timestamp of the last modification for each record. 
# With this additional column it is possible to selectively delete old and unused records. 
ALTER TABLE awl ADD lastupdate timestamp default CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP;
UPDATE awl SET lastupdate = NOW() WHERE lastupdate < 1;
\q

# needs in script 
# The following statements delete entries that are older than 6 months and addresses that occurred only once in the past 15 days. 
#DELETE FROM awl WHERE lastupdate <= DATE_SUB(SYSDATE(), INTERVAL 6 MONTH);
#DELETE FROM awl WHERE count = 1 AND lastupdate <= DATE_SUB(SYSDATE(), INTERVAL 15 DAY);


#####  Setting up the Bayes configuration
# The Bayes settings are similar to the ones seen above. 
cat << EOF >> /etc/spamassassin/local-sql.cf
bayes_store_module           Mail::SpamAssassin::BayesStore::SQL

bayes_sql_dsn                dbi:mysql:spamassassin:localhost
bayes_sql_username           spamassassin
bayes_sql_password           my_spamassassin_password
#bayes_sql_override_username  debian-spamd

EOF

######## Bayes SQL 

#mysql -u root
#use spamassassin;

mysql -u root spamassassin <<-EOF
# The tables with the default layout are created with the following commands. 
CREATE TABLE bayes_expire (
        id int(11) NOT NULL default '0',
        runtime int(11) NOT NULL default '0',
        KEY bayes_expire_idx1 (id));
CREATE TABLE bayes_global_vars (
        variable varchar(30) NOT NULL default '',
        value varchar(200) NOT NULL default '',
        PRIMARY KEY  (variable));
INSERT INTO bayes_global_vars VALUES ('VERSION','3');
CREATE TABLE bayes_seen (
        id int(11) NOT NULL default '0',
        msgid varchar(200) binary NOT NULL default '',
        flag char(1) NOT NULL default '',
        PRIMARY KEY (id, msgid(100)));
CREATE TABLE bayes_token (
        id int(11) NOT NULL default '0',
        token binary(5) NOT NULL default '',
        spam_count int(11) NOT NULL default '0',
        ham_count int(11) NOT NULL default '0',
        atime int(11) NOT NULL default '0',
        PRIMARY KEY  (id, token),
        INDEX bayes_token_idx1 (id, atime));
CREATE TABLE bayes_vars (
        id int(11) NOT NULL AUTO_INCREMENT,
        username varchar(200) NOT NULL default '',
        spam_count int(11) NOT NULL default '0',
        ham_count int(11) NOT NULL default '0',
        token_count int(11) NOT NULL default '0',
        last_expire int(11) NOT NULL default '0',
        last_atime_delta int(11) NOT NULL default '0',
        last_expire_reduce int(11) NOT NULL default '0',
        oldest_token_age int(11) NOT NULL default '2147483647',
        newest_token_age int(11) NOT NULL default '0',
        PRIMARY KEY  (id),
        UNIQUE bayes_vars_idx1 (username(100)));
EOF


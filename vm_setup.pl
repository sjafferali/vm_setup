#!/usr/bin/perl

# vm_setup.pl

use strict;
use warnings;
use Getopt::Long;
use Fcntl;
$| = 1;

my $VERSION = '0.2.0';

# get opts
my ($ip, $natip, $help, $fast, $full, $answer);
GetOptions (
    "help" => \$help,
    "full" => \$full,
    "fast" => \$fast,
);

# print header
print "\nVM Server Setup Script\n" .
      "Version: $VERSION\n" .
      "\n";
if ($help) {
    print "Usage: perl vm_setup.pl [options]\n\n";
    print "Description: Performs a number of functions to prepare meteorologist VMs for immediate use. \n\n";
    print "Options: \n";
    print "-------------- \n";
    print "--fast: Skips all optional setup functions\n";
    print "--full: Passes yes to all optional setup functions \n\n";
    print "Full list of things this does: \n";
    print "-------------- \n";
    print "- Installs common packages\n";
    print "- Sets hostname\n";
    print "- Sets resolvers\n";
    print "- Builds /var/cpanel/cpnat\n";
    print "- Performs basic setup wizard\n";
    print "- Fixes /etc/host\n";
    print "- Fixes screen permissions\n";
    print "- Runs cpkeyclt\n";
    print "- Creates a test accounts\n";
    print "- Runs upcp (optional)\n";
    print "- Runs check_cpanel_rpms --fix (optional)\n";
    print "- Installs Task::Cpanel::Core (optional)\n\n";
    exit;
}


### and go
if($full)
{
    print "--full passed. Passing y to all optional setup options.\n\n";
    chomp ($answer="y");
}
if($fast)
{
    print "--fast passed. Skipping all optional setup options.\n\n";
    chomp ($answer="n");
}

# check for and install prereqs
print "installing utilities via yum [mtr nmap telnet bind-utils jwhois dev git]\n";
system_formatted ("yum install mtr nmap telnet bind-utils jwhois dev git -y");

# set hostname
print "setting hostname\n";
system_formatted ("hostname daily.cpanel.vm");
sysopen (my $etc_hostname, '/etc/hostname', O_WRONLY|O_CREAT) or
    die print_formatted ("$!");
    print $etc_hostname "daily.cpanel.vm";
close ($etc_hostname);

# add resolvers
print "adding resolvers\n";
unlink '/etc/resolv.conf';
sysopen (my $etc_resolv_conf, '/etc/resolv.conf', O_WRONLY|O_CREAT) or
    die print_formatted ("$!");
    print $etc_resolv_conf "nameserver 10.6.1.1\n" . "nameserver 8.8.8.8\n";
close ($etc_resolv_conf);

# run /scripts/build_cpnat
print "running build_cpnat\n";
system_formatted ("/scripts/build_cpnat");
chomp ( $ip = qx(cat /var/cpanel/cpnat | awk '{print\$2}') );
chomp ( $natip = qx(cat /var/cpanel/cpnat | awk '{print\$1}') );

# create .whostmgrft
print "creating /etc/.whostmgrft\n";
sysopen (my $etc_whostmgrft, '/etc/.whostmgrft', O_WRONLY|O_CREAT) or
    die print_formatted ("$!");
close ($etc_whostmgrft);

# correct wwwacct.conf
print "correcting /etc/wwwacct.conf\n";
unlink '/etc/wwwacct.conf';
sysopen (my $etc_wwwacct_conf, '/etc/wwwacct.conf', O_WRONLY|O_CREAT) or
    die print_formatted ("$!");
    print $etc_wwwacct_conf "HOST daily.cpanel.vm\n" .
                            "ADDR $natip\n" .
                            "HOMEDIR /home\n" .
                            "ETHDEV eth0\n" .
                            "NS ns1.os.cpanel.vm\n" .
                            "NS2 ns2.os.cpanel.vm\n" .
                            "NS3\n" .
                            "NS4\n" .
                            "MINUID 500\n" .
                            "HOMEMATCH home\n" .
                            "NSTTL 86400\n" .
                            "TTL 14400\n" .
                            "DEFMOD x3\n" .
                            "SCRIPTALIAS y\n" .
                            "CONTACTPAGER\n" .
                            "MINUID\n" .
                            "CONTACTEMAIL\n" .
                            "LOGSTYLE combined\n" .
                            "DEFWEBMAILTHEME x3\n";
close ($etc_wwwacct_conf);

# correct /etc/hosts
print "correcting /etc/hosts\n";
unlink '/etc/hosts';
sysopen (my $etc_hosts, '/etc/hosts', O_WRONLY|O_CREAT) or
    die print_formatted ("$!");
    print $etc_hosts "127.0.0.1		localhost localhost.localdomain localhost4 localhost4.localdomain4\n" .
                     "::1		localhost localhost.localdomain localhost6 localhost6.localdomain6\n" .
                     "$ip		daily daily.cpanel.vm\n";
close ($etc_hosts);

# update cplicense
print "updating cpanel license\n";
system_formatted ('/usr/local/cpanel/cpkeyclt');

# fix screen perms
print "fixing screen perms\n";
system_formatted ('rpm --setperms screen');

# create test account
print "creating test account - cptest\n";
system_formatted ('yes|/scripts/wwwacct cptest.tld cptest cpanel1');
print "creating test email - testing\@cptest.tld\n";
system_formatted ('/scripts/addpop testing@cptest.tld cpanel1');
print "creating test database - cptest_testdb\n";
system_formatted ("mysql -e 'create database cptest_testdb'");
print "creating test db user - cptest_testuser\n";
system_formatted ("mysql -e 'create user \"cptest_testuser\" identified by \"cpanel1\"'");
print "adding all privs for cptest_testuser to cptest_testdb\n";
system_formatted ("mysql -e 'grant all on cptest_testdb.* TO cptest_testuser'");
system_formatted ("mysql -e 'FLUSH PRIVILEGES'");
print "mapping cptest_testuser and cptest_testdb to cptest account\n";
system_formatted ("/usr/local/cpanel/bin/dbmaptool cptest --type mysql --dbusers 'cptest_testuser' --dbs 'cptest_testdb'");

# upcp
print "would you like to run upcp now? [n] ";
if (!$full && !$fast) { 
    chomp ($answer = <STDIN>);
}
if ($answer eq "y") {
    print "\nrunning upcp \n ";
    system_formatted ('/scripts/upcp');
}

# running another check_cpanel_rpms
print "would you like to run check_cpanel_rpms now? [n] ";
if (!$full && !$fast) { 
    chomp ($answer = <STDIN>);
}
if ($answer eq "y") {
    print "\nrunning check_cpanel_rpms \n ";
    system_formatted ('/scripts/check_cpanel_rpms --fix');
}

# install Task::Cpanel::Core
print "would you like to install Task::Cpanel::Core? [n] ";
if (!$full && !$fast) { 
    chomp ($answer = <STDIN>);
}
if ($answer eq "y") {
    print "\ninstalling Task::Cpanel::Core\n ";
    system_formatted ('/scripts/perlinstaller Task::Cpanel::Core');
}

# exit cleanly
print "setup complete\n\n";
print "https://$ip:2087/login/?user=root&pass=cpanel1\n";
print "https://$ip:2083/login/?user=root&pass=cpanel1\n\n";

### subs
sub print_formatted {
    my @input = split /\n/, $_[0];
    foreach (@input) { print "    $_\n"; }
}

sub system_formatted {
    open (my $cmd, "-|", "$_[0]");
    while (<$cmd>) {
        print_formatted("$_");
    }
    close $cmd;
}

#!/usr/bin/perl
use Getopt::Std;
use Fcntl;
use DBI;

# Set User Defaults
$fqdn = "washington.uww.edu"; #fully qualified domain name
$mysqlhost = "washington.uww.edu";

######################################################
# SHOULD NOT NEED TO CHANGE ANYTHING BELOW THIS LINE #
######################################################

# Grab Values
getopts("f:c:wrmu:s:d");
my ($file,$course,$web,$remove,$mysql,$mysqluser,$semester,$dbonly) = ($opt_f,$opt_c,$opt_w,$opt_r,$opt_m,$opt_u,$opt_s,$opt_d);
if ($file eq '' || $course eq '' || $semester eq '') {
        usage();
}

# Set Webroot
$webroot = "/srv/www/htdocs/$course";

if ($mysql) {
        usage() if ($mysqluser eq '');
        # Verify User/Pass
        system("stty -echo");
        print "Please enter the mysql password for $mysqluser: ";
        chomp($mysqlpass = <STDIN> );
        system("stty echo");
}

# Does Instructors Group Exists?
if (!getgrnam('instructors')) {
        die("'instructors' system group is not present.  You must add the 'instructors' group for file acls to work.");
}

open(STUDENTS, $file) or die $!;

while ($record = <STUDENTS>) {
        @records = split(/,/,$record);
        $id = substr($records[0],3,4);
        $netid = lc($records[4]);
        $first = lc(substr($records[1],0,1));
        $last = lc(substr($records[2],0,1));
        $pass = $first.$last.$id;

        # Safety Check
        if ($netid eq "") {
                die("netid is empty");
        }
        if (not defined $netid) {
                die("netid is not defined");
        }

        $passcrypt = crypt($pass,$pass);
        $homedir = "/home/students/$netid";
        $dbname = $course."-".$semester."_".lc($netid);
        #$dbname = lc($records[2])."DB";
        print "-----------------------\n";

        if ($remove) {
                die("remove user portion not complete");
        } else {
                if ($dbonly eq '') {
                        # Create course group
                        system("/usr/sbin/groupadd $course");

                        # Create User
                        $id = `id -u $netid`;
                        if ($id =~ m/^\d+$/g) {
                                print "User $netid exists. Password not changed.\n";
                                #system("/usr/sbin/usermod -p $passcrypt $netid"); //this will reset the password
                        } else {
                                system("/usr/sbin/groupadd $netid");
                                ($gname,$gpasswd,$gid,$gmembers) = getgrnam $netid;
                                system("/usr/sbin/useradd -m -g $gid -p $passcrypt -d $homedir $netid");
                                system("/usr/sbin/usermod -A shellaccess,$course $netid");

                                # Set Password Age
                                system("chage -d 0 $netid");
                        }

                        # Update Owner
                        system("chown -R $netid $homedir");
                        system("chgrp -R $netid $homedir");

                        # Update Permissions
                        system("chmod -R 701 $homedir");

                        # Remove Default Web
                        system("rm -rf $homedir/public_html");

                        # Create Symlink for Instructor
                        if (!-d "/home/$course-$semester") {
                                system("mkdir /home/$course-$semester");
                                system("setfacl -m g:instructors:rwx /home/$course-$semester");
                                system("setfacl -m d:g:instructors:rwx /home/$course-$semester");
                        }

                        if (!-l "/home/$course-$semester/$netid") {
                                system("ln -s $homedir /home/$course-$semester/$netid");
                        }

                        # Create Web Folder
                        if ($web) {
                                if (!-d $webroot) {
                                        system("mkdir $webroot");
                                }

                                if (!-d "$homedir/html_$course") {
                                        system("mkdir $homedir/html_$course");
                                        system("chown $netid -R $homedir/html_$course");
                                        system("chgrp $netid -R $homedir/html_$course");
                                }
                                if (!-d "$homedir/html_$course/cgi-bin") {
                                        system("mkdir $homedir/html_$course/cgi-bin");
                                        system("chown $netid -R $homedir/html_$course/cgi-bin");
                                        system("chgrp $netid -R $homedir/html_$course/cgi-bin");
                                        system("chmod -R 755 $homedir/html_$course/cgi-bin");
                                }

                                if (!-l "$webroot/$netid") {
                                        system("ln -s $homedir/html_$course $webroot/$netid");
                                }

                                system("setfacl -R -m u:wwwrun:rwx $homedir/html_$course");

                        }

                        # Set Folder Permissions
                        system("setfacl -R -m g:instructors:rwx /home/students/$netid");
                        system("setfacl -R -m d:g:instructors:rwx /home/students/$netid");
                }

                # Create MySQL Database
                if ($mysql) {
                        # Connect
                        $dsn = "DBI:mysql:mysql:host=$mysqlhost;port=3306";
                        $dbh = DBI->connect($dsn, $mysqluser, $mysqlpass);

                        $sth = $dbh->prepare("CREATE DATABASE IF NOT EXISTS `$dbname` DEFAULT CHARACTER SET utf8 COLLATE utf8_general_ci;");
                        if (!$sth->execute) {
                                print "Error creating database: $dbname - ".$sth->errstr;
                        }

                        $sth = $dbh->prepare("SELECT count(*) as count FROM `user` WHERE user = '$netid'");
                        $sth->execute;
                        $sth->bind_columns(\$count);
                        $sth->fetch();

                        if ($count < 1) {
                                $sth = $dbh->prepare("CREATE USER '$netid' IDENTIFIED BY '$pass'");
                                if (!$sth->execute) {
                                        print "Error creating user: $netid - ".$sth->errstr;
                                } else {
                                        print "MySQL user $netid added.\n";
                                }
                        } else {
                                print "MySQL user already exists.\n";
                        }
                        $sth = $dbh->prepare("GRANT ALL PRIVILEGES ON `$dbname` . * TO '$netid'\@'%'");
                        if (!$sth->execute) {
                                print "Error granting privileges - $netid - ".$sth->errstr;
                        } else {
                                print "DB Permissions Granted.\n";
                        }
                        $sth = $dbh->prepare("GRANT ALL PRIVILEGES ON `$dbname` . * TO '$netid'\@'localhost' IDENTIFIED BY '$pass'");
                        if (!$sth->execute) {
                                print "Error granting privileges - $netid - ".$sth->errstr;
                        } else {
                                print "DB Permissions Granted.\n";
                        }
                        $sth = $dbh->prepare("GRANT ALL PRIVILEGES ON `$dbname` . * TO '$netid'\@'$mysqlhost' IDENTIFIED BY '$pass'");
                        if (!$sth->execute) {
                                print "Error granting privileges - $netid - ".$sth->errstr;
                        } else {
                                print "DB Permissions Granted.\n";
                        }
                }
        }
        print "-----------------------\n";
}
close(STUDENTS);

sub usage {

print "Usage: $0 options

Class User/Web/Database creation script by Aaron Axelsen

Users passwords will be first initial of first name, first initial of last name, last 4 of student id.  Password change is required on first login.
Users home folders will be set to /home/students/\$username.
The web folders are located in $webroot\$course/\$username.
The students will have a symlink to the web folder in /home/students/\$username/html_\$course

Example Usage:
        $0 -f cs223_2127.txt -s 2127 -c cs223
        $0 -f cs382_2137.txt -s 2137 -c cs382 -w
        $0 -f cs482_2131.txt -s 2131 -c cs482 -w -m -u axelsena

Required:
 -f file     course roster extract file - available at https://appsdev.uww.edu/dev/ltc/classrosters-compsci
 -c course   name of the course being created - ex. cs482
 -s semester the semester code for the current semester - ex. 2127

Optional:
 -w          flag to create web folders under $fqdn with symlinks into the users home folder (html_course)
 -m          flag to create mysql database for each user
 -d          only creates the mysql database, no local user is created
 -u user     mysql username to use for creation
\n";
exit;
}

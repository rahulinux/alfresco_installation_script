
# Automate installation of alfresco on Ubuntu 12.04
# Following the installation instructions from http://fcorti.com/2013/01/09/installation-alfresco-4-2-c-on-ubuntu/

set -e
#-------------> Global variables

alfresco_dir='/opt/alfresco'
postgresql_dir='/opt/postgresql'
jdk_download_link='http://download.oracle.com/otn-pub/java/jdk/7u45-b18/jdk-7u45-linux-i586.tar.gz'
# You can find download links from : https://ivan-site.com/2012/05/download-oracle-java-jre-jdk-using-a-script/
# jdk_download_link='http://download.oracle.com/otn-pub/java/jdk/7u45-b18/jdk-7u7-linux-x64.tar.gz'
tomcat_download_link='http://archive.apache.org/dist/tomcat/tomcat-7/v7.0.30/bin/apache-tomcat-7.0.30.tar.gz'
alfresco_download_link='http://dl.alfresco.com/release/community/build-04576/alfresco-community-4.2.c.zip'



#------------> Functions 
os_update() {
	echo "Updating OS"
	sudo apt-get update
	sudo apt-get upgrade
}

remove_old_jdk() {
	echo "Removing Preinstalled OpenJDK"
	apt-get purge openjdk-\*
}

create_user() {
	echo "Creating Users"
	# Generate crypt using : python -c "import crypt; print crypt.crypt('x','$2salt')"
	# crypted pass is 'x'
	id alfresco || useradd -p 'sa/gmiDJtU21A' alfresco
	id postgres || useradd -s /bin/bash -m -p 'sa/gmiDJtU21A' postgres
	# add into sudo group
	adduser alfresco sudo
	adduser postgres sudo	

}

create_required_dir_set_perm(){
	
	echo "Settingup $alfresco_dir"

	[[ -d $alfresco_dir ]] ||  mkdir -p $alfresco_dir
	[[ -d $postgresql_dir ]] || mkdir -p $postgresql_dir
	chown alfresco. $alfresco_dir
	chown alfresco. $postgresql_dir

}

download_compile_jdk(){
	echo "Downloading and Installing JDK"

	[[ -d ${alfresco_dir}/java ]] || mkdir ${alfresco_dir}/java
	cd ${alfresco_dir}/java
	[[ -f ${jdk_download_link##*/} ]] ||  wget --no-cookies --header \
	"Cookie: gpw_e24=http%3A%2F%2Fwww.oracle.com" "${jdk_download_link}"
	echo "Extracting JDK"
	tar -xzf ${jdk_download_link##*/}
	chown -R alfresco. ${alfresco_dir} 
	cat <<-_EOF >> /etc/profile.d/java.sh
	export JAVA_HOME=${alfresco_dir}/java/jdk1.7.0_07
	export PATH=\$PATH:\$HOME/bin:\$JAVA_HOME/bin
	_EOF
}

install_required_packages() {
	echo "Installing Required Pckages"
	apt-get install ghostscript && echo "GhostScript Done"
	apt-get install imagemagick && echo "Imagemagick Done"
	apt-get install ffmpeg && echo "ffmpeg Done"
	apt-get install libreoffice && echo "LibreOffice"
	apt-get install libart-2.0-2 libjpeg62 libgif-dev
	apt-get install gcc libreadline-dev bison flex zlib1g-dev make
	cd /usr/local/src/
	wget http://launchpadlibrarian.net/43569089/swftools_0.9.0-0ubuntu2_i386.deb
	chmod a+x swftools_0.9.0-0ubuntu2_i386.deb
	dpkg -i swftools_0.9.0-0ubuntu2_i386.deb 
	
}

configure_postgresql() {
	[[ -d ${postgresql_dir}/9.0.4 ]] || sudo mkdir ${postgresql_dir}/9.0.4
	cd $postgresql_dir
	test -f postgresql-9.0.4.tar.gz  || wget ftp://ftp.postgresql.org/pub/source/v9.0.4/postgresql-9.0.4.tar.gz 
	chmod a+x postgresql-9.0.4.tar.gz
	gunzip postgresql-9.0.4.tar.gz
	tar xvf postgresql-9.0.4.tar
	cd ${postgresql_dir}/postgresql-9.0.4/
	./configure exec_prefix=${postgresql_dir}/9.0.4
	make exec_prefix=${postgresql_dir}/9.0.4
	make install exec_prefix=${postgresql_dir}/9.0.4
	chown -R postgres:postgres ${postgresql_dir}
	su - postgres -c "mkdir ${postgresql_dir}/9.0.4/data
	mkdir ${postgresql_dir}/9.0.4/log
	touch /home/postgres/.environment-9.0.4
	"
	cat <<-_EOF > /home/postgres/.environment-9.0.4
	#!/bin/sh

	export POSTGRESQL_VERSION=9.0.4
	export LD_LIBRARY_PATH=${postgresql_dir}/\${POSTGRESQL_VERSION}/lib
	export PATH=${postgresql_dir}/\${POSTGRESQL_VERSION}/bin:\${PATH}
	_EOF
	grep -q '.environment-9.0.4' /home/postgres/.bashrc || echo '. .environment-9.0.4' >> /home/postgres/.bashrc
	su - postgres -c "
	chmod a+x /home/postgres/.environment-9.0.4
	/home/postgres/.environment-9.0.4
	${postgresql_dir}/9.0.4/bin/initdb -D ${postgresql_dir}/9.0.4/data/ --encoding=UNICODE
	touch /home/postgres/postgresql-9.0.4
	"
	cat <<-_EOF > /home/postgres/postgresql-9.0.4
	#!/bin/sh -e

	# Parameters: start or stop.
	export POSTGRESQL_VERSION=9.0.4

	# Check parameter.
	if [ "\$1" != "start" ] && [ "\$1" != "stop" ]; then
	  echo "Specify start or stop as first parameter."
	  exit
	fi

	# Add stop switch.
	__STOP_SWITCH=""
	if [ "\$1" = "stop" ]; then
	  __STOP_MODE="smart"
	  __STOP_SWITCH="-m \$__STOP_MODE"
	  echo "Stop switch is: \$__STOP_SWITCH"
	fi

	# Do it.
	export LD_LIBRARY_PATH=/opt/postgresql/\${POSTGRESQL_VERSION}/lib
	~/.environment-\${POSTGRESQL_VERSION}
	/opt/postgresql/\${POSTGRESQL_VERSION}/bin/pg_ctl \\
	     -D /opt/postgresql/\${POSTGRESQL_VERSION}/data \\
	     -l /opt/postgresql/\${POSTGRESQL_VERSION}/log/postgresql.log \\
	     \$1 \$__STOP_SWITCH
	_EOF
	chmod a+x /home/postgres/postgresql-9.0.4
	cat <<-EOF > /etc/init.d/postgresql.9.0.4
	#!/bin/sh -e

	case "\$1" in
	 	start)
			echo "Starting postgres"
			/bin/su - postgres -c "/home/postgres/postgresql-9.0.4 start"
		  ;;
		stop)
			echo "Stopping postgres" 
			/bin/su - postgres -c "/home/postgres/postgresql-9.0.4 stop"
			;;
		 * )
			echo "Usage: service postgresql-9.0.4 {start|stop}"
			exit 1

	esac

	exit 0
	EOF
	chmod +x /etc/init.d/postgresql.9.0.4
	service postgresql.9.0.4 start
	sql_cmd=/home/postgres/.sql_cmd
	cat <<-EOF > $sql_cmd
	CREATE ROLE alfresco WITH PASSWORD 'alfresco' LOGIN;
	CREATE DATABASE alfresco WITH OWNER alfresco;
	EOF
	su - postgres -c "
	. .environment-9.0.4
	psql -f $sql_cmd
	"
	cat <<-EOF > $sql_cmd
	ALTER USER alfresco WITH PASSWORD 'alfresco';	
	EOF
	su - postgres -c ". .environment-9.0.4; psql -U alfresco -d alfresco -f $sql_cmd"
	[[ -f $sql_cmd ]] &&  rm -f $sql_cmd

}

configure_tomcat(){
	cd $alfresco_dir
	[[ -f ${tomcat_download_link##*/} ]] || wget ${tomcat_download_link}
	chmod a+x ${tomcat_download_link##*/}
	tar -xzvf ${tomcat_download_link##*/}
	#[[ -f ${tomcat_download_link##*/} ]] && rm -rf ${tomcat_download_link##*/}
	edir=${tomcat_download_link##*/}
	extracted_name=${edir%.tar.gz}
	mv $extracted_name ${alfresco_dir}/tomcat
	echo "Checking Tomcat"
	${alfresco_dir}/tomcat/bin/startup.sh
	( ps -ef | grep java && sleep 3 && nc -vzw 1 localhost 8080 ) && echo "Tomcat is running Successfully" ||
	{ echo "Something wrong with tomcat installation"; exit 1;  }
	${alfresco_dir}/tomcat/bin/shutdown.sh
	cateline_prop=${alfresco_dir}/tomcat/conf/catalina.properties
	[[ -f ${cateline_prop}-org-bkp ]] ||  cp -v ${cateline_prop}{,-org-bkp}
	grep -q 'shared.loader=/shared' $cateline_prop ||
	sed -i 's/shared.loader=/shared.loader=${catalina.base}\/shared\/classes\,${catalina.base}\/shared\/lib\/*.jar/'\
	$cateline_prop
	server_xml=${alfresco_dir}/tomcat/conf/server.xml
	[[ -f ${server_xml}-org-bkp ]] || cp -v ${server_xml}{,-org-bkp}
	grep -q 'URIEncoding="UTF-8"' $server_xml ||
	sed -i '/connectionTimeout/,/redirectPort/{s/redirectPort="8443"/redirectPort="8443" \n\t\tURIEncoding="UTF-8"/}' \
	$server_xml
	contextfile=${alfresco_dir}/tomcat/conf/context.xml
	[[ -f ${contextfile}-bkp-org ]] || cp -v ${contextfile}{,-bkp-org}
	cat <<-_EOF > $contextfile
	<?xml version='1.0' encoding='utf-8'?>
	<Context>
	<Valve className="org.apache.catalina.authenticator.SSLAuthenticator" securePagesWithPragma="false" />
	</Context>
	_EOF

}

configure_alfresco(){
#	mkdir ${alfresco_dir}/tomcat/{shared,endorsed}
#	mkdir ${alfresco_dir}/tomcat/shared/{classes,lib}
#	[[ -f ${alfresco_download_link##*/} ]] || wget ${alfresco_download_link}
#        chmod a+x ${alfresco_download_link##*/}
#	apt-get install unzip
#	unzip ${alfresco_download_link##*/}
#	mv -v web-server/shared/* ${alfresco_dir}/tomcat/shared/
#	mv -v web-server/lib/* ${alfresco_dir}/tomcat/lib/
#	mv -v web-server/webapps/* ${alfresco_dir}/tomcat/webapps/
#	cat <<-_EOF > /opt/alfresco/start_oo.sh
#	#!/bin/sh -e
#
#	SOFFICE_ROOT=/usr/bin
#	"\${SOFFICE_ROOT}/soffice" "--accept=socket,host=localhost,port=8100;urp;StarOffice.ServiceManager" --nologo --headless &
#	_EOF
#	chmod uga+x ${alfresco_dir}/start_oo.sh
	${alfresco_dir}/start_oo.sh
	killall soffice.bin
	cat <<-_EOF >  ${alfresco_dir}/alfresco.sh
	#!/bin/sh -e

	# Start or stop Alfresco server

	# Set the following to where Tomcat is installed
	ALF_HOME=${alfresco_dir}
	cd "\$ALF_HOME"
	APPSERVER="\${ALF_HOME}/tomcat"
	export CATALINA_HOME="\$APPSERVER"

	# Set any default JVM values
	export JAVA_OPTS='-Xms512m -Xmx768m -Xss768k -XX:MaxPermSize=256m -XX:NewSize=256m -server'
	export JAVA_OPTS="\${JAVA_OPTS} -Dalfresco.home=\${ALF_HOME} -Dcom.sun.management.jmxremote"

	if [ "\$1" = "start" ]; then
		 "\${APPSERVER}/bin/startup.sh"
		 if [ -r ./start_oo.sh ]; then
			  "\${ALF_HOME}/start_oo.sh"
		 fi
	elif [ "\$1" = "stop" ]; then
		 "\${APPSERVER}/bin/shutdown.sh"
		 killall -u alfresco java
		 killall -u alfresco soffice.bin
	fi
	_EOF
	
	chmod +x ${alfresco_dir}/alfresco.sh
	cat <<-_EOF >  /etc/init.d/alfresco
	#!/bin/sh -e

	ALFRESCO_SCRIPT="${alfresco_dir}alfresco.sh"

	if [ "\$1" = "start" ]; then
	 su - alfresco "\${ALFRESCO_SCRIPT}" "start"
	elif [ "\$1" = "stop" ]; then
	 su - alfresco "\${ALFRESCO_SCRIPT}" "stop"
	elif [ "\$1" = "restart" ]; then
	 su - alfresco "\${ALFRESCO_SCRIPT}" "stop"
	 su - alfresco "\${ALFRESCO_SCRIPT}" "start"
	else
	 echo "Usage: /etc/init.d/alfresco [start|stop|restart]"
	fi
	_EOF
	chmod +x /etc/init.d/alfresco
	chown alfresco:alfresco /etc/init.d/alfresco
	[[ -d ${alfresco_dir}/alf_data ]] ||  mkdir ${alfresco_dir}/alf_data
	alfresco_prop=${alfresco_dir}/tomcat/shared/classes/alfresco-global.properties.sample
	[[ -f ${alfresco_prop%.sample} ]] || cp -v $alfresco_prop ${alfresco_prop%.sample}
	
		



}

Main(){
	#os_update
	#remove_old_jdk
	#create_user
	#create_required_dir_set_perm
	#download_compile_jdk
	#install_required_packages
	#configure_postgresql
	#configure_tomcat
	configure_alfresco
}


Main

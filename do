#!/bin/bash

[[ "${SECRET}" == "" ]] && SECRET=~/.secret
ENV=${SECRET}/.ceph/env

[ -e $ENV ] && . $ENV || { \
	mkdir -p `dirname $ENV` ; \
	read -p "[ceph] NETWORK: " NETWORK ; \
	echo NETWORK=$NETWORK > $ENV
	read -p "[ceph] OPERATOR: " OPERATOR ; \
	echo OPERATOR=$OPERATOR >> $ENV
	read -p "[ceph] SSHPORT: " SSHPORT ; \
	echo SSHPORT=$SSHPORT >> $ENV
}
echo NETWORK=$NETWORK
echo OPERATOR=$OPERATOR
echo SSHPORT=$SSHPORT

ACTION=$1
HOST=$2
PORT=$SSHPORT
USER=$OPERATOR
if [ "$PORT" == "" ] ; then PORT=${SECRET_SSHPORT} ; fi
HOSTIP=`eval "cat /etc/hosts | grep ' ${HOST} ' | cut -d ' ' -f 1"`

echo \# ceph-adm: NETWORK=$NETWORK OPERATOR=$OPERATOR SSHPORT=$SSHPORT ACTION=$ACTION HOST=$HOST
echo ===

case $ACTION in
	"initby")
		ssh -t ${USER}@${HOST} -p ${SSHPORT} "
			cd ~/docker/docker-workshop/services/ceph
			./ws cleanclean
			./ws mon $HOSTIP $NETWORK
			./ws clean
			rm -rf ~/.secret/.ceph
			mkdir -p ~/.secret/.ceph
			sudo tar pzcf ~/.secret/.ceph/ceph.secret.tgz ~/store/ceph
			sudo chown ${USER} ~/.secret/.ceph/ceph.secret.tgz
			"
		scp -P ${SSHPORT} ${USER}@${HOST}:/home/${USER}/.secret/.ceph/ceph.secret.tgz ${SECRET}/.ceph
		ssh -t ${USER}@${HOST} -p ${SSHPORT} "rm -rf ~/.secret/.ceph"
		;;
	"deploy")
		shift
		HOSTS=$*
		for HOST in $HOSTS
		do
			ssh -t ${USER}@${HOST} -p ${SSHPORT} "mkdir -p ~/.secret/.ceph"
			scp -r -P ${SSHPORT} ${SECRET}/.ceph ${USER}@${HOST}:/home/${USER}/.secret
			ssh -t ${USER}@${HOST} -p ${SSHPORT} "
				cd ~/docker/docker-workshop/services/ceph
				./ws cleanclean
				cd /
				sudo tar pzxf ~/.secret/.ceph/ceph.secret.tgz
				"
		done
		;;
	"mon")
		shift
		HOSTS=$*
		for HOST in $HOSTS
		do
			HOSTIP=`eval "cat /etc/hosts | grep ' ${HOST} ' | cut -d ' ' -f 1"`
			ssh -t ${USER}@${HOST} -p ${SSHPORT} "
				cd ~/docker/docker-workshop/services/ceph
				./ws mon $HOSTIP $NETWORK
				"
		done
		;;
	"mgr")
		shift
		HOSTS=$*
		for HOST in $HOSTS
		do
			ssh -t ${USER}@${HOST} -p ${SSHPORT} "
				cd ~/docker/docker-workshop/services/ceph
				./ws mgr
				"
		done
		;;
	"osds")
		shift
		HOST=$1
		shift
		OSDS=$*
		ssh -t ${USER}@${HOST} -p ${SSHPORT} "
			cd ~/docker/docker-workshop/services/ceph
			./ws osds $OSDS
			"
		;;
	"mds")
		shift
		ACTIVEMDS=$1
		PGNUM=$2
		shift
		shift
		HOSTS=$*
		for HOST in $HOSTS
		do
			ssh -t ${USER}@${HOST} -p ${SSHPORT} "
				cd ~/docker/docker-workshop/services/ceph
				./ws mds $PGNUM
				./ws mdsmount $ACTIVEMDS
				"
		done
		;;
	"mdsmount")
		shift
		HOST=$1
		ACTIVEMDS=$2
		ssh -t ${USER}@${HOST} -p ${SSHPORT} "
			cd ~/docker/docker-workshop/services/ceph
			./ws mdsmount $ACTIVEMDS
			"
		;;
	"network-up")
		shift
		HOSTS=$*
		SECRET=${SECRET} $0 network-down $HOSTS
		for HOST in $HOSTS
		do
			for NODE in $HOSTS
			do
				ssh -t ${USER}@${HOST} -p ${SSHPORT} "
					sudo iptables -I INPUT -m multiport -p tcp -s $NODE --dport 111,6789,6800:7300 -j ACCEPT -m comment --comment 'ceph'
					sudo iptables -I INPUT -m multiport -p tcp -s $NODE --sport 111,6789,6800:7300 -j ACCEPT -m comment --comment 'ceph'
					"
			done
			ssh -t ${USER}@${HOST} -p ${SSHPORT} "sudo iptables-save | sudo tee /etc/iptables/rules.v4"
		done
		;;
	"network-down")
		shift
		HOSTS=$*
		for HOST in $HOSTS
		do
			for NODE in $HOSTS
			do
				ssh -t ${USER}@${HOST} -p ${SSHPORT} "
					sudo iptables -D INPUT -m multiport -p tcp -s $NODE --dport 111,6789,6800:7300 -j ACCEPT -m comment --comment 'ceph'
					sudo iptables -D INPUT -m multiport -p tcp -s $NODE --sport 111,6789,6800:7300 -j ACCEPT -m comment --comment 'ceph'
					"
			done
			ssh -t ${USER}@${HOST} -p ${SSHPORT} "sudo iptables-save | sudo tee /etc/iptables/rules.v4"
		done
		;;
	*)
		echo $(basename $0) initby host
		echo $(basename $0) deploy host1 host2...
		echo $(basename $0) mon host1 host2...
		echo $(basename $0) mgr host1 host2...
		echo $(basename $0) osds host osd1 osd2...
		echo $(basename $0) mds pgnum host1 host2...
		echo $(basename $0) mdsmount host mds-host...
		echo $(basename $0) network-up host1 host2...
		echo $(basename $0) network-down host1 host2...
		;;
esac

echo \# ceph-adm: done
echo ===

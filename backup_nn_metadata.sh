#!/usr/bin/env bash -l
#######################
# Backup the filesystem metadata for hadoop using namenode url
# Change the variables to match appropriate env and put this script in crontab
#######################

#Variables
TODAY=$(date +"%Y-%m-%d-%H%M")  #date and time
BACKUP_PATH="/home/hdfs/backup" #path to store metadata
NN_IP="192.168.1.62"            #Namenode ip address
NN_PORT="50070"                 #Namenode http port
RT_DAYS="3"                     #Rentention in days

#Logic
if [ -d ${BACKUP_PATH} ]; then
  cd ${BACKUP_PATH}
else
  mkdir -p ${BACKUP_PATH} && cd ${BACKUP_PATH}
fi

#download fsimage file
wget http://${NAMENODE_IP}:${NN_PORT}/getimage?getimage=1 -O fsimage -nv
if [ $? -eq 0 ]; then
  #download edits file
  wget http://${NAMENODE_IP}:${NN_PORT}/getimage?getedit=1 -O edits -nv
  if [ $? -eq 0 ]; then
    #compress the fsimage and edits file
    tar -zcf namenode-${TODAY}.tar.gz fsimage edits
    if [ $? -eq 0 ]; then
      #delete all backup up to days specified in RT_DAYS
      find -atime +${RT_DAYS} -name "namenode*" -exec rm {} \;
      rm fsimage #remove downloaded fsimage
      rm edits   #remove downloaded edits
    fi
  else
    rm fsimage  #remove downloaded fsimage
    exit 4
  fi
fi
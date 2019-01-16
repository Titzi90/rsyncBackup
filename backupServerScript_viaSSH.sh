#!/bin/bash

# This version of the script does use an encrypted protocol (SSH)


MOUNTPOINT="/..."
BASEDIR=${MOUNTPOINT}"/serverBackup"
SERVERS=("Server1,Server2")
SSH_USERS=("UserForServer1,UserForServer2")
EXCLUDES=("ignore_Server1,ignore_server2")
USERS=("backupUserServer1,backupUserServer2") # rsync user
PW_FILES=("paswordFileServer1,paswordFileServer2") # password for rsync user

#ACHTUNG: ACLs werden auf NAS nicht unterstützt ( -A)
RSYNC_OP="-aAXzh --numeric-ids --delete --ignore-errors --fake-super --stats"

#check if volume is mounted
if grep -qs ${MOUNTPOINT} /proc/mounts; then
	  #echo "target medium is mounted"
    logger -t backup -p local5.info "target medium is mounted"
else
	  #echo "target medium is NOT mounted"
	  logger -t backup -p local5.err "target medium is NOT mounted"
	  exit -3
fi

function daily_backup
{
    ### ARGUMENTS
    SERVER=$1
    MODULE=$2
    BASEDIR=$3
    EXCLUDES=$4
    RSYNC_USER=$5
    SSH_USER=$6
    PW_FILE=$7


    ### SCRIPT
    STARTDATE=$(date +'%Y-%m-%d %T')
    #echo "$STARTDATE start backup of ${SERVER}:${MODULE} ..."
    logger -t backup -p local5.notice "$STARTDATE start backup of ${SERVER}:${MODULE} ..."

    # Make sure passwort file exist
    if [ -f $PW_FILE ] ; then
	      # echo "Using password file: $PW_FILE"
	      logger -t backup -p local5.info "Using password file: $PW_FILE"
    else
	      # Fail
	      # echo "Could not find password file $EXCLUDES"
	      logger -t backup -p local5.err "Could not find password file $EXCLUDES"
	      return 2
    fi

    # Make sure file for excludelist exists
    if [ -f $EXCLUDES ] ; then
	      #echo "Using excludelist: $EXCLUDES"
	      logger -t backup -p local5.info "Using excludelist: $EXCLUDES"
    else
	      # Fail
	      #echo "Could not find excludelist $EXCLUDES"
	      logger -t backup -t local5.err "Could not find excludelist $EXCLUDES"
	      return 2
    fi

    # on the 1st of each month do a monthly backup
    day=$(date +'%d')
    if [ $day -eq 01 ]; then
        POSTFIX="monthly"
    else
        POSTFIX="daily"
    fi

    # define directory for backups
    DATA_PATH=${BASEDIR}/${SERVER}/${MODULE}

    # create backup dir if it dos not exist
    if ! [ -d ${DATA_PATH} ] ; then
        mkdir -p ${DATA_PATH}
    fi

    # finds newest backup
    NEWEST_BACKUP=$(                                                                     \
                    ls -d ${DATA_PATH}/20[0-9][0-9]-[0-9][0-9]-[0-9][0-9].* 2> /dev/null \
                    | tail --lines=1)
    NEWEST_BACKUP=$(realpath ${NEWEST_BACKUP} 2> /dev/null)

    # finds out the oldest daily backup
    OLDEST_DAILY_BACKUP=$(                                                                         \
                          ls -d ${DATA_PATH}/20[0-9][0-9]-[0-9][0-9]-[0-9][0-9].daily 2> /dev/null \
                          | head --lines=1)

    # counts the number of daily backups
    DAILY_BACKUP_COUNT=$(                                                                         \
                         ls -d ${DATA_PATH}/20[0-9][0-9]-[0-9][0-9]-[0-9][0-9].daily 2> /dev/null \
                         | wc -l)

    # today date used for new backup
    DATE=$(date +'%Y-%m-%d')

    # gives an error when there already is a backup from the same day
    if test -d ${DATA_PATH}/${DATE}.* ; then
        # echo "Ein aktuelles Backup existiert bereits";
        logger -t backup -p local5.warning "Ein aktuelles Backup existiert bereits";
        return 1;
    fi;

    # use oldest daily backup as basis for new backup
    # if we have more than 31 daily backups
    # otherwise create new directory for backup
    if [ $DAILY_BACKUP_COUNT -gt "31" ]; then
        mv ${OLDEST_DAILY_BACKUP} ${DATA_PATH}/${DATE}.${POSTFIX}

        # echo "use ${OLDEST_DAILY_BACKUP} backup as basis for new backup"
        logger -t backup -p local5.info "use ${OLDEST_DAILY_BACKUP} backup as basis for new backup"
    else
        mkdir ${DATA_PATH}/${DATE}.${POSTFIX}
    fi

    # SYNC data
    rsync -e "ssh -l ${SSH_USER}"                \
        ${RSYNC_OP}                              \
        --link-dest=${NEWEST_BACKUP}             \
        --exclude-from="${EXCLUDES}"             \
        --password-file="${PW_FILE}"             \
        ${RSYNC_USER}@${SERVER}::${MODULE}       \
        ${DATA_PATH}/${DATE}.${POSTFIX}/

    # Validate return code
    # 0 = no error,
    # 24 is fine, happens when files are being touched during sync (logs etc)
    # all other codes are fatal -- see man (1) rsync
    if ! [ $? = 24 -o $? = 0 ] ; then
        ENDDATE=$(date +'%Y-%m-%d %T')
	      # echo "${ENDDATE} ${SERVER}:${MODULE} Fatal: rsync finished with errors!"
	      logger -t backup -p local5.err "${ENDDATE} ${SERVER}:${MODULE} Fatal: rsync finished with errors!"
        return 3
    fi

    # Touch dir to set backup date
    touch ${DATA_PATH}/${DATE}.${POSTFIX}

    # Sync disks to make sure data is written to disk
    sync

    ENDDATE=$(date +'%Y-%m-%d %T')
    # echo "$ENDDATE ${SERVER}:${MODULE} Finished daily snapshots"
    logger -t backup -p user5.notice "$ENDDATE ${SERVER}:${MODULE} Finished daily snapshots"
}




# create backup for all defined modules
for SERVER in ${!SERVERS[*]}; do
    #get modulules from server
    MODULES=$(rsync -e "ssh -l ${SSH_USERS[$SERVER]}" ${SERVERS[$SERVER]}:: | grep -Eo '^[^ ]+')
    #echo modules at ${SERVERS[$SERVER]}: ${MODULES}

    for MODULE in ${MODULES}; do
        #echo "sync ${MODULE} from ${SERVERS[$i]}"
	      diaily_backup ${SERVERS[$SERVER]} ${MODULE} $BASEDIR \
                      ${EXCLUDES[$SERVER]} ${USERS[$SERVER]} \
                      ${SSH_USERS[$SERVER]} ${PW_FILES[$SERVER]}
	      # echo; echo "#########################" ; echo;
    done
done

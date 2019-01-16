#! /bin/sh

CONTAINER=$1
TARGET=$2

DATE=$(date +'%Y--%m-%d')

if [ ! -d "${TARGET}" ]; then
  mkdir -p ${TARGET}
fi

#TODO logging

docker exec ${CONTAINER} sh -c 'exec mysqldump --all-databases --single-transaction -uroot -p"$MYSQL_ROOT_PASSWORD"' > ${TARGET}/${CONTAINER}.sql

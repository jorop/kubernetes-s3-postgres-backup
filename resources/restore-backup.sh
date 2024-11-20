#!/bin/sh

COMMAND=$1
S3_HOST=${AWS_S3_ENDPOINT#"https://"}
if [ "list" = "$COMMAND" ]
then
  s3cmd --host=$S3_HOST --host-bucket=$AWS_S3_ENDPOINT/$AWS_BUCKET_NAME -v ls s3://$AWS_BUCKET_NAME$AWS_BUCKET_BACKUP_PATH/
elif [ "restore" = "$COMMAND" ]
then
  S3_FILE=$2
  DATABASE_NAME=$3
  SECURITY_BKP=/tmp/security_bkp.sql
  # download, decrypt and extract backup
  echo Restoring $S3_FILE into $DATABASE_NAME
  s3cmd --host=$S3_HOST --host-bucket=$AWS_S3_ENDPOINT/$AWS_BUCKET_NAME -v sync $S3_FILE /tmp/bkp.bz2.ssl
  openssl smime -decrypt -in /tmp/bkp.bz2.ssl -binary -inform DEM -inkey /pgbkp/backup_prod_key.pem -out /tmp/bkp.bz2
  bzip2 -d /tmp/bkp.bz2
  echo Downloaded and extracted $S3_FILE
  # make a backup before restore
  if psgloutput=$(pg_dump -U $TARGET_DATABASE_USER -h $TARGET_DATABASE_HOST -p $TARGET_DATABASE_PORT $DATABASE_NAME -f $SECURITY_BKP 2<&1)
  then 
    echo Security backup is stored temporarily at $SECURITY_BKP
  else
    echo $psgloutput
    exit 1
  fi
  # delete database
  if psgloutput=$(dropdb -U $TARGET_DATABASE_USER -h $TARGET_DATABASE_HOST -p $TARGET_DATABASE_PORT --if-exists $DATABASE_NAME)
  then
    echo Dropped database $DATABASE_NAME
  else
    echo $psqloutput
    exit 1
  fi
  # create db
  if psqloutput=$(psql -U $TARGET_DATABASE_USER -h $TARGET_DATABASE_HOST -p $TARGET_DATABASE_PORT -c "CREATE DATABASE $DATABASE_NAME;"  2>&1)
  then
    echo Created database $DATABASE_NAME
  else
    echo $psqloutput
    exit 1
  fi
  # restore backup
  if psqloutput=$(psql -U $TARGET_DATABASE_USER -h $TARGET_DATABASE_HOST -p $TARGET_DATABASE_PORT -d $DATABASE_NAME < /tmp/bkp.sql  2>&1)
  then
    echo Restored backup into database $DATABASE_NAME
  else
    echo $psqloutput
  fi
else
  echo " Usage"
  echo "   ./restore-backup.sh [COMMAND] <params>"
  echo "     COMMAND"
  echo "        list - list backups in current s3 bucket path"
  echo "        restore - restore backup with params"
  echo "     params"
  echo "        1 - s3 file - file name of backup to restore"
  echo "        2 - database name - database name to restore backup into"
fi
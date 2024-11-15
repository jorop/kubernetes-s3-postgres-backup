#/bin/sh
# Set the has_failed variable to false. This will change if any of the subsequent database backups/uploads fail.
has_failed=false

# Loop through all the defined databases, seperating by a ,
for CURRENT_DATABASE in ${TARGET_DATABASE_NAMES}
do

    # Perform the database backup. Put the output to a variable. If successful upload the backup to S3, if unsuccessful print an entry to the console and the log, and set has_failed to true.
    if sqloutput=$(pg_dump -U $TARGET_DATABASE_USER -h $TARGET_DATABASE_HOST -p $TARGET_DATABASE_PORT $CURRENT_DATABASE | bzip2 | openssl smime -encrypt -aes256 -binary -outform DEM -out /tmp/$CURRENT_DATABASE.bz2.ssl /pgbkp/backup_prod_key.pem.pub)
    then
        
        echo -e "Database backup successfully completed for $CURRENT_DATABASE at $(date +'%d-%m-%Y %H:%M:%S')."
        
        # If the AWS_S3_ENDPOINT variable isn't empty, then populate the --endpoint-url parameter to use a custom S3 compatable endpoint
        if [ ! -z "$AWS_S3_ENDPOINT" ]; then
            ENDPOINT="--endpoint-url=$AWS_S3_ENDPOINT"
        fi

        # Perform the upload to S3. Put the output to a variable. If successful, print an entry to the console and the log. If unsuccessful, set has_failed to true and print an entry to the console and the log
        if awsoutput=$(aws $ENDPOINT s3 cp /tmp/$DUMP s3://$AWS_BUCKET_NAME$AWS_BUCKET_BACKUP_PATH/$DUMP 2>&1); then
            echo -e "Database backup successfully uploaded for $CURRENT_DATABASE at $(date +'%d-%m-%Y %H:%M:%S')."
        else
            echo -e "Database backup failed to upload for $CURRENT_DATABASE at $(date +'%d-%m-%Y %H:%M:%S'). Error: $awsoutput" | tee -a /tmp/kubernetes-cloud-mysql-backup.log
            has_failed=true
        fi
        rm /tmp/"$DUMP"
        
    else
        echo -e "Database backup FAILED for $CURRENT_DATABASE at $(date +'%d-%m-%Y %H:%M:%S'). Error: $sqloutput" | tee -a /tmp/kubernetes-s3-postgres-backup.log
        has_failed=true
    fi

done

# Check if any of the backups have failed. If so, exit with a status of 1. Otherwise exit cleanly with a status of 0.
if [ "$has_failed" = true ]
then

    # If Slack alerts are enabled, send a notification alongside a log of what failed
    if [ "$SLACK_ENABLED" = true ]
    then
        # Put the contents of the database backup logs into a variable
        logcontents=`cat /tmp/kubernetes-s3-postgres-backup.log`

        # Send Slack alert
        /slack-alert.sh "One or more backups on database host $TARGET_DATABASE_HOST failed. The error details are included below:" "$logcontents"
    fi

    echo -e "kubernetes-s3-postgres-backup encountered 1 or more errors. Exiting with status code 1."
    exit 1

else

    # If Slack alerts are enabled, send a notification that all database backups were successful
    if [ "$SLACK_ENABLED" = true ]
    then
        /slack-alert.sh "All database backups successfully completed on database host $TARGET_DATABASE_HOST."
    fi

    exit 0
    
fi

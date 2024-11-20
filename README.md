# kubernetes-s3-postgres-backup

kubernetes-s3-postgres-backup is a container image based on Alpine Linux. This container is designed to run in Kubernetes as a cronjob to perform automatic backups of postgres databases to Amazon S3 or S3 compatible object storage like minio. It was created to meet my requirements for regular and automatic database backups. Having started with a relatively basic feature set, it is gradually growing to add more and more features.

Currently, kubernetes-s3-postgres-backup supports the backing up of postgres Databases. It can perform backups of multiple postgres databases from a single database host. When triggered, a full database dump is performed using the `pg_dump` command for each configured database. The backup(s) are then uploaded to an Amazon S3 Bucket. kubernetes-s3-postgres-backup features Slack Integration, and can post messages into a channel detailing if the backup(s) were successful or not.

## Environment Variables

The below table lists all of the Environment Variables that are configurable for kubernetes-s3-postgres-backup.

| Environment Variable        | Purpose                                                                                                          |
| --------------------------- |------------------------------------------------------------------------------------------------------------------|
| CLUSTER_NAME                | **(Optional)** Will be added as prefix of the backup file name.                                                  |
| AWS_ACCESS_KEY_ID           | **(Required)** AWS IAM Access Key ID.                                                                            |
| AWS_SECRET_ACCESS_KEY       | **(Required)** AWS IAM Secret Access Key. Should have very limited IAM permissions (see below for example) and should be configured using a Secret in Kubernetes.                                                                                                         |
| AWS_DEFAULT_REGION          | **(Required)** Region of the S3 Bucket (e.g. eu-west-2).                                                         |
| AWS_BUCKET_NAME             | **(Required)** The name of the S3 bucket.                                                                        |
| AWS_BUCKET_BACKUP_PATH      | **(Required)** Path the backup file should be saved to in S3. E.g. `/database/myblog/backups`. **Do not put a trailing / or specify the filename.**  
| AWS_S3_ENDPOINT             | **(Optional)** Endpoint other than AWS. E.g. `https://s3-storage.example.com`                                                                                        |
| TARGET_DATABASE_HOST        | **(Required)** Hostname or IP address of the postgres Host.                                                         |
| TARGET_DATABASE_PORT        | **(Optional)** Port postgres is listening on (Default: 5432).                                                       |
| TARGET_DATABASE_NAMES       | **(Required)** Name of the databases to dump. This should be comma seperated (e.g. `database1,database2`).       |
| TARGET_DATABASE_USER        | **(Required)** Username to authenticate to the database with.                                                    |
| PGPASSWORD                  | **(Required)** Password to authenticate to the database with. Should be configured using a Secret in Kubernetes. |
| SLACK_ENABLED               | **(Optional)** (true/false) Enable or disable the Slack Integration (Default False).                             |
| SLACK_USERNAME              | **(Optional)** (true/false) Username to use for the Slack Integration (Default: kubernetes-s3-postgres-backup).            |
| SLACK_CHANNEL               | **(Required if Slack enabled)** Slack Channel the WebHook is configured for.                                     |
| SLACK_WEBHOOK_URL           | **(Required if Slack enabled)** What is the Slack WebHook URL to post to? Should be configured using a Secret in Kubernetes.                                                                                                                                      |


## Slack Integration

kubernetes-s3-postgres-backup supports posting into Slack after each backup job completes. The message posted into the Slack Channel varies as detailed below:

* If the backup job is **SUCCESSFUL**: A generic message will be posted into the Slack Channel detailing that all database backups successfully completed.
* If the backup job is **UNSUCCESSFUL**: A message will be posted into the Slack Channel with a detailed error message for each database that failed.

In order to configure kubernetes-s3-postgres-backup to post messages into Slack, you need to create an [Incoming WebHook](https://api.slack.com/incoming-webhooks). Once generated, you can configure kubernetes-s3-postgres-backup using the environment variables detailed above.

## Configuring the S3 Bucket & AWS IAM User

kubernetes-s3-postgres-backup performs a backup to the same path, with the same filename each time it runs. It therefore assumes that you have Versioning enabled on your S3 Bucket. A typical setup would involve S3 Versioning, with a Lifecycle Policy.

An IAM Users should be created, with API Credentials. An example Policy to attach to the IAM User (for a minimal permissions set) is as follows:

```
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "VisualEditor0",
            "Effect": "Allow",
            "Action": "s3:ListBucket",
            "Resource": "arn:aws:s3:::<BUCKET NAME>"
        },
        {
            "Sid": "VisualEditor1",
            "Effect": "Allow",
            "Action": [
                "s3:PutObject"
            ],
            "Resource": "arn:aws:s3:::<BUCKET NAME>/*"
        }
    ]
}
```


## Example Kubernetes Cronjob

An example of how to schedule this container in Kubernetes as a cronjob is below. This would configure a database backup to run each day at 01:00am. The AWS Secret Access Key, and Target Database Password are stored in secrets.

```
apiVersion: v1
kind: Secret
metadata:
  name: AWS_SECRET_ACCESS_KEY
type: Opaque
data:
  aws_secret_access_key: <AWS Secret Access Key>
---
apiVersion: v1
kind: Secret
metadata:
  name: TARGET_DATABASE_PASSWORD
type: Opaque
data:
  database_password: <Your Database Password>
---
apiVersion: v1
kind: Secret
metadata:
  name: SLACK_WEBHOOK_URL
type: Opaque
data:
  slack_webhook_url: <Your Slack WebHook URL>
---
apiVersion: v1
kind: Secret
metadata:
  name: pubkey-backup
type: Opaque
data:
  backup_prod_key.pem.pub: <Your Public Key>
---
apiVersion: v1
kind: Secret
metadata:
  name: key-restore
type: Opaque
data:
  backup_prod_key.pem: <Your Private Key>
---
apiVersion: batch/v1
kind: CronJob
metadata:
  name: my-database-backup
spec:
  schedule: "0 01 * * *"
  jobTemplate:
    spec:
      template:
        spec:
          volumes:
          - name: public-key
            secret:
              secretName: pubkey-backup
          containers:
          - name: my-database-backup
            image: jorop/kubernetes-s3-postgres-backup
            imagePullPolicy: Always
            volumeMounts:
            - name: public-key
              mountPath: "/pgbkp"
              readOnly: true
            env:
              - name: CLUSTER_NAME
                value: "myCluster"
              - name: AWS_S3_ENDPOINT
                value: https://s3.example.com 
              - name: AWS_ACCESS_KEY_ID
                value: "<Your Access Key>"
              - name: AWS_SECRET_ACCESS_KEY
                valueFrom:
                   secretKeyRef:
                     name: AWS_SECRET_ACCESS_KEY
                     key: aws_secret_access_key
              - name: AWS_DEFAULT_REGION
                value: "<Your S3 Bucket Region>"
              - name: AWS_BUCKET_NAME
                value: "<Your S3 Bucket Name>"
              - name: AWS_BUCKET_BACKUP_PATH
                value: "<Your S3 Bucket Backup Path>"
              - name: TARGET_DATABASE_HOST
                value: "<Your Target Database Host>"
              - name: TARGET_DATABASE_PORT
                value: "<Your Target Database Port>"
              - name: TARGET_DATABASE_NAMES
                value: "<Your Target Database Name(s)>"
              - name: TARGET_DATABASE_USER
                value: "<Your Target Database Username>"
              - name: PGPASSWORD
                valueFrom:
                   secretKeyRef:
                     name: TARGET_DATABASE_PASSWORD
                     key: database_password
              - name: SLACK_ENABLED
                value: "<true/false>"
              - name: SLACK_CHANNEL
                value: "#chatops"
              - name: SLACK_WEBHOOK_URL
                valueFrom:
                   secretKeyRef:
                     name: SLACK_WEBHOOK_URL
                     key: slack_webhook_url
          restartPolicy: Never
```

## Generate SSL Encrypt Key

You needs to generate a private/public key for the database encryption. The public key will be added into the container for encryption and then you will use in a future the private one for decrypt the backup.

To generate the keys you can use the following commands:

```
openssl req -x509 -nodes -newkey rsa:4096 -keyout YOUR_BACKUP_PRIVATE_key.pem \
 -subj "/C=AR/ST=CBA/L=CBA/O=IT/CN=www.yourdomain.com" \
 -out YOUR_BACKUP_key.pem.pub
```

## Restore procedure
### Option 1
 
Create a pod like `Restore.yml`  
> When restoring from e.g. bitnami postgresql chart the `postgres` user should be used to restore the database, in any case the user should be able to drop and create a database on the db instance. 

The script `restore-backup.sh` will list the available options when invoked.
- `./restore-backup.sh list` -> list the available backups in the s3 bucket
- `./restore-backup.sh restore filename-in-s3-bucket database-name` -> restore backup into database; a backup will be created at `/tmp/security_bkp.sql`, then the database will be dropped completely and restored from the backup of the chosen file in the s3-bucket

### Option 2

You can use the following procedure in order to restore your backups 

1.- Download Backup File encrypted from S3 Bucket

2.- Decrypt the File:
```$ openssl smime -decrypt -in your_database_backup-02-08-2019-02_10_11.bz2.ssl -binary -inform DEM -inkey YOUR_BACKUP_PRIVATE_key.pem -out your_database_backup-02-08-2019-02_10_11.bz2```

3.- Unzip File:
```bzip2 -d your_database_backup-02-08-2019-02_10_11.bz2```

4.- Copy File to POD:
```kubectl cp /path/to/backup/your_database_backup-02-08-2019-02_10_11/your_database_backup-02-08-2019-02_10_11 yourNameSpace/your-db-pod-jdvb7:tmp/```

5.- Login to POD:
```kubectl exec -it your-db-pod-jdvb7 bash```

6.- Change to postgres user:
```su - postgres```

7.- Restore File:
```psql -U db_user db_name < /tmp/your_database_backup-02-08-2019-02_10_11```

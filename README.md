# kubernetes-s3-postgres-backup

kubernetes-s3-postgres-backup is a container image based on Alpine Linux. This container is designed to run in Kubernetes as a cronjob to perform automatic backups of postgres databases to Amazon S3. It was created to meet my requirements for regular and automatic database backups. Having started with a relatively basic feature set, it is gradually growing to add more and more features.

Currently, kubernetes-s3-postgres-backup supports the backing up of postgres Databases. It can perform backups of multiple postgres databases from a single database host. When triggered, a full database dump is performed using the `pg_dump` command for each configured database. The backup(s) are then uploaded to an Amazon S3 Bucket. kubernetes-s3-postgres-backup features Slack Integration, and can post messages into a channel detailing if the backup(s) were successful or not.

## Environment Variables

The below table lists all of the Environment Variables that are configurable for kubernetes-s3-postgres-backup.

| Environment Variable        | Purpose                                                                                                          |
| --------------------------- |------------------------------------------------------------------------------------------------------------------|
| AWS_ACCESS_KEY_ID           | **(Required)** AWS IAM Access Key ID.                                                                            |
| AWS_SECRET_ACCESS_KEY       | **(Required)** AWS IAM Secret Access Key. Should have very limited IAM permissions (see below for example) and should be configured using a Secret in Kubernetes.                                                                                                         |
| AWS_DEFAULT_REGION          | **(Required)** Region of the S3 Bucket (e.g. eu-west-2).                                                         |
| AWS_BUCKET_NAME             | **(Required)** The name of the S3 bucket.                                                                        |
| AWS_BUCKET_BACKUP_PATH      | **(Required)** Path the backup file should be saved to in S3. E.g. `/database/myblog/backups`. **Do not put a trailing / or specify the filename.**                                                                                                        |
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
apiVersion: batch/v1beta1
kind: CronJob
metadata:
  name: my-database-backup
spec:
  schedule: "0 01 * * *"
  jobTemplate:
    spec:
      template:
        spec:
          containers:
          - name: my-database-backup
            image: gcr.io/maynard-io-public/kubernetes-s3-postgres-backup
            imagePullPolicy: Always
            env:
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
              - name: TARGET_DATABASE_PASSWORD
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

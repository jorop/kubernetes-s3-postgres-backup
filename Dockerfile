# Set the base image
FROM alpine:3.20.3

RUN apk -v --update add \
        python3 \
        py-pip \
        groff \
        less \
        mailcap \
        openssl \
        postgresql14-client \
        curl
RUN rm /usr/lib/python*/EXTERNALLY-MANAGED && \
    python3 -m ensurepip
RUN pip3 install awscli s3cmd python-magic
RUN apk -v --purge del py-pip && \
    rm /var/cache/apk/*

# Set Default Environment Variables
ENV TARGET_DATABASE_PORT=5432
ENV SLACK_ENABLED=false
ENV SLACK_USERNAME=kubernetes-s3-postgres-backup
RUN mkdir /pgbkp
# Copy Slack Alert script and make executable
COPY resources/slack-alert.sh /
RUN chmod +x /slack-alert.sh

# Copy backup script and execute
COPY resources/perform-backup.sh /
RUN chmod +x /perform-backup.sh
CMD ["sh", "/perform-backup.sh"]

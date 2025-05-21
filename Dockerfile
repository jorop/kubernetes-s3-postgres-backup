# Set the base image
FROM alpine:3.20.3

RUN apk upgrade --no-cache && apk -v --update add \
        python3 \
        py-pip \
        groff \
        less \
        mailcap \
        openssl \
        curl
RUN echo 'http://dl-cdn.alpinelinux.org/alpine/edge/main' > /etc/apk/repositories
RUN apk update --allow-untrusted
RUN apk upgrade --allow-untrusted
RUN apk add postgresql17-client --allow-untrusted
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

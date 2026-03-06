FROM postgres:18-alpine

RUN apk add --no-cache tzdata python3 py3-pip \
  && pip install --break-system-packages --no-cache-dir awscli

COPY backup.sh /backup.sh
RUN chmod +x /backup.sh

CMD sh -c "sleep 1800; while true; do /backup.sh; sleep 3600; done"
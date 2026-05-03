FROM postgres:18-alpine

RUN apk add --no-cache tzdata python3 py3-pip \
  && pip install --break-system-packages --no-cache-dir awscli

COPY backup.sh /backup.sh
RUN chmod +x /backup.sh

# Execução única (ex.: `docker compose --profile backup-tools run --rm backup-tools`).
# Agendamento em produção: Temporal `system-backup-cron` + system_config `runtime.scheduled_backup.*`.
CMD ["/backup.sh"]

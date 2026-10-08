FROM ubuntu:22.04

RUN apt-get update \
    && apt-get install -y --no-install-recommends procps python3 \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /var/www
ENV LOG_FILE=/var/www/monitor.log PYTHONUNBUFFERED=1

COPY script.sh /usr/local/bin/script.sh
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/script.sh /usr/local/bin/entrypoint.sh

EXPOSE 8080
CMD ["/usr/local/bin/entrypoint.sh"]

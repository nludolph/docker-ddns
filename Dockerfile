FROM ubuntu:focal-20200916 as builder
RUN apt-get update \
	&& DEBIAN_FRONTEND=noninteractive apt-get install -y \
	     golang git-core \
	&& apt-get clean

ENV GOPATH=/root/go
RUN mkdir -p /root/go/src
COPY rest-api /root/go/src/dyndns
RUN cd /root/go/src/dyndns && go get && go test -v

FROM ubuntu:focal-20200916

ENV BIND_USER=bind \
    DATA_DIR=/data

RUN rm -rf /etc/apt/apt.conf.d/docker-gzip-indexes \
	&& apt-get update \
	&& DEBIAN_FRONTEND=noninteractive apt-get install -y \
	     bind9 bind9-host dnsutils \
	&& apt-get clean \
	&& rm -rf /var/lib/apt/lists/*

RUN chmod 770 /var/cache/bind
COPY entrypoint.sh /root/entrypoint.sh
RUN chmod +x /root/entrypoint.sh
COPY named.conf.options /etc/bind/named.conf.options
COPY --from=builder /root/go/bin/dyndns /root/dyndns

EXPOSE 53/udp 53/tcp  8080/tcp

ENTRYPOINT ["/bin/bash","/root/entrypoint.sh"]

CMD ["/usr/sbin/named"]

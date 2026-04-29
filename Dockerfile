FROM alpine:3.21
RUN apk add --no-cache unbound
RUN wget -O /etc/unbound/named.root https://www.internic.net/domain/named.root
RUN unbound-anchor -a /etc/unbound/trusted-key.key; exit 0
COPY unbound.conf /etc/unbound/unbound.conf
EXPOSE 5335/tcp
EXPOSE 5335/udp
CMD ["unbound", "-d"]

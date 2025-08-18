FROM ubuntu:latest

RUN apt-get update && \
    apt-get install -y \
        apache2

WORKDIR "/var/www/html/debian"

COPY ./packages/ .

RUN dpkg-scanpackages . /dev/null | gzip -9c > Packages.gz

CMD ["apachectl", "-D", "FOREGROUND"]

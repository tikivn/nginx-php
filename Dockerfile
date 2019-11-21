FROM ubuntu:18.04
MAINTAINER Hoa Nguyen <hoa.nguyenmanh@tiki.vn>

# ENV
ENV DEBIAN_FRONTEND noninteractive
ENV LANG       en_US.UTF-8
ENV LC_ALL     en_US.UTF-8
ENV TZ         Asia/Saigon

SHELL ["/bin/bash", "-c"]

# timezone and locale
RUN apt-get update \
    && apt-get install -y software-properties-common \
        language-pack-en-base sudo \
        apt-utils tzdata locales \
        curl wget gcc g++ make autoconf libc-dev pkg-config \
    && locale-gen en_US.UTF-8 \
    && echo $TZ > /etc/timezone \
    && ln -snf /usr/share/zoneinfo/$TZ /etc/localtime \
    && dpkg-reconfigure -f noninteractive tzdata \
    && apt-get autoclean \
    && rm -vf /var/lib/apt/lists/*.* /tmp/* /var/tmp/*

# nginx php newrelic
RUN add-apt-repository -y ppa:nginx/stable \
    && add-apt-repository ppa:ondrej/php \
    && echo 'deb http://apt.newrelic.com/debian/ newrelic non-free' > /etc/apt/sources.list.d/newrelic.list \
    && curl -sSL https://download.newrelic.com/548C16BF.gpg | apt-key add - \
    && apt-get update \
    && apt-get install -y build-essential \
    zlib1g-dev \
    vim \
    unzip \
    sudo \
    dialog \
    net-tools \
    git \
    supervisor \
    python-pip \
    nginx \
    ruby-dev \
    php7.2-common \
    php7.2-dev \
    php7.2-fpm \
    php7.2-bcmath \
    php7.2-curl \
    php7.2-gd \
    php7.2-geoip \
    php7.2-imagick \
    php7.2-intl \
    php7.2-json \
    php7.2-ldap \
    php7.2-mbstring \
    php7.2-memcache \
    php7.2-memcached \
    php7.2-mongo \
    php7.2-mysqlnd \
    php7.2-pgsql \
    php7.2-redis \
    php7.2-sqlite \
    php7.2-xml \
    php7.2-xmlrpc \
    php7.2-zip \
    php7.2-soap \
    php7.2-xdebug \
    php7.2-amqp \
    newrelic-php5 \
&& phpdismod xdebug newrelic opcache \
&& (curl -L https://toolbelt.treasuredata.com/sh/install-ubuntu-bionic-td-agent3.sh | sh) \
&& pip install superlance slacker \
&& mkdir /run/php && chown www-data:www-data /run/php \
&& apt-get autoclean \
&& rm -vf /var/lib/apt/lists/*.* /var/tmp/*

# Install php-snappy
RUN git clone -b 0.1.9 --recursive --depth=1 https://github.com/kjdev/php-ext-snappy.git \
    && cd php-ext-snappy \
    && phpize \
    && ./configure && make && make install \
    && echo "extension=snappy.so" > /etc/php/7.2/mods-available/snappy.ini \
    && phpenmod snappy \
    && cd .. && rm -rf php-ext-snappy

# Install php-rdkafka
RUN curl -sSL https://github.com/edenhill/librdkafka/archive/v0.11.5.tar.gz | tar xz \
    && cd librdkafka-0.11.5 \
    && ./configure && make && make install \
    && cd .. && rm -rf librdkafka-0.11.5

RUN curl -sSL https://github.com/arnaud-lb/php-rdkafka/archive/3.0.5.tar.gz | tar xz \
    && cd php-rdkafka-3.0.5 \
    && phpize && ./configure && make all && make install \
    && echo "extension=rdkafka.so" > /etc/php/7.2/mods-available/rdkafka.ini \
    && phpenmod rdkafka \
    && cd .. && rm -rf php-rdkafka-3.0.5

# Install GRPC & Protobuf
RUN pecl install grpc \
    && echo "extension=grpc.so" > /etc/php/7.2/mods-available/grpc.ini \
    && phpenmod grpc \
    && pecl install protobuf \
    && echo "extension=protobuf.so" > /etc/php/7.2/mods-available/protobuf.ini \
    && phpenmod protobuf

# Install nodejs, npm, phalcon & composer
RUN curl -sL  https://deb.nodesource.com/setup_10.x | bash -\
&& apt-get install -y nodejs \
&& curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/bin --filename=composer \
&& ln -fs /usr/bin/nodejs /usr/local/bin/node \
&& npm config set registry http://registry.npmjs.org \
&& npm config set strict-ssl false \
&& npm install -g --unsafe-perm=true aglio bower grunt-cli gulp-cli \
&& apt-get autoclean \
&& rm -vf /var/lib/apt/lists/*.*

# Install Yarn
RUN curl -sS https://dl.yarnpkg.com/debian/pubkey.gpg |  apt-key add - \
&& echo "deb https://dl.yarnpkg.com/debian/ stable main" |  tee /etc/apt/sources.list.d/yarn.list \
&&  apt-get update \
&&  apt-get install yarn -y \
&& apt-get autoclean \
&& rm -vf /var/lib/apt/lists/*.*

# install telegraf
RUN wget -qO- https://repos.influxdata.com/influxdb.key | sudo apt-key add - \
    && source /etc/lsb-release \
    && echo "deb https://repos.influxdata.com/${DISTRIB_ID,,} ${DISTRIB_CODENAME} stable" | sudo tee /etc/apt/sources.list.d/influxdb.list \
    && sudo apt-get update \
    && sudo apt-get install telegraf

# Install superslacker (supervisord notify to slack)
RUN curl -sSL https://raw.githubusercontent.com/luk4hn/superslacker/state_change_msg/superslacker/superslacker.py > /usr/local/bin/superslacker \
    && chmod 755 /usr/local/bin/superslacker

# Install Beeinstant metric monitoring

RUN wget https://beeinstant.com/statsbee.tar.gz \
    && tar zxvf statsbee.tar.gz \
    && cp -R agent /opt/statsbee

# Install google fluentd plugin
RUN td-agent-gem install fluent-plugin-google-cloud

# configuration
COPY conf/nginx/vhost.conf /etc/nginx/sites-available/default
COPY conf/nginx/nginx.conf /etc/nginx/nginx.conf
COPY conf/php72/php.ini /etc/php/7.2/fpm/php.ini
COPY conf/php72/cli.php.ini /etc/php/7.2/cli/php.ini
COPY conf/php72/php-fpm.conf /etc/php/7.2/fpm/php-fpm.conf
COPY conf/php72/www.conf /etc/php/7.2/fpm/pool.d/www.conf
COPY conf/supervisor/supervisord.conf /etc/supervisord.conf
COPY conf/supervisor/conf.d/* /etc/supervisor/conf.d/
COPY conf/td-agent/td-agent.conf /etc/td-agent/td-agent.conf
COPY conf/telegraf /etc/telegraf

# Forward request and error logs to docker log collector
RUN ln -sf /dev/stdout /var/log/nginx/access.log
RUN ln -sf /dev/stderr /var/log/nginx/error.log

# Start Supervisord
COPY ./start.sh /start.sh
RUN chmod 755 /start.sh

EXPOSE 80 443

CMD ["/bin/bash", "/start.sh"]

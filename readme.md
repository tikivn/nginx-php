## Introduction
This is a Dockerfile to build a container image for nginx and php-fpm for PHP projects

## Git repository
The source files for this project can be found here: https://github.com/tikivn/tikit-docker-nginx-php

## Pulling from Docker Hub
Pull the image from docker hub rather than downloading the git repo. This prevents you having to build the image on every docker host:

```
docker pull tikivn/tikit-nginx-php
```

## Running
To simply run the container:

```
docker run --name nginx-php -p 8080:80 -d tikivn/tikit-nginx-php
```

You can then browse to http://localhost:8080 to verify.

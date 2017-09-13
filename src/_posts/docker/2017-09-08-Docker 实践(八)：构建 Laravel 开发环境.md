---
layout: post
title: "Docker 实践(八)：构建 Laravel 开发环境"
author: "Tairy"
tag: "docker"
---

> 有人在 [SegmentFault](http:sf.gg) 上邀请我回答问题：[请问下有人使用Docker来安装Laravel本地开发环境吗](https://segmentfault.com/q/1010000007871262?_ea=1478295)，随手写了篇答案，记录下。

首先需要明确，一容器一进程，多容器协作完成。

所以，需要以下四个容器：

1. nginx
   - 作用：响应 web 请求，处理静态文件。
   - 镜像：无需自己构建，直接拉去官方镜像。
2. php-fpm
   - 作用：处理 PHP 脚本。
   - 镜像：由于项目中可能依赖不同的扩展，需要依赖官方镜像自行构建， 另外还需要 composer 支持。
3. mysql
	- 作用：数据库。
	- 镜像：无需自己构建，直接拉去官方镜像。
4. redis
   - 作用：缓存数据库。
   - 镜像：无需自己构建，直接拉去官方镜像。

下面说一下 php-fpm 镜像的构建，需要注意以下几点：

- 直接依赖官方的 `php:7.0.12-fpm` 镜像即可，无需自己从头开始构建。
- 不当玩具使用的话最好不要使用 `alpine` 系列的镜像，虽然它小巧玲珑。

一个简单的 dockerfile 示例：

```bash
FROM php:7.0.12-fpm
MAINTAINER Tairy <tairyguo@gmail.com>

WORKDIR /working
RUN apt-get update --fix-missing && apt-get install -y \
    g++ autoconf bash git apt-utils libxml2-dev libcurl3-dev pkg-config \
    && ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime \
    && echo "Asia/Shanghai" > /etc/timezone \
    && docker-php-ext-install iconv curl mbstring \
        xml json mcrypt mysqli pdo pdo_mysql zip \
    && docker-php-ext-configure gd \
        --with-gd \
        --with-freetype-dir=/usr/include/ \
        --with-png-dir=/usr/include/ \
        --with-jpeg-dir=/usr/include/ \
    && docker-php-ext-install gd \
    && docker-php-ext-enable gd \
    && pecl install /pecl/redis-3.0.0.tgz \
    && docker-php-ext-enable redis \
    && apt-get purge -y --auto-remove \
    && rm -rf /var/cache/apt/* \
    && rm -rf /var/lib/apt/lists/* \
    && rm -rf /pecl
    
# 安装 composer
RUN php -r "copy('https://getcomposer.org/installer', 'composer-setup.php');" \
    && php composer-setup.php \
    && php -r "unlink('composer-setup.php');" \
    && mv composer.phar /usr/local/bin/composer \
    && composer self-update \
    && composer config -g repo.packagist composer https://packagist.phpcomposer.com \
    && composer global require "laravel/installer=~1.1" \
    && composer global require predis/predis \
    && wget https://phar.phpunit.de/phpunit.phar \
    && chmod +x phpunit.phar \
    && mv phpunit.phar /usr/local/bin/phpunit
```

当然，构建过程中可能会遇到 GFW 的问题，可以参考我的文章做一些调整：[Docker 实践（七）：提升幸福感](https://segmentfault.com/a/1190000007587170)

构建好镜像之后，多容器管理需要使用编排工具 `docker-compose`，所以还需要编写 `docker-compose.yml` 文件，一个简单的示例(不要忘了看注释)：

```bash
version: '2'
services:
  nginx:
    image: nginx:alpine
    depends_on:
      - red
    ports:
      - 8080:80
    volumes:
      - /path/to/nginx.conf:/etc/nginx/nginx.conf
      - /path/to/default.conf:/etc/nginx/conf.d/default.conf
      # 这个挂载是为了处理静态文件
      - /path/to/static:/working
    networks:
      - app
  app:
    image: your-php-fpm-image
    depends_on:
      - mysql
      - redis
    volumes:
      - .:/working
      - /path/to/php.ini:/usr/local/etc/php/php.ini
    networks:
      - app
  mysql:
    image: mysql:latest
    environment:
      TZ: 'Asia/Shanghai'
      MYSQL_ROOT_PASSWORD: 123456
    volumes:
      - ./data:/var/lib/mysql
    ports:
      - 8002:3306
    networks:
      - app
  redis:
    image: redis:latest
    ports:
      - 8003:6379
    networks:
      - app
networks:
  app:
```

需要注意的几点：

- 一定要定义网络。
- nginx.conf, default.conf, php.ini 最好自己定义，挂载到容器中。
- 不要忘了设置时区。

这样在nginx的 default.conf 文件可以这样写：

```
server {
  listen 80 default_server;
  server_name  default;

  location /static/ {
    root /working;
    index index.html;
  }

  index index.html index.php;
  root /working/public;
  location / {
    try_files $uri $uri/ /index.php?$query_string;
  }

  location /packages {
    try_files $uri $uri/;
  }

  location ~ [^/]\.php(/|$) {
    fastcgi_split_path_info ^(.+\.php)(/.+)$;
    # 注意下面这行，pass 到 php-fpm 容器的服务名即可。
    fastcgi_pass app:9000;
    fastcgi_index index.php;
    fastcgi_param SCRIPT_FILENAME $document_root$fastcgi_script_name;
    include fastcgi_params;
  }

  sendfile off;
}
```

至此，配置工作完成，以后你只需要 cd 到你的项目目录下执行

```
docker-compose up -d
```

就可以进行开发了，是不是很简单。
---
layout: post
title: "Docker 实践(四): Beta 环境容器化"
author: "Tairy"
---

最近把公司的 `beta` 环境做了容器化，目前达到的效果是代码提交到 `gitlab`，触发 `webhook` 将代码部署到测试服务器，然后就可以根据前后端不同的分支组合的域名来访问，从而省去了每次前后端代码都合并到 `master` 分支才能测试的环节。

### 系统架构

![](http://ac-HSNl7zbI.clouddn.com/RfaIdbcDtc7STRMy9Swcg0S8MhJljaBSKk4gV4FS.jpg)

### 域名路由

[nginx-proxy](https://github.com/jwilder/nginx-proxy) 是一个 Docker 容器， 是实现本文解决方案的神器，只需简单的配置，便可实现为多个容器路由的功能。

#### 1. 在服务器上安装并运行

```
docker run -d -p 80:80 -v /var/run/docker.sock:/tmp/docker.sock:ro jwilder/nginx-proxy
```

#### 2. 泛域名解析

假设有域名 foo.bar, 使用泛域名解析将 *.foo.bar解析到当前服务器即可。

#### 3. 启动下游容器

假设有一个运行 web 服务的容器，只需要在启动的时候加上 `-e VIRTUAL_HOST=web.foo.bar`，就可以实现对该容器的访问了。

```
docker run -e VIRTUAL_HOST=web.foo.bar  ...
```

> 注意：如果使用 docker-compose 管理多个容器的时候，docker-compose 会为这些容器创建一个网桥，这样会使得后来手动创建的容器没法被路由，所以这里不建议使用 docker-compose 来管理。

### 可视化管理

[ui-for-docker](https://github.com/kevana/ui-for-docker) 是一个基于 docker remote api 实现的 web 管理界面，虽然界面不怎么样，但是基本上常用的功能已经实现了，前端使用 angular 实现，可以根据自己的需求作修改。

#### 修改方法

- clone 代码
- npm install && bower install
- grunt run (更多操作可参看 gruntFile.js 文件)  

### 代码部署

使用 Gitlab 提供的 webhook 功能完成自动部署代码，期间遇到一些问题：

#### 文件写入权限

通过 webhook 的请求执行用户是 www-data，如果要在 hook 脚本中进行文件的写入操作是总会遇到权限问题，最暴力的办法就是给目录全部 777 或者在 Dockerfile 中将 www-data 用户加入 sudo 组，并且无需输入密码。

```bash
echo " data-www ALL=NOPASSWD: ALL" >> /etc/sudoers
```

当然，正式的环境中需要对权限做严格控制，做到最小权限原则。

#### hook 响应超时

Gitlab 触发 hook 请求之后会一直等待服务器返回 `HTTP 200` 的状态码，如果没收到，会重复触发 hook，如果 hook 脚本执行时间过长会导致 HTTP 请求超时，或者一次代码提交触发多次部署请求，所以最后我选择用异步的方式，hook 脚本只需要接受上线指令，写入队列，上线过程交给另外一个脚本来完成。

为了减少环境配置的麻烦，可以使用文件队列，php 可参考 [Filefifo.php](https://gist.github.com/cnnewjohn/b9d2db29dd79f6b9d1a6)。

可将队列目录挂载到 webhook 容器上，即可实现容器内部写入，主机读取队列(可使用supervisor 来管理该进程)，完成代码部署的过程。

### 日志回显

使用 supervisor 管理上线脚本进程，需要把日志回显到 web 界面，首先在 supervisor 的配置文件中配置好日志路径，然后创建一个 websocket 容器，将日志目录挂载到容器中，再tail 读取日志文件，实时显示在 web 界面。

可参考 [websocket](https://github.com/Tairy/dockerfiles/tree/master/websocket)。

- [socket.io](http://socket.io/)
- [node-tail](https://github.com/lucagrulla/node-tail)

### 下游容器

下游容器将前后端环境做了分离，降低耦合度，在使用过程中会减少一些麻烦。分离时会遇到浏览器同源策略的问题，可将前后端容器做互联，然后后端容器反向代理到前端容器。

- 前端容器参考: [frontend](https://github.com/Tairy/dockerfiles/tree/master/frontend)
- 后端容器参考: [backend](https://github.com/Tairy/dockerfiles/tree/master/backend)

在部署代码的时候可根据不同的分支将代码部署到不同的目录，然后创建容器的时候把不同的分支目录挂载到不同的容器中，即可实现开发分支的随意搭配。

### 精简镜像

对于一些服务，有时候只需要一个非常简单的 web 容器就可以，比如上面的前端容器，但是如果使用 ubuntu + nginx 的配置的时候会发现镜像要几百兆，很不划算，所以考虑精简镜像。

受[这篇文章](http://blog.xebia.com/create-the-smallest-possible-docker-container/)的启发，打算自己用 go 实现一个简单的 web 服务器，这样 build 好的镜像基本上只有十几兆，但是因没有做相关的测试，所以还不敢放在线上。

最后选择了使用 alpine + nginx 的策略，build 之后的镜像之后几十兆，已经减少了很多冗余的东西，具体可参考[simple-nginx](https://github.com/Tairy/dockerfiles/tree/master/simple-nginx)。

### 结语

经过无数次踩坑和不停的折腾，终于可以勉强使用了，当然还存在一些瑕疵，之后会慢慢修复。

感谢期间帮助过我的每一位同事。

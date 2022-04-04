## Introduction

This tutorial aims to introduce Traefik, explain its basic components and show a basic configuration in Docker. I :heart: Traefik and I hope you are going to love it too! We will go through the following:

1. Cover basic Traefik v2.X [concepts](#basic-concepts). In this tutorial, we are going to use Traefik [v2.6.0](https://github.com/traefik/traefik/releases/tag/v2.6.0).
2. [Setup and configure Traefik](#setup-and-configure-traefik) using the [Docker](https://doc.traefik.io/traefik/providers/docker/) provider in Standalone Engine mode.
3. Provide a [docker-compose file](#complete-configuration) to achieve the above.
4. [Deploy](#deploy-the-containers) a simple `whoami` service that Traefik is going to forward requests to.
     - [Scale](#scale-whoami-service-to-3-containers) whoami service to show how Traefik loadbalances the requests.

The codebase for this tutorial can be found [here](https://github.com/karvounis/traefik-tutorial-docker-compose-files/blob/master/standalone/basic/docker-compose.yml). All docker-compose files that appear in the Traefik tutorials can be found [here](https://github.com/karvounis/traefik-tutorial-docker-compose-files).

### What is Traefik

[Traefik](https://github.com/traefik/traefik) is an open-source reverse proxy (or Edge Router) and a loadbalancer written in Go. Its greatest strength is the dynamic generation of routes to your deployed services without any manual intervention.

### Why Traefik

In modern architecture, a number of different services are deployed and each one of them has X amount of instances running at the same time. When you receive a request for a particular service, you must find a way to route this request to a healthy instance of this service and provide the response. What is more, the number of instances of a particular service can frequently change based on various factors such as traffic load and cpu and memory usage. You must find a way to dynamically update the routes to your services, route requests only to healthy instances and discard the unhealthy ones.

Traefik solves the above problem by dynamically updating the available routes to each service and their respective instances, thus making service discovery easy. Just imagine how difficult, error-prone and irritating task would be to manually update the routes whenever a service gets created/destroyed/scaled up or down, which can happen all too often during the day.

![Docker Use case](https://doc.traefik.io/traefik/assets/img/quickstart-diagram.png "Simple Use Case Using Docker")

### Prerequisites

- Docker
- Docker compose

All docker compose files have been tested with Docker 20.10.12 and docker-compose 1.24.0.

## Basic concepts

### Providers

[Providers](https://doc.traefik.io/traefik/providers/overview/) are the infrastructure components that Traefik is using for configuration discovery. Under the bonnet, Traefik queries the providers' APIs and based on the information it receives, it dynamically updates the routes.

There are a number of [supported providers](https://doc.traefik.io/traefik/providers/overview/#supported-providers) like Docker, ECS, Kubernetes, Consul, Rancher etc. In this tutorial, we are going to use the [Docker](https://doc.traefik.io/traefik/providers/docker/) provider and use container labels for routing configuration.

### Entrypoints

[Entrypoints](https://doc.traefik.io/traefik/routing/entrypoints/) listen for incoming traffic on specified ports and for a specific protocol (TCP or UDP). The most popular entrypoints are the ones that listen on ports 80 and 443. Entrypoints are part of the static configuration of Traefik, which means that you have to define them using a file (YAML or TOML) or CLI arguments.

### Routers

[Routers](https://doc.traefik.io/traefik/routing/routers/) analyse the incoming requests and based on a set of rules make sure that the requests end up on the appropriate services. They may also use middlewares before forwarding the request.

![Traefik routers](https://doc.traefik.io/traefik/assets/img/routers.png "Traefik routers")

### Middlewares

[Middlewares](https://doc.traefik.io/traefik/middlewares/overview/) can be attached to routers and can be used to analyse/enhance/change/reject the requests before they reach the services. If wanted, they can be chained together and some common use cases are authentication, redirection, path modification etc.

### Services

[Services](https://doc.traefik.io/traefik/routing/services/) configure the way to forward the requests to your actual services. They configure things like load balancing (round-robin only as of version 2.6), health checks, sticky sessions etc.

## Setup and configure Traefik

### Preparation

Pull the necessary images

```bash
docker pull traefik:v2.6
docker pull tecnativa/docker-socket-proxy:latest
docker pull traefik/whoami:v1.7.1
```

Create the Docker networks that we are going to use

```bash
docker network create traefik_public
docker network create socket_proxy
```

`traefik_public` is going to be used by every service that needs to be exposed by Traefik.
`socket_proxy` is just going to be used by `traefik` and `socket_proxy` services to communicate and isolated from the services that need exposure through Traefik.

### Configuration explanation

Our setup consists of three Docker services:

1. **traefik**: Listens to host port 80 and forwards the requests to any appropriate routes.
2. **whoami**: Defines a router and a service using Docker labels. The goal is to serve requests to this service while sitting behing the `traefik` reverse proxy.
3. **socket_proxy**: A security-enhanced proxy for the Docker Socket. It is only going to be used by Traefik.

We are now going to explain the configuration bit by bit. *Tip: Skip to the full docker-compose file [here](#complete-configuration).*

#### Traefik service

```yaml
  traefik:
    image: traefik:v2.6
    command:
      # Entrypoints configuration
      - --entrypoints.web.address=:80
      # Docker provider configuration
      - --providers.docker=true
      # Makes sure that services have to explicitly direct Traefik to expose them
      - --providers.docker.exposedbydefault=false
      # Use the secure docker socket proxy
      - --providers.docker.endpoint=tcp://socket_proxy:2375
      # Default docker network to use for connections to all containers
      - --providers.docker.network=traefik_public
      # Logging levels are DEBUG, PANIC, FATAL, ERROR, WARN, and INFO.
      - --log.level=info
    ports:
      - 80:80
```

##### Entrypoints configuration

###### --entrypoints.web.address=:80

Defines an entrypoint called web that will listen on port 80 of the Traefik container.
By specifying the ports using the short syntax `HOST_PORT:CONTAINER_PORT`

```bash
ports:
  - 80:80
```

you are publishing the port 80 inside the container to the host's port 80. That way, Traefik is going to receive the requests heading to `localhost:80` or `http://localhost`.

##### Docker provider configuration

###### --providers.docker=true

Enables the docker provider.

###### --providers.docker.exposedbydefault=false

Only services that have the Docker label `traefik.enable=true` will be discovered and added to the routing configuration.

###### --providers.docker.endpoint=tcp://socket_proxy:2375

Instead of connecting directly to `unix:///var/run/docker.sock` we are going to use the `socket_proxy` container to be able to query the Docker endpoint as a security precaution.

###### --providers.docker.network=traefik_public

All exposed services through Traefik are going to use by default the `traefik_public` Docker network.

##### Whoami labels

The Docker service `whoami` is going to be exposed and only reachable through Traefik.

```yaml
  whoami:
    image: traefik/whoami:v1.7.1
    labels:
      # Explicitly instruct Traefik to expose this service
      - traefik.enable=true
      # Router configuration
      ## Listen to the `web` entrypoint
      - traefik.http.routers.whoami_route.entrypoints=web
      ## Rule based on the Host of the request
      - traefik.http.routers.whoami_route.rule=Host(`whoami.karvounis.tutorial`)
      - traefik.http.routers.whoami_route.service=whoami_service
      # Service configuration
      ## 80 is the port that the whoami container is listening to
      - traefik.http.services.whoami_service.loadbalancer.server.port=80
```

###### traefik.enable=true

Explicitly instructs Traefik to add it to the routing configuration.

###### traefik.http.routers.whoami_route.entrypoints=web

The `whoami_route` route accepts requests only from the `web` entrypoint (port 80).

###### traefik.http.routers.whoami_route.rule=Host(`whoami.karvounis.tutorial`)

This label adds the Host rule. If a request's domain (host header value) is `whoami.karvounis.tutorial` then this router becomes active and forwards the request to the service.

###### traefik.http.routers.whoami_route.service=whoami_service

Service to use if the request matches the criteria of the `whoami_route`.

###### traefik.http.services.whoami_service.loadbalancer.server.port=80

The `whoami_service` service is going to send the request to the port 80 of the container (the value 80 is the default value for this setting). Useful when the default container port that a service is listening to is not 80 (i.e. Portainer is listening to 9000 so in that case you would configure that service like this `traefik.http.services.portainer_service.loadbalancer.server.port=9000`).

#### Complete configuration

```yaml
version: "3.7"

services:
  traefik:
    image: traefik:v2.6
    command:
      # Entrypoints configuration
      - --entrypoints.web.address=:80
      # Docker provider configuration
      - --providers.docker=true
      # Makes sure that services have to explicitly direct Traefik to expose them
      - --providers.docker.exposedbydefault=false
      # Use the secure docker socket proxy
      - --providers.docker.endpoint=tcp://socket_proxy:2375
      # Default docker network to use for connections to all containers
      - --providers.docker.network=traefik_public
      # Logging levels are DEBUG, PANIC, FATAL, ERROR, WARN, and INFO.
      - --log.level=info
    ports:
      - 80:80
    networks:
      - traefik_public
      - socket_proxy
    restart: unless-stopped
    depends_on:
      - socket_proxy

  # https://github.com/traefik/whoami
  whoami:
    image: traefik/whoami:v1.7.1
    labels:
      # Explicitly instruct Traefik to expose this service
      - traefik.enable=true
      # Router configuration
      ## Listen to the `web` entrypoint
      - traefik.http.routers.whoami_route.entrypoints=web
      ## Rule based on the Host of the request
      - traefik.http.routers.whoami_route.rule=Host(`whoami.karvounis.tutorial`)
      - traefik.http.routers.whoami_route.service=whoami_service
      # Service configuration
      ## 80 is the port that the whoami container is listening to
      - traefik.http.services.whoami_service.loadbalancer.server.port=80
    networks:
      - traefik_public

  # https://github.com/Tecnativa/docker-socket-proxy
  # Security-enhanced proxy for the Docker Socket
  socket_proxy:
    image: tecnativa/docker-socket-proxy:latest
    restart: unless-stopped
    environment:
      NETWORKS: 1
      SERVICES: 1
      CONTAINERS: 1
      TASKS: 1
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
    networks:
      - socket_proxy

networks:
  traefik_public:
    external: true
  socket_proxy:
    external: true
```

### Deploy the containers

Deploy the containers by executing the following command:

```bash
docker-compose up -d
```

Send a request to Traefik with the Host header set to `whoami.karvounis.tutorial`. This request matches the `Host` rule of the `whoami_route` router and will be forwarded to the `whoami_service` service. The response's `Hostname` field is the ID of the `whoami` Docker container.

```bash
$ curl -H "Host: whoami.karvounis.tutorial" http://localhost/

Hostname: ed1b87c345ad
IP: 127.0.0.1
IP: 172.19.0.2
RemoteAddr: 172.19.0.3:49146
GET / HTTP/1.1
Host: whoami.karvounis.tutorial
User-Agent: curl/7.68.0
Accept: */*
Accept-Encoding: gzip
X-Forwarded-For: 172.20.0.1
X-Forwarded-Host: whoami.karvounis.tutorial
X-Forwarded-Port: 80
X-Forwarded-Proto: http
X-Forwarded-Server: f71bbf328ed6
X-Real-Ip: 172.20.0.1
```

By sending the following request, Traefik will forward the request to `whoami_service` and will also forward the desired path `/api` to the service. The response from the `whoami_service` is the same response as above but in JSON.

```bash
$ curl -H "Host: whoami.karvounis.tutorial" http://localhost/api

{"hostname":"ed1b87c345ad","ip":["127.0.0.1","172.19.0.2"],"headers":{"Accept":["*/*"],"Accept-Encoding":["gzip"],"User-Agent":["curl/7.68.0"],"X-Forwarded-For":["172.20.0.1"],"X-Forwarded-Host":["whoami.karvounis.tutorial"],"X-Forwarded-Port":["80"],"X-Forwarded-Proto":["http"],"X-Forwarded-Server":["f71bbf328ed6"],"X-Real-Ip":["172.20.0.1"]},"url":"/api","host":"whoami.karvounis.tutorial","method":"GET"}
```

Try by yourself the following request

```bash
curl -H "Host: whoami.karvounis.tutorial" "http://localhost/data?size=1&unit=KB"
```

Alternatively, add the line `127.0.0.1 whoami.karvounis.tutorial` to your `/etc/hosts` file and visit the `http://whoami.karvounis.tutorial/` URL from your browser.

#### Scale whoami service to 3 containers

```bash
docker-compose up --scale whoami=3 -d
```

The above command will create 3 containers for the `whoami` Docker service instead of just 1. Send the following request multiple times and see Traefik load balance the requests between the 3 containers (`Hostname` keeps changing on every request).

```bash
curl -H "Host: whoami.karvounis.tutorial" http://localhost/
```

Isn't that wonderful and automagical?

## Final notes

Congratulations! We successfully configured Traefik to run in Docker, listen for requests on port 80 and forward requests to the `whoami` service! However, this is just a pretty basic Traefik configuration and the beginning of your Traefik journey. We are going to cover some more advanced topics in the next tutorial! Until next time!

*You can find me on [LinkedIn](https://www.linkedin.com/in/karvounis/) and [Github](https://github.com/karvounis/).*

## Introduction

*This tutorial is the second part of the Traefik series. The first part can be found [here](https://dev.to/karvounis/basic-traefik-configuration-tutorial-593m).*

In the previous tutorial, the basic Traefik concepts were explained and we showed a simple Traefik configuration running in standalone Docker. In this tutorial, we are going to cover some advanced concepts such as TLS, authentication and chain middlewares, the Traefik dashboard, Traefik metrics for Prometheus, and healthchecks.

*The codebase for this tutorial can be found [here](https://github.com/karvounis/traefik-tutorial-docker-compose-files/tree/master/standalone/advanced). All docker-compose files that appear in the Traefik tutorials can be found [here](https://github.com/karvounis/traefik-tutorial-docker-compose-files).*

### Prerequisites

- Docker
- Docker compose

All docker compose files have been tested with Docker 20.10.12 and docker-compose 1.24.0.

Create the required Docker networks

```bash
docker network create traefik_public
docker network create socket_proxy
```

## TL;DR

![tldr-doge](https://github.com/karvounis/traefik-tutorial-docker-compose-files/blob/master/standalone/advanced/images/tldr-doge.jpg?raw=true "TLDR Doge")

## Advanced concepts

### TLS

*The full `docker-compose` file for this section can be found [here](https://github.com/karvounis/traefik-tutorial-docker-compose-files/blob/master/standalone/advanced/docker-compose.tls.yml).*

Traefik can be configured to accept incoming [HTTPS connections](https://doc.traefik.io/traefik/https/overview/) in order to terminate the SSL connections (meaning that it will send decrypted data to the services). It can be configured to use an [ACME provider](https://doc.traefik.io/traefik/https/acme/) (like Let's Encrypt) for automatic certificate generation. However, we are not going to cover this as there is already a plethora of very informative material on the subject online. In this tutorial, we are going to create our own CA and Traefik certificates and configure Traefik to use them.

#### Certificates

We need to create our own TLS certificates in order to have encryption in transit and properly secure the communication from and to Traefik. I have already generated some certificates which can be found [here](https://github.com/karvounis/traefik-tutorial-docker-compose-files/tree/master/standalone/advanced/certs).

However, you can create your own certificates by running the following commands:

```bash
mkdir -p certs/{ca,traefik}
# Create CA certificates
openssl genrsa -out certs/ca/rootCA.key 4096
openssl req -x509 -new \
    -nodes \
    -sha256 \
    -days 3650 \
    -key certs/ca/rootCA.key \
    -subj "/C=GR/L=Athens/O=Karvounis Tutorials, Inc./CN=Karvounis Root CA/OU=CA department" \
    -out certs/ca/rootCA.pem
# Create Traefik wildcard certificates
openssl genrsa -out certs/traefik/traefik.key 4096
openssl req -new \
    -key certs/traefik/traefik.key \
    -subj "/C=GR/L=Athens/O=Karvounis Tutorials, Inc./CN=*.karvounis.tutorial/OU=Dev.to" \
    -out certs/traefik/traefik.csr
openssl x509 -req \
    -sha256 \
    -days 365 \
    -CA certs/ca/rootCA.pem \
    -CAkey certs/ca/rootCA.key \
    -CAcreateserial \
    -in certs/traefik/traefik.csr \
    -out certs/traefik/traefik.crt
```

The above commands will create the necessary certificates under the following directory structure:

```bash
$ tree certs/
certs/
├── ca
│   ├── rootCA.key
│   ├── rootCA.pem
│   └── rootCA.srl
└── traefik
    ├── traefik.crt
    ├── traefik.csr
    └── traefik.key
```

The generated traefik certificate is a wildcard certificate for `*.karvounis.tutorial` and will cover all the use cases for the tutorials. From now on, we are going to use these certificates in every `docker-compose` file.

#### Service configuration

```yaml
traefik:
    image: traefik:v2.6
    command:
    # Entrypoints configuration
    - --entrypoints.web.address=:80
    ## Create a new entrypoint called `websecure` that is going to be used for TLS
    - --entrypoints.websecure.address=:443
    ## Forces redirection of incoming requests from `web` to `websecure` entrypoint
    ## https://doc.traefik.io/traefik/routing/entrypoints/#redirection
    - --entrypoints.web.http.redirections.entryPoint.to=websecure
    # Docker provider configuration
    - --providers.docker=true
    - --providers.docker.exposedbydefault=false
    - --providers.docker.endpoint=tcp://socket_proxy:2375
    - --providers.docker.network=traefik_public
    # File provider configuration
    - --providers.file.directory=/traefik/config/my_dynamic_conf
    # Logging configuration
    - --log.level=info
    - --log.format=json
    ports:
    - 80:80
    - 443:443
    volumes:
    - ./certs/traefik:/traefik/config/certs:ro
    - ./config.yml:/traefik/config/my_dynamic_conf/conf.yml:ro
    networks:
    - traefik_public
    - socket_proxy
    restart: unless-stopped
    depends_on:
    - socket_proxy

whoami:
    image: traefik/whoami:v1.7.1
    labels:
      - traefik.enable=true
      - traefik.http.routers.whoami_route.entrypoints=websecure
      - traefik.http.routers.whoami_route.rule=Host(`whoami.karvounis.tutorial`)
      - traefik.http.routers.whoami_route.service=whoami_service
      - traefik.http.routers.whoami_route.tls=true
      - traefik.http.services.whoami_service.loadbalancer.server.port=80
    networks:
      - traefik_public
```

##### Entrypoints configuration

###### --entrypoints.websecure.address=:443

Defines an entrypoint called `websecure` that will listen on port 443 of the Traefik container. This entrypoint is going to be used for all the TLS connections.

###### --entrypoints.web.http.redirections.entryPoint.to=websecure

It enables permanent redirecting of all incoming requests from the `web` entrypoint to the `websecure` entrypoint. That means that even if someone tries to send an HTTP request, that request will be redirected to HTTPS.

##### File provider configuration

TLS certification configuration is part of the dynamic configuration of Traefik. Unfortunately, we cannot use the [Docker provider](https://doc.traefik.io/traefik/reference/dynamic-configuration/docker/) in order to dynamically configure tls certificates using labels. We have to use the [File provider](https://doc.traefik.io/traefik/reference/dynamic-configuration/file/) instead.

###### --providers.file.directory=/traefik/config/my_dynamic_conf

Points to the directory where Traefik can load the dynamic configuration from. In our case, we are going to mount a `config.yml` file that contains the paths to our certificates.

##### Volumes

```yaml
volumes:
    - ./certs/traefik:/traefik/config/certs:ro
    - ./config.yml:/traefik/config/my_dynamic_conf/conf.yml:ro
```

Mounts the local `./certs/traefik` folder and its contents (the Traefik certificates) to the `/traefik/config/certs` inside the container. Local `./config.yml` file, that contains the dynamic configuration, will be mounted inside the `/traefik/config/my_dynamic_conf/` directory, which is the directory that Traefik looks for its dynamic configuration from.

The path of Traefik's public key and private key in the container are `/traefik/config/certs/traefik.crt` and `/traefik/config/certs/traefik.key` respectively.

##### Config

The following config file, which can be found [here](https://github.com/karvounis/traefik-tutorial-docker-compose-files/blob/master/standalone/advanced/config.yml), is used to define the paths in the container for the certificate and the key.

```yaml
tls:
  certificates:
    - certFile: /traefik/config/certs/traefik.crt
      keyFile: /traefik/config/certs/traefik.key
```

##### whoami service labels

We are going to enable TLS for the `whoami_route`. This can be achieved by changing the value of the `traefik.http.routers.whoami_route.entrypoints` to `websecure` (the HTTPS entrypoint) and setting the `traefik.http.routers.whoami_route.tls` label to true.

```yaml
labels:
    - traefik.enable=true
    - traefik.http.routers.whoami_route.entrypoints=websecure
    - traefik.http.routers.whoami_route.rule=Host(`whoami.karvounis.tutorial`)
    - traefik.http.routers.whoami_route.service=whoami_service
    - traefik.http.routers.whoami_route.tls=true
    - traefik.http.services.whoami_service.loadbalancer.server.port=80
```

#### Deployment

Deploy the containers by executing the following command:

```bash
docker-compose -f docker-compose.tls.yml up -d
```

##### Requests

First, we are going to send a request to `http://whoami.karvounis.tutorial`.

```bash
$ curl -H "Host: whoami.karvounis.tutorial" \
    http://localhost
# OR curl http://whoami.karvounis.tutorial
Moved Permanently
```

The response is __Moved Permanently__ due to the redirection that we configured with this command: `--entrypoints.web.http.redirections.entryPoint.to=websecure`. Every request to the HTTP `web` entrypoint will be automatically redirected to the HTTPS `websecure` entrypoint!

Let's try to directly hit the HTTPS entrypoint:

```bash
$ curl --cacert ./certs/ca/rootCA.pem \
    https://whoami.karvounis.tutorial
Hostname: 5f1a8f92cd2b
IP: 127.0.0.1
IP: 172.19.0.2
RemoteAddr: 172.19.0.3:53910
GET / HTTP/1.1
Host: whoami.karvounis.tutorial
User-Agent: curl/7.68.0
Accept: */*
Accept-Encoding: gzip
X-Forwarded-For: 172.20.0.1
X-Forwarded-Host: whoami.karvounis.tutorial
X-Forwarded-Port: 443
X-Forwarded-Proto: https
X-Forwarded-Server: 40e915108da5
X-Real-Ip: 172.20.0.1
```

Success! Sending a request to the HTTPS entrypoint and specifying the public key of the CA, returned the expected response.

### Ping

*The full `docker-compose` file for this section can be found [here](https://github.com/karvounis/traefik-tutorial-docker-compose-files/blob/master/standalone/advanced/docker-compose.ping.yml).*

Traefik provides a `ping` [endpoint](https://doc.traefik.io/traefik/operations/ping/) that, when enabled, can be used to check the health of the Traefik instance.

#### Configuration changes

##### --ping=true

Enables the `/ping` healthcheck URL. However, we are not going to expose it using a router. Instead, we are going to use the URL to check the health of the Docker container by leveraging docker-compose's [healthcheck](https://docs.docker.com/compose/compose-file/compose-file-v3/#healthcheck) option.

##### healthcheck configuration

Every 10 seconds, Docker is going to execute the command `traefik healthcheck --ping` to establish the health of each Traefik instance ([docs](https://doc.traefik.io/traefik/operations/cli/#healthcheck)). If the command is unsuccessful for 3 consecutive times, Docker will mark the container as unhealthy and will restart it.

```yaml
healthcheck:
    # Run traefik healthcheck command
    # https://doc.traefik.io/traefik/operations/cli/#healthcheck
    test: ["CMD", "traefik", "healthcheck", "--ping"]
    interval: 10s
    timeout: 5s
    retries: 3
    start_period: 5s
```

#### Deployment

Deploy the containers by executing the following command:

```bash
docker-compose -f docker-compose.ping.yml up -d
```

Check the status of the traefik service by executing:

```bash
docker-compose -f docker-compose.ping.yml ps traefik
```

After a few seconds, traefik service's status will change from `starting` to `healthy`.

### Dashboard

*The full `docker-compose` file for this section can be found [here](https://github.com/karvounis/traefik-tutorial-docker-compose-files/blob/master/standalone/advanced/docker-compose.dashboard.yml).*

Traefik offers a [dashboard](https://doc.traefik.io/traefik/operations/dashboard/) where you can view all the active routers, services and middlewares. In this section, we are going to find out how to enable the dashboard and how to configure the routers to be able to access it.

#### Traefik service configuration

This is the first time we are going to add Docker labels to the `traefik` service. They are going to define a new router, called `dashboard`, which will only be accessible through TLS.

In order to enable the `dashboard` and the `api`, you have to add the `--api.dashboard=true` to the `command` configuration option of the `traefik` service.

##### Service labels

The Docker labels below define a new router called `dashboard`. This router uses a __Host Based rule__ as well as two __PathPrefix__ rules to be able to match all the necessary requests. This router is only accessible through the `websecure` entrypoint.

```yaml
labels:
    - traefik.enable=true
    - traefik.http.routers.dashboard.rule=Host(`traefik.karvounis.tutorial`) && (PathPrefix(`/api`) || PathPrefix(`/dashboard`))
    - traefik.http.routers.dashboard.tls=true
    - traefik.http.routers.dashboard.entrypoints=websecure
    - traefik.http.routers.dashboard.service=api@internal
```

#### Deployment

Deploy the containers by executing the following command:

```bash
docker-compose -f docker-compose.dashboard.yml up -d
```

##### UI

You can access the dashboard by visiting `https://traefik.karvounis.tutorial/dashboard/` and the `api` at `https://traefik.karvounis.tutorial/api/rawdata`.

*Tip: Do not forget the trailing slash `/` in `/dashboard/`!*

![traefik-dashboard](https://github.com/karvounis/traefik-tutorial-docker-compose-files/blob/master/standalone/advanced/images/traefik_dashboard.jpg?raw=true "Traefik Dashboard")

### Authentication

*The full `docker-compose` file for this section can be found [here](https://github.com/karvounis/traefik-tutorial-docker-compose-files/blob/master/standalone/advanced/docker-compose.auth.yml).*

After exposing the dashboard in the previous section, it is clear that we need to secure it and restrict access only to authenticated users.
Traefik offers the following HTTP Authentication middlewares:

- [BasicAuth](https://doc.traefik.io/traefik/middlewares/http/basicauth/)
- [DigestAuth](https://doc.traefik.io/traefik/middlewares/http/digestauth/)
- [ForwardAuth](https://doc.traefik.io/traefik/middlewares/http/forwardauth/)

In this section, we are going to use the `BasicAuth` middleware to secure the `dashboard` router and the `DigestAuth` to secure the `whoami` router.

#### Configuration changes

`traefik` service:

```yaml
labels:
    - traefik.enable=true
    - traefik.http.routers.dashboard.rule=Host(`traefik.karvounis.tutorial`) && (PathPrefix(`/api`) || PathPrefix(`/dashboard`))
    - traefik.http.routers.dashboard.tls=true
    - traefik.http.routers.dashboard.entrypoints=websecure
    - traefik.http.routers.dashboard.service=api@internal
    # Middlewares
    - traefik.http.routers.dashboard.middlewares=dashboard_auth
    ## Creates 2 authentication middlewares
    ### `dashboard_auth` is a BasicAuth middleware and is going to be used by the `dashboard` router.
    ### dashboard:tutorial
    - traefik.http.middlewares.dashboard_auth.basicauth.users=dashboard:$$2y$$05$$T/WVjQVqBc24NLUNI/xuVu0V2B.RPY50k2.CCH5JHGInb3EUeaDcO
    ### `auth` is a DigestAuth middleware and is going to be used by the `whoami_route` router.
    ### whoami:tutorial
    - traefik.http.middlewares.digest_auth.digestauth.users=whoami:traefik:f4ba293a96d5dcf51eb2f03b5931dd96
```

`whoami` service:

```yaml
    labels:
      - traefik.enable=true
      - traefik.http.routers.whoami_route.entrypoints=websecure
      - traefik.http.routers.whoami_route.rule=Host(`whoami.karvounis.tutorial`)
      - traefik.http.routers.whoami_route.service=whoami_service
      - traefik.http.routers.whoami_route.tls=true
      # `whoami_route` uses the `digest_auth` middleware defined in the `traefik` service
      - traefik.http.routers.whoami_route.middlewares=digest_auth
      - traefik.http.services.whoami_service.loadbalancer.server.port=80
```

##### traefik.http.middlewares.dashboard_auth.basicauth.users

This label creates a new `BasicAuth` middleware called `dashboard_auth`. It contains the user with the credentials `dashboard:tutorial` and can contain an array of authorized users. If you have a great number of users, you can also add their credentials to a file, mount that file to the container and specify the `usersFile` option to point to that file.

You can generate the passwords with the following ways:

```bash
# Using the httpd:2.4-alpine image which is 58.2MB
$ docker run --rm httpd:2.4-alpine htpasswd -nbB dashboard tutorial | sed -e s/\\$/\\$\\$/g
# OR with `xmartlabs/htpasswd` docker image which is 9MB
$ docker run --rm -ti xmartlabs/htpasswd dashboard tutorial | sed -e s/\\$/\\$\\$/g
# OR without docker
$ htpasswd -nbB dashboard tutorial | sed -e s/\\$/\\$\\$/g

dashboard:$$2y$$05$$T/WVjQVqBc24NLUNI/xuVu0V2B.RPY50k2.CCH5JHGInb3EUeaDcO
```

*Tip: when used in `docker-compose.yml`, all dollar signs in the hash need to be doubled for escaping!*

##### traefik.http.middlewares.digest_auth.digestauth.users

This label creates a new `DigestAuth` middleware called `digest_auth`. It contains the user with the credentials `whoami:tutorial` and can contain an array of authorized users. The `usersFile` option is available here as well.

You can generate the digest credentials with the following commands:

```bash
$ print whoami:traefik:$(printf whoami:traefik:tutorial | md5sum | awk '{print $1}')
# OR with htdigest `htdigest [-c] passwordfile realm username` and type the password
$ htdigest -c /tmp/pwd_file traefik whoami && cat /tmp/pwd_file

whoami:traefik:f4ba293a96d5dcf51eb2f03b5931dd96
```

##### traefik.http.routers.dashboard.middlewares=dashboard_auth

Instructs the `dashboard` router to use the `dashboard_auth` as authentication middleware.

##### traefik.http.routers.whoami_route.middlewares=digest_auth

Instructs the `whoami_route` router to use the `digest_auth` as authentication middleware.

*Tip: You can use middlewares defined in other services!*

#### Deployment

Deploy the containers by executing the following command:

```bash
docker-compose -f docker-compose.auth.yml up -d
```

##### Requests

If you try to access the `https://traefik.karvounis.tutorial/api/rawdata` URL like before, you are going to get a `401` response status code.

```bash
$ curl --cacert ./certs/ca/rootCA.pem \
    https://traefik.karvounis.tutorial/api/rawdata
401 Unauthorized
```

In order to access the Traefik `api` using `curl`, you have to specify the basic auth user credentials.

```bash
$ curl --cacert ./certs/ca/rootCA.pem \
    -u dashboard:tutorial \
    https://traefik.karvounis.tutorial/api/version
{"Version":"2.6.0","Codename":"rocamadour","startDate":"2022-02-23T17:42:57.897252485Z","pilotEnabled":true}
```

If you want to access the `whoami` service, you need to specify the digest credentials of the `whoami` authorized user. Otherwise, Traefik is going to respond with a `401` as above.

```bash
$ curl --cacert ./certs/ca/rootCA.pem \
    --digest -u whoami:tutorial \
    https://whoami.karvounis.tutorial
Hostname: 637aadaf37b3
IP: 127.0.0.1
IP: 172.19.0.2
RemoteAddr: 172.19.0.3:40984
GET / HTTP/1.1
Host: whoami.karvounis.tutorial
User-Agent: curl/7.68.0
Accept: */*
Accept-Encoding: gzip
Authorization: Digest username="whoami", realm="traefik", nonce="2ZZJLL5tPk8bEDU8", uri="/", cnonce="YzUxNzMyZWIyODNjN2VlNDIyMDkyMmY3Nzc3YjVkNDE=", nc=00000001, qop=auth, response="518ade9a297beb2f5174e2368e8cf561", opaque="pfm5w5vBpLYhEv7A", algorithm="MD5"
X-Forwarded-For: 172.20.0.1
X-Forwarded-Host: whoami.karvounis.tutorial
X-Forwarded-Port: 443
X-Forwarded-Proto: https
X-Forwarded-Server: 5966f55786bb
X-Real-Ip: 172.20.0.1
```

### Chain middleware

*The full `docker-compose` file for this section can be found [here](https://github.com/karvounis/traefik-tutorial-docker-compose-files/blob/master/standalone/advanced/docker-compose.chain.yml).*

In this section, we are going to create a new [Chain middleware](https://doc.traefik.io/traefik/middlewares/http/chain/) and instruct `whoami_route` to use it. This middleware consists of two middlewares:

1. A new HTTP [RateLimit](https://doc.traefik.io/traefik/middlewares/http/ratelimit/) middleware called `simple_ratelimit`. This middleware is going to limit the maximum amount of allowed requests to the `whoami_service` service in a particular time period.
2. `digest_auth` which we have already seen in the [Authentication](#authentication) section.

The `chain` middleware is first going to pass the request through the `simple_ratelimit` and then through the `digest_auth` middleware. If the request manages to successfully pass both, then it will reach the `whoami_service`. Traefik's documentation does not specify a hard limit for the amount of middlewares that you can chain.

#### Configuration changes

We are going to create the new `simple_ratelimit` and `secured_chain` middlewares by adding the following labels to the `traefik` service:

```yaml
labels:
    - traefik.http.middlewares.secured_chain.chain.middlewares=simple_ratelimit,digest_auth
    ## The `simple_ratelimit` middleware allows
    ## an average of 5 requests per 5 seconds
    ## and a burst of 2 requests.
    - traefik.http.middlewares.simple_ratelimit.ratelimit.average=5
    - traefik.http.middlewares.simple_ratelimit.ratelimit.period=5s
    - traefik.http.middlewares.simple_ratelimit.ratelimit.burst=2
```

Based on the above numbers, the maximum allowed request rate is `r=average/period=5/5s=1 request/second`. If we exceed that rate, the requests are going to be automatically rejected with a __429__ HTTP status code.

We also need to instruct `whoami_route` to use the `secured_chain` middleware:

```yaml
labels:
    # Use the `secured_chain` chain middleware
    - traefik.http.routers.whoami_route.middlewares=secured_chain
```

#### Deployment

Deploy the containers by executing the following command:

```bash
docker-compose -f docker-compose.chain.yml up -d
```

##### Requests

Sending a simple `curl` request to `https://whoami.karvounis.tutorial` will work as before. Nothing out of the ordinary yet.

```bash
curl --cacert ./certs/ca/rootCA.pem \
    --digest -u whoami:tutorial \
    https://whoami.karvounis.tutorial
```

The following command is going to send a curl request to `https://whoami.karvounis.tutorial` every 1.5 seconds. All 5 requests are going to succeed because the rate is slower than the maximum allowed request rate.

```bash
SLEEP_TIMER=1.5s
for i in {1..5};
do
    echo "\nRequest number: $i"
    curl --cacert ./certs/ca/rootCA.pem \
        --digest -u whoami:tutorial \
        https://whoami.karvounis.tutorial
    sleep "${SLEEP_TIMER}"
done
```

On the other hand, the following command is going to send a curl request to `https://whoami.karvounis.tutorial` every 0.5 seconds. This request rate of 2 requests/sec is faster that the maximum allowed rate! The very first request will succeed but all the subsequent ones will be rejected with a `429 Too Many Requests` HTTP status code.

```bash
SLEEP_TIMER=0.5s
for i in {1..5};
do
    echo "\nRequest number: $i"
    curl --cacert ./certs/ca/rootCA.pem \
        --digest -u whoami:tutorial \
        https://whoami.karvounis.tutorial
    sleep "${SLEEP_TIMER}"
done
```

### Metrics

*The full `docker-compose` file for this section can be found [here](https://github.com/karvounis/traefik-tutorial-docker-compose-files/blob/master/standalone/advanced/docker-compose.metrics.yml).*

Currently, Traefik supports 4 [metrics backends](https://doc.traefik.io/traefik/observability/metrics/overview/):

- Datadog
- InfluxDB
- Prometheus
- StatsD

In this section, we are going to expose Traefik's  metrics for Prometheus.

#### Configuration changes

First, we are going to enable the prometheus backend and disable the default internal router in order to allow one to create a custom router to the `prometheus@internal` service.

```yaml
command:
    # Prometheus metrics
    ## Enable prometheus metrics
    - --metrics.prometheus=true
    ## Create a manual router instead of the default one.
    - --metrics.prometheus.manualrouting=true
    - --metrics.prometheus.addrouterslabels=true
    ...
```

The custom `metrics` router exposes the metrics through `https://traefik.karvounis.tutorial/metrics` and uses the `dashboard_auth` BasicAuth middleware for authentication.

```yaml
labels:
    # `metrics` router configuration
    - traefik.http.routers.metrics.rule=Host(`traefik.karvounis.tutorial`) && PathPrefix(`/metrics`)
    - traefik.http.routers.metrics.tls=true
    - traefik.http.routers.metrics.entrypoints=websecure
    - traefik.http.routers.metrics.service=prometheus@internal
    - traefik.http.routers.metrics.middlewares=dashboard_auth
    ...
```

#### Deployment

Deploy the containers by executing the following command:

```bash
docker-compose -f docker-compose.metrics.yml up -d
```

##### Requests

Send the following request to `https://traefik.karvounis.tutorial/metrics`. The response contains all the Prometheus metrics for the particular Traefik instance.

```bash
curl --cacert ./certs/ca/rootCA.pem \
    -u dashboard:tutorial \
    https://traefik.karvounis.tutorial/metrics
```

## Final notes

I hope you enjoyed this advanced tutorial on Traefik. Even more interesting tutorials are on the way! Please, let me know your thoughts in the comments section below! Cheers

*You can find me on [LinkedIn](https://www.linkedin.com/in/karvounis/) and [Github](https://github.com/karvounis/).*

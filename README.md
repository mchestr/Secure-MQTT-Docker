# Basic Docker setup for a TLS enabled MQTT Server

# Getting Started

First you must generate the certificates used for TLS, if you already have certificates skip to the next section.

# Generate Certificates

`cd ./config` before executing this section.

## Create Root CA (Done once)

### Create Root Key

**Attention:** this is the key used to sign the certificate requests, anyone holding this can sign certificates on your behalf. So keep it in a safe place!

```bash
openssl genrsa -des3 -out rootCA.key 4096
```

If you want a non password protected key just remove the `-des3` option


### Create and self sign the Root Certificate

```bash
openssl req -x509 -new -nodes -key rootCA.key -sha256 -days 1024 -out rootCA.crt
```

Here we used our root key to create the root certificate that needs to be distributed in all the computers that have to trust us.


## Create a server certificate

### Create the certificate key

```
openssl genrsa -out server.key 2048
```

### Create the signing  (csr)

The certificate signing request is where you specify the details for the certificate you want to generate.
This request will be processed by the owner of the Root key (you in this case since you create it earlier) to generate the certificate.

**Important:** Please mind that while creating the signign request is important to specify the `Common Name` providing the IP address or domain name for the service, otherwise the certificate cannot be verified.

If you generate the csr in this way, openssl will ask you questions about the certificate to generate like the organization details and the `Common Name` (CN) that is the web address you are creating the certificate for, e.g `mydomain.com`.

```
openssl req -new -key server.key -out server.csr
```


### Verify the csr's content

```
openssl req -in server.csr -noout -text
```

### Generate the certificate using the `server` csr and key along with the CA Root key

```
openssl x509 -req -in server.csr -CA rootCA.crt -CAkey rootCA.key -CAcreateserial -out server.crt -days 500 -sha256
```

### Verify the certificate's content

```
openssl x509 -in server.crt -text -noout
```

## Create a client certificate

### Create the certificate key

```
openssl genrsa -out client.key
```

### Create the signing  (csr)

```
openssl req -new -key client.key -out client.csr
```

### Verify the csr's content

```
openssl req -in client.csr -noout -text
```

### Generate the certificate using the `client` csr and key along with the CA Root key

```
openssl x509 -req -CA rootCA.crt -CAkey rootCA.key -CAcreateserial -in client.csr -out client.crt
```

### Verify the certificate's content

```
openssl x509 -in client.crt -text -noout
```

# Move Certificates and Verify Docker Compose Values

Move the `rootCA.crt` and `server.*` into the `./config` directory and adjust the file names in `docker-compose.yml` accordingly.

# Generate Passwords File

`docker run -it --rm -v $pwd/config:/mosquitto/config eclipse-mosquitto mosquitto_passwd -c /mosquitto/config/passwords.txt <username>`

to add more users change `-c` to `-b`

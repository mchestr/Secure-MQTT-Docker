# Basic Docker setup for a TLS enabled MQTT Server

This project establishes an MQTT broker with TLS and user
authentication.  Most actions including the generation of certificates
are performed using GNU make to reduce errors introduced with manual
procedures.  You can print help using the command `make help`.

## Setup

All MQTT clients must not only have a valid certificate, but they also
must use user authentication to successfully connect to the broker.
In this project, only one client is defined in the Makefile.

For each new client, you must edit a file containing information
required to build a client certificate as well as the client's
username and password.

Therefore, you must create a file named `*.client` in the
`mqtt/certs/clients` directory, where `*` is the unique name of the
client.

Your operating procedures will vary, but I found that it's useful to
name the client file the same as the username.

The `*.client` file contains one line, with several fields separated
by semicolons.  The first column contains the subject line of the
client's certificate.  The second and third fields contain the
username and password used in authentication with the MQTT broker.

Example:

```
/C=SE/ST=Stockholm/L=Stockholm/O=snuffeldorf.com/OU=Client/CN=localhost;example_user;insecure
```

## Run

It's safe to start and stop the broker without fear of losing the
certificates. Start the MQTT broker with `make start`.

```bash
make start
```

To stop, run:

```bash
make stop
```

## Test

1. Start the MQTT broker using `make start`.
2. Verify that the broker is running with `docker-compose ps`
3. Subscribe to the /world topic:
```bash
mosquitto_sub -h localhost -p 8883 -u example_user -P 'insecure' --cafile mqtt/certs/ca/ca.crt --cert mqtt/certs/clients/example_user.crt --key mqtt/certs/clients/example_user.key -t /world
```
4. Manually publish a message:
```bash
mosquitto_pub -h localhost -p 8883 -u example_user -P 'insecure' --cafile mqtt/certs/ca/ca.crt --cert mqtt/certs/clients/example_user.crt --key mqtt/certs/clients/example_user.key -m hello -t /world
```
5. Verify that the subscriber prints out the `hello` message to the `/world` topic.

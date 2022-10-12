SHELL := /bin/bash

# The version of the code.  Needed if you want to embed this in the
# code itself.
GIT_VERSION:=$(shell git describe --abbrev=6 --dirty --always --tags)

# check for dependencies to build the application (docker,
# docker-compose, etc)
EXECUTABLES = sudo nohup git docker docker-compose pytest-3 openssl
K := $(foreach exec,$(EXECUTABLES),\
        $(if $(shell which $(exec)),some string,$(error "No $(exec) in PATH")))

# Verbose flag used similarly to the Linux kernel kbuild system.  By
# default, the makefile is mostly silent/terse. to run, type: make
# V=n, where n can be any positive non-zero integer.  By default, V=0
# (silent).
V=0
ifeq ($(V),0)
  Q = @
  # for sending verbose output of some commands to /dev/null
  Q_STDOUT = >/dev/null
  Q_STDERR = 2>/dev/null
else
  Q = 
  Q_STDOUT =
  Q_STDERR =
endif

MOUNTED_VOLUMES_TOP:=mounted-volumes
CERTS:=\
	$(MOUNTED_VOLUMES_TOP)/mqtt/config/certs/ca.crt \
	$(MOUNTED_VOLUMES_TOP)/mqtt/config/certs/broker.key \
	$(MOUNTED_VOLUMES_TOP)/mqtt/config/certs/broker.crt
CLIENT_CERTS:=\
	mqtt/certs/clients/example_user.crt

# ==================================================================
# Targets:

.PHONY: all
all: build ## Default rule: compile the main application
	@echo "make all rule"

.PHONY: host-setup
host-setup: ## Setup your build environment
	@echo "make host-setup rule"
	$(Q)git submodule update --init --recursive

.PHONY: build
build:	host-setup ## Builds the application
	$(Q)docker-compose build

.PHONY: clean ## Cleans up miscellaneous files except generated certificates and persistent data
clean:
	$(Q)rm -f *~

.PHONY: distclean ## Cleans up EVERYTHING
distclean:
	$(Q)rm -f *~
	$(Q)rm -f mqtt/certs/ca/*.crt mqtt/certs/ca/*.key mqtt/certs/ca/*.srl
	$(Q)rm -f mqtt/certs/broker/*.crt mqtt/certs/broker/*.key mqtt/certs/broker/*.csr
	$(Q)rm -f mqtt/certs/clients/*.crt mqtt/certs/clients/*.key mqtt/certs/clients/*.csr

.PHONY: start
start:	build $(CERTS) $(MOUNTED_VOLUMES_TOP)/mqtt/config/mosquitto.conf $(CLIENT_CERTS) $(MOUNTED_VOLUMES_TOP)/mqtt/config/passwords.txt ## Starts the application
	$(Q)(docker-compose ps -q | wc -l | grep -q 0) || (echo "Already running" && docker-compose ps && /bin/false)
	$(Q)nohup docker-compose up -d &
	@echo "Application Started - VERSION $(GIT_VERSION)"

.PHONY: stop
stop: ## Stops the application
	$(Q)docker-compose down

.PHONY: useradd
useradd: $(MOUNTED_VOLUMES_TOP)/mqtt/config/passwords.txt ## Manually adds an MQTT client. You must define makefile variables MQTT_USER and MQTT_PASSWORD.
	$(Q)docker run -it --rm -v $(shell pwd)/$(MOUNTED_VOLUMES_TOP)/mqtt/config:/mosquitto/config eclipse-mosquitto mosquitto_passwd -b /mosquitto/config/passwords.txt $(MQTT_USER) $(MQTT_PASSWORD)

.PHONY: userdel
userdel: $(MOUNTED_VOLUMES_TOP)/mqtt/config/passwords.txt ## Manually deletes an MQTT client. You must define makefile variables MQTT_USER.
	$(Q)docker run -it --rm -v $(shell pwd)/$(MOUNTED_VOLUMES_TOP)/mqtt/config:/mosquitto/config eclipse-mosquitto mosquitto_passwd -D /mosquitto/config/passwords.txt $(MQTT_USER)

# Add the following 'help' target to your Makefile
# And add help text after each target name starting with '\#\#'
.PHONY: help
help:           ## Show this help
	$(Q)awk 'BEGIN {FS = ":.*##"; printf "\nUsage: make <TARGET>\n"} /^[$$()% 0-9a-zA-Z_-]+:.*?##/ { printf "  %-15s %s\n", $$1, $$2 } /^##@/ { printf "\n%s\n", substr($$0, 5) } ' $(MAKEFILE_LIST)

# ==================================================================
# CERTIFICATES:

# This section creates three groups of ceritficates: one for the
# certificate authority (CA), one for the MQTT broker, and then one
# for each MQTT client.  The subjects for the CA and broker are
# defined in this makefile and may be overriden on the command line.
# See mqtt/certs/clients/README.txt for instructions for creating new
# clients.

# =========================
# variables

# Materials that go in the subject
IP:=localhost
ORGANIZATION_NAME:=flaxnerf.io
# NOTE: the Common Name (CN) for the CA must be different than that of the broker and the client
SUBJECT_ROOT_CA:=/C=SE/ST=Stockholm/L=Stockholm/O=$(ORGANIZATION_NAME)/OU=CA/CN=$(ORGANIZATION_NAME)
SUBJECT_SERVER:=/C=SE/ST=Stockholm/L=Stockholm/O=$(ORGANIZATION_NAME)/OU=Server/CN=$(IP)
SUBJECT_CLIENT:=/C=SE/ST=Stockholm/L=Stockholm/O=$(ORGANIZATION_NAME)/OU=Client/CN=$(IP)

# =========================
# CERTIFICATE AUTHROITY

# KEY

# Note: if you want a password protected key, then add the '-des3'
# command line option to the 'openssl genrsa' command below.
mqtt/certs/ca/ca.key: ## Create Root Key
	$(Q)openssl genrsa -out $@ 4096 $(Q_STDERR)

# CERTIFICATE

# Here we used our root key to create the root certificate that needs
# to be distributed in all the computers that have to trust us.
mqtt/certs/ca/ca.crt: mqtt/certs/ca/ca.key ## Create and self sign the Root Certificate
	$(Q)openssl req -x509 -new -nodes -key $< -sha256 -days 1024 -out $@ -subj "$(SUBJECT_ROOT_CA)" $(Q_STDERR)

# =========================
# MQTT BROKER

# KEY
mqtt/certs/broker/broker.key: ## Create the server certificate key
	$(Q)openssl genrsa -out $@ 2048 $(Q_STDERR)

# CERTIFICATE SIGNING REQUEST (CSR)

# The certificate signing request is where you specify the details for
# the certificate you want to generate.  This request will be
# processed by the owner of the Root key (you in this case since you
# created it earlier) to generate the certificate.
mqtt/certs/broker/broker.csr: mqtt/certs/broker/broker.key ## Create the server certificate signing request (csr)
	$(Q)openssl req -new -key $< -out $@ -subj "$(SUBJECT_SERVER)" $(Q_STDERR) || openssl req -in $@ -noout -text $(Q_STDERR)

# CERTIFICATE

mqtt/certs/broker/broker.crt: mqtt/certs/broker/broker.csr mqtt/certs/ca/ca.crt mqtt/certs/ca/ca.key ## Generate the certificate using the `server` csr and key along with the CA Root key
	$(Q)openssl x509 -req -in mqtt/certs/broker/broker.csr -CA mqtt/certs/ca/ca.crt -CAkey mqtt/certs/ca/ca.key -CAcreateserial -out $@ -days 500 -sha256 $(Q_STDERR) || openssl x509 -in $@ -text -noout $(Q_STDERR)

# =========================
# MQTT CLIENTS

# generic rule to generate the client certificate from a text file.
%.key %.csr %.crt: %.client mqtt/certs/ca/ca.crt mqtt/certs/ca/ca.key $(MOUNTED_VOLUMES_TOP)/mqtt/config/passwords.txt
	$(Q)IFS=';' read -r summary mqtt_user mqtt_password < $< ; \
	echo "Creating Client: $*" ; \
	openssl genrsa -out $*.key $(Q_STDERR) ; \
	openssl req -new -key $*.key -out $*.csr -subj "$(SUBJECT_CLIENT)" || openssl req -in $*.csr -noout -text $(Q_STDERR) ; \
	openssl x509 -req -CA mqtt/certs/ca/ca.crt -CAkey mqtt/certs/ca/ca.key -CAcreateserial -in $*.csr -out $*.crt $(Q_STDERR) || openssl x509 -in $*.crt -text -noout $(Q_STDERR) ; \
	docker run -it --rm -v $(shell pwd)/$(MOUNTED_VOLUMES_TOP)/mqtt/config:/mosquitto/config eclipse-mosquitto mosquitto_passwd -b /mosquitto/config/passwords.txt $${mqtt_user} $${mqtt_password} $(Q_STDERR)

# ==================================================================
# Miscellaneous rules

$(MOUNTED_VOLUMES_TOP)/mqtt/config/passwords.txt: $(MOUNTED_VOLUMES_TOP)/mqtt/config
	$(Q)([ ! -f $@ ] && touch $@) || /bin/true

$(MOUNTED_VOLUMES_TOP)/mqtt/config/mosquitto.conf: mqtt/mosquitto.conf $(MOUNTED_VOLUMES_TOP)/mqtt/config
	$(Q)([ ! -f $@ ] && cp $< $@) || /bin/true

$(MOUNTED_VOLUMES_TOP)/mqtt/config/certs/ca.crt: mqtt/certs/ca/ca.crt $(MOUNTED_VOLUMES_TOP)/mqtt/config/certs
	$(Q)([ ! -f $@ ] && cp $< $@) || /bin/true

$(MOUNTED_VOLUMES_TOP)/mqtt/config/certs/broker.key: mqtt/certs/broker/broker.key $(MOUNTED_VOLUMES_TOP)/mqtt/config/certs
	$(Q)([ ! -f $@ ] && cp $< $@) || /bin/true

$(MOUNTED_VOLUMES_TOP)/mqtt/config/certs/broker.crt: mqtt/certs/broker/broker.crt $(MOUNTED_VOLUMES_TOP)/mqtt/config/certs
	$(Q)([ ! -f $@ ] && cp $< $@) || /bin/true

$(MOUNTED_VOLUMES_TOP)/mqtt/config:
	$(Q)mkdir -p $@

$(MOUNTED_VOLUMES_TOP)/mqtt/config/certs:
	$(Q)mkdir -p $@


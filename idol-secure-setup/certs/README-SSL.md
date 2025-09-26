# Generate TLS for Find UI
Those variables describe the SSL material that the Find UI container expects. Right now they are just examples. To make them work, you need to actually generate or provide the certificate and keystore files, then mount them at the paths used inside the container.

## Step 1. Generate a PKCS12 keystore for the Find UI

If you already have a cert (nifi-cert.pem) and key (nifi-key.key), you can combine them:

openssl pkcs12 -export \
  -in certs/nifi-cert.pem \
  -inkey certs/nifi-key.key \
  -out certs/find-ui.pkcs12 \
  -name find-ui \
  -password pass:1234


Now you have certs/find-ui.pkcs12.

## Step 2. (Optional) Create an intermediate CA PKCS12 if required

If you want to import a CA chain:

openssl pkcs12 -export \
  -in certs/ca-chain.pem \
  -out certs/intermediate.pkcs12 \
  -name ca-chain \
  -password pass:1234


If you don’t have an intermediate, you can skip this and just use the root CA PEM.

## Step 3. Mount your files in docker-compose

In your service definition:

volumes:
  - ./certs:/ssl/certs:ro


That way inside the container you will have /ssl/certs/find-ui.pkcs12, /ssl/certs/intermediate.pkcs12, /ssl/certs/ca.cert.pem.

## Step 4. Set the environment variables
environment:
  - IDOL_UI_SSL_PKCS_FILE=/ssl/certs/find-ui.pkcs12
  - IDOL_UI_SSL_PKCS_PASS=1234
  - IDOL_UI_SSL_CA_PKCS12=/ssl/certs/intermediate.pkcs12
  - IDOL_UI_SSL_CA_PASS=1234
  - IDOL_UI_ROOT_CERTIFICATE=/ssl/certs/ca.cert.pem

## Step 5. Restart
docker-compose down
docker-compose up -d

Here is a full script to generate the files your Find UI container expects. It assumes you have a private key and certificate (nifi-key.key and nifi-cert.pem) in a local certs/ folder. It will produce:

find-ui.pkcs12

intermediate.pkcs12 (self-signed CA if you don’t have one)

ca.cert.pem

#!/bin/bash
set -e

# Directory to store SSL files
CERT_DIR=certs
mkdir -p $CERT_DIR

# Passwords for keystores
UI_PASS=1234
CA_PASS=1234

# Paths to existing cert and key
UI_CERT=$CERT_DIR/nifi-cert.pem
UI_KEY=$CERT_DIR/nifi-key.key

# Check required files
if [ ! -f "$UI_CERT" ] || [ ! -f "$UI_KEY" ]; then
    echo "Error: nifi-cert.pem or nifi-key.key missing in $CERT_DIR"
    exit 1
fi

# 1. Generate Find UI PKCS12 keystore
openssl pkcs12 -export \
  -in "$UI_CERT" \
  -inkey "$UI_KEY" \
  -out "$CERT_DIR/find-ui.pkcs12" \
  -name find-ui \
  -password pass:$UI_PASS

echo "Created $CERT_DIR/find-ui.pkcs12"

# 2. Generate intermediate CA PKCS12 (self-signed) if it doesn't exist
if [ ! -f "$CERT_DIR/intermediate.pkcs12" ]; then
    openssl req -x509 -newkey rsa:2048 -nodes \
      -keyout "$CERT_DIR/intermediate.key" \
      -out "$CERT_DIR/intermediate.pem" \
      -days 365 \
      -subj "/CN=Find-Intermediate-CA"
    
    openssl pkcs12 -export \
      -in "$CERT_DIR/intermediate.pem" \
      -inkey "$CERT_DIR/intermediate.key" \
      -out "$CERT_DIR/intermediate.pkcs12" \
      -name intermediate-ca \
      -password pass:$CA_PASS
    
    echo "Created $CERT_DIR/intermediate.pkcs12"
fi

# 3. Export root certificate (PEM)
cp "$CERT_DIR/intermediate.pem" "$CERT_DIR/ca.cert.pem"
echo "Created $CERT_DIR/ca.cert.pem"

echo "All SSL files generated in $CERT_DIR"

Usage

Put your nifi-cert.pem and nifi-key.key into certs/.

Run the script:

chmod +x generate_ssl.sh
./generate_ssl.sh


Mount certs/ in your Docker Compose as /ssl/certs and set the environment variables:

volumes:
  - ./certs:/ssl/certs:ro

environment:
  - IDOL_UI_SSL_PKCS_FILE=/ssl/certs/find-ui.pkcs12
  - IDOL_UI_SSL_PKCS_PASS=1234
  - IDOL_UI_SSL_CA_PKCS12=/ssl/certs/intermediate.pkcs12
  - IDOL_UI_SSL_CA_PASS=1234
  - IDOL_UI_ROOT_CERTIFICATE=/ssl/certs/ca.cert.pem


This ensures the container finds all the SSL files at the paths it expects.



# Additional Troubleshooting
## Run the TLS Toolkit in Docker (using NiFi Toolkit 1.2.1)
mkdir -p $(pwd)/certs
chmod 755 $(pwd)/certs
docker run --rm \
  --user $(id -u):$(id -g) \
  -v $(pwd)/certs:/opt/certs \
  apache/nifi-toolkit:1.28.1 \
  tls-toolkit standalone \
  -n 'OTX-F1ZF574.opentext.net' \
  -C 'subject=C = IL, ST = center, L = tel-aviv, O = demo, OU = demo, CN = OTX-F1ZF574.opentext.net, emailAddress = oattia@opentext.com' \
  -o /opt/certs

mkdir -p /opt/idol/idol-containers-toolkit/ssl/intermediate/
chmod 755 /opt/idol/idol-containers-toolkit/ssl/intermediate/
cd /opt/idol/idol-containers-toolkit/basic-idol
cp nifi/nifi-current/conf/keystore.jks nifi/nifi-current/conf/truststore.jks ../ssl/intermediate

## Run Customized NiFi SSL Configuration
mkdir -p $(pwd)/certs
chmod 755 $(pwd)/certs
### Create a Custom Certificate Authority
  1) Generate a private key for the custom CA.
      - openssl genpkey -algorithm RSA -out ca.key
  2) Generate a certificate signing request
      - openssl req -new -key ca.key -out ca.csr
      - [Note] A challenge password []:Passw0rd1!
  3) Generate the (self-signed) CA certificate
      - openssl x509 -req -days 365 -in ca.csr -key ca.key -out cacert.crt
      - [Output] subject=C = IL, ST = center, L = tel-aviv, O = demo, OU = demo, CN = OTX-F1ZF574.opentext.net, emailAddress = oattia@opentext.com

  **You now have the private key (ca.key) and CA certificate (cacert.crt) in PEM format.**

### Create a Server Certificate for a NiFi Node
  1) On the NiFi server, generate a private key for this node
      - openssl genpkey -algorithm RSA -out private.key
  2) Generate a certificate signing request
      - openssl req -new -key private.key -out request.csr
  3) On the machine where you created your custom certificate authority, use the CSR and generate the certificate
      - openssl x509 -req -days 365 -in request.csr -CA cacert.crt -CAkey ca.key -out nifi-server.crt
      - [Output] Certificate request self-signature ok
      - [Output] subject=C = IL, ST = center, L = tel-aviv, O = demo, OU = demo, CN = OTX-F1ZF574.opentext.net, emailAddress = oattia@opentext.com
  **nifi-server.crt is the SSL certificate that is generated for the NiFi node. This certificate is signed by your custom CA, so will be trusted providing that the CA is trusted.**

  4) Return to the NiFi server and combine the node's private key and certificate together as a PKCS #12 keystore
      - openssl pkcs12 -export -inkey private.key -in nifi-server.crt -out nifi-keystore.p12
      - [Note] Enter Export Password: Passw0rd1!

      
## Test your NiFi keystore password
    - [PKCS12] openssl pkcs12 -in nifi-keystore.p12 -noout -passin pass:Passw0rd1!
    - [JKS] keytool -list -keystore keystore.jks -storepass Passw0rd1!

          

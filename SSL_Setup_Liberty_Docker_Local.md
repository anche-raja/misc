# SSL Setup for J2EE App on WebSphere Liberty — Local Development (Docker)

**Use Case:** J2EE web application deployed on WebSphere Liberty in Docker on your local machine
needs to call an **internal corporate HTTPS web service** (e.g. address validation API). The
service uses a cert signed by a **private corporate CA** which is not in the JVM's default
`cacerts` — causing SSL handshake failures locally.

---

## Table of Contents

1. [Understanding the Problem](#1-understanding-the-problem)
2. [Understanding SSL Certificate Hierarchy](#2-understanding-ssl-certificate-hierarchy)
3. [Step 1 — Get the Corporate CA Certs](#3-step-1--get-the-corporate-ca-certs)
4. [Step 2 — Extract CA Certs Manually (if PKI team unavailable)](#4-step-2--extract-ca-certs-manually-if-pki-team-unavailable)
5. [Step 3 — Build the Truststore](#5-step-3--build-the-truststore)
6. [Step 4 — Generate a Self-Signed Keystore for Local Dev](#6-step-4--generate-a-self-signed-keystore-for-local-dev)
7. [Step 5 — Configure WebSphere Liberty server.xml](#7-step-5--configure-websphere-liberty-serverxml)
8. [Step 6 — Dockerfile](#8-step-6--dockerfile)
9. [Step 7 — Build and Run Locally](#9-step-7--build-and-run-locally)
10. [Debugging & Troubleshooting](#10-debugging--troubleshooting)
11. [Quick Checklist](#11-quick-checklist)
12. [Project Folder Structure](#12-project-folder-structure)

---

## 1. Understanding the Problem

Internal corporate services use SSL certificates signed by a **private corporate CA** that is not
in the JVM's default `cacerts`. When Liberty makes an outbound HTTPS call to such a service, the
JVM cannot validate the certificate chain and the connection is rejected.

```
Your App (Liberty JVM — running in Docker locally)
    └── Makes HTTPS call to internal-address-svc.corp.com
            └── Server presents its corporate-signed leaf cert
                    └── JVM checks: Is this cert's CA in MY truststore?
                            ├── Default cacerts → Corporate CA NOT found ❌
                            │     PKIX path building failed
                            │     SSLHandshakeException
                            │
                            └── Custom trust.jks with Corp CA → Found ✅
                                  Connection succeeds
```

**Fix for local dev:** Extract the corporate CA certs, build a `trust.jks` truststore, copy it
into the Docker image, and configure Liberty to use it for outbound HTTPS connections. Passwords
are passed as environment variables when running the container.

> **Note:** The `trust.jks` and `key.jks` are baked directly into the Docker image for local
> development convenience. This is **only acceptable for local dev** — for DEV / TEST / QA / PROD
> environments on AWS ECS Fargate, certs are injected via AWS Secrets Manager. See the separate
> wiki: `SSL_Setup_Liberty_Docker_Wiki.md`.

---

## 2. Understanding SSL Certificate Hierarchy

```
┌──────────────────────────────────────────────────────┐
│                    ROOT CA                           │
│  • Self-signed · managed by corporate PKI/SecOps     │
│  • Never installed on servers · stored offline       │
│  • Valid: 10–20 years                                │
│  e.g. "YourCorp Root CA"                             │
└───────────────────────┬──────────────────────────────┘
                        │ signs
┌───────────────────────▼──────────────────────────────┐
│                INTERMEDIATE CA                       │
│  • Signed by Root CA                                 │
│  • Signs all individual server (leaf) certs          │
│  • Valid: 3–5 years                                  │
│  e.g. "YourCorp Internal Services CA"                │
└────────────────────────┬─────────────────────────────┘
                         │ signs
              ┌──────────▼────────────┐
              │   Server leaf cert    │
              │ internal-svc.corp.com │
              │   Valid: 1 year       │
              └───────────────────────┘
              LEAF CERT — DO NOT import into truststore
```

| Cert Layer | Import into trust.jks? | Why |
|---|---|---|
| Root CA | ✅ Yes | Anchors the chain of trust |
| Intermediate CA | ✅ Yes | Signs all server certs |
| Leaf / Server cert | ❌ Never | Specific to one server, expires yearly |

---

## 3. Step 1 — Get the Corporate CA Certs

**Fastest path:** Contact your **PKI / SecOps team** and ask:

> *"Can you provide the Root CA and Intermediate CA certificates for internal corporate services
> in PEM format — ideally as a single `corporate-ca-chain.pem` file?"*

They will provide one of:

```
corporate-root-ca.pem           ← Root CA only
corporate-intermediate-ca.pem   ← Intermediate CA only

  — OR —

corporate-ca-chain.pem           ← Both combined (preferred)
```

Once you have these files, skip to [Step 3: Build the Truststore](#5-step-3--build-the-truststore).

> Also ask: *"Does our corporate network do TLS/SSL inspection on outbound traffic?"*
> If YES — the proxy swaps the target cert with a corp-signed one. You need the **proxy's CA cert**
> instead. The network/proxy team will provide it.

---

## 4. Step 2 — Extract CA Certs Manually (if PKI team unavailable)

### Extract the full cert chain from the target service

```bash
# Replace <host> and <port> with your internal service details
openssl s_client -connect <host>:<port> -showcerts 2>/dev/null
```

### Understand the output

```
Certificate chain
 0 s:CN=internal-address-svc.corp.com    ← LEAF cert      — DO NOT import
   i:CN=YourCorp Internal Services CA
-----BEGIN CERTIFICATE-----
MIIDxxx...                               ← Certificate[0] — SKIP THIS
-----END CERTIFICATE-----

 1 s:CN=YourCorp Internal Services CA    ← INTERMEDIATE CA — IMPORT THIS
   i:CN=YourCorp Root CA
-----BEGIN CERTIFICATE-----
MIIDyyy...                               ← Certificate[1]
-----END CERTIFICATE-----

 2 s:CN=YourCorp Root CA                 ← ROOT CA         — IMPORT THIS
   i:CN=YourCorp Root CA                 (subject = issuer = self-signed)
-----BEGIN CERTIFICATE-----
MIIDzzz...                               ← Certificate[2]
-----END CERTIFICATE-----
```

**How to identify each layer:**
- `Certificate[0]` — subject matches the service hostname → **Leaf cert, skip**
- `Certificate[1]` — subject is a CA name, issuer is a different CA → **Intermediate CA, save**
- `Certificate[last]` — subject and issuer are identical → **Root CA, save**

### Save each CA cert to a file

```bash
# Save Intermediate CA (Certificate[1] block only)
cat > intermediate-ca.pem << 'EOF'
-----BEGIN CERTIFICATE-----
<paste Certificate[1] content here — the full block between BEGIN and END inclusive>
-----END CERTIFICATE-----
EOF

# Save Root CA (Certificate[2] block only)
cat > root-ca.pem << 'EOF'
-----BEGIN CERTIFICATE-----
<paste Certificate[2] content here — the full block between BEGIN and END inclusive>
-----END CERTIFICATE-----
EOF
```

### Verify the certs

```bash
# Check Intermediate CA — confirm CA:TRUE and review expiry
openssl x509 -in intermediate-ca.pem -noout -subject -issuer -dates -ext basicConstraints

# Check Root CA — subject and issuer must be identical
openssl x509 -in root-ca.pem -noout -subject -issuer -dates -ext basicConstraints

# Verify the full chain resolves — must return "OK"
openssl verify -CAfile root-ca.pem -untrusted intermediate-ca.pem intermediate-ca.pem
# Expected: intermediate-ca.pem: OK
```

---

## 5. Step 3 — Build the Truststore

```bash
# Import Intermediate CA — this creates trust.jks if it does not exist yet
keytool -import \
  -alias corp-intermediate-ca \
  -file intermediate-ca.pem \
  -keystore trust.jks \
  -storepass changeit \
  -noprompt

# Import Root CA into the same truststore
keytool -import \
  -alias corp-root-ca \
  -file root-ca.pem \
  -keystore trust.jks \
  -storepass changeit \
  -noprompt

# If PKI team gave you a combined chain file, import as a single entry instead:
# keytool -import -alias corp-ca-chain -file corporate-ca-chain.pem \
#   -keystore trust.jks -storepass changeit -noprompt

# Verify truststore contents
keytool -list -v -keystore trust.jks -storepass changeit | grep -E "Alias|Owner|Issuer|Valid"
```

Expected output:

```
Alias name: corp-intermediate-ca
Owner: CN=YourCorp Internal Services CA, O=YourCorp, C=US
Issuer: CN=YourCorp Root CA, O=YourCorp, C=US
Valid from: Mon Jan 01 ...  until: Sat Jan 01 ...

Alias name: corp-root-ca
Owner: CN=YourCorp Root CA, O=YourCorp, C=US
Issuer: CN=YourCorp Root CA, O=YourCorp, C=US   ← same as Owner = self-signed root
Valid from: Mon Jan 01 ...  until: ...
```

---

## 6. Step 4 — Generate a Self-Signed Keystore for Local Dev

Liberty requires a `key.jks` (its own identity keystore) even when only making outbound calls.
For local development, a self-signed cert is sufficient.

```bash
keytool -genkeypair \
  -alias liberty-local \
  -keyalg RSA \
  -keysize 2048 \
  -validity 365 \
  -keystore key.jks \
  -storepass localKeyPass \
  -dname "CN=localhost, OU=Dev, O=YourCorp, C=US"
```

> Do not reuse this `key.jks` in any non-local environment. Each environment should have its own
> keystore managed by the appropriate team.

---

## 7. Step 5 — Configure WebSphere Liberty server.xml

```xml
<server>

    <featureManager>
        <!-- Required for outbound SSL support -->
        <feature>ssl-1.0</feature>
        <feature>transportSecurity-1.0</feature>

        <!-- Your existing application features — add as needed -->
        <feature>servlet-4.0</feature>
        <feature>jaxrs-2.1</feature>
        <feature>jndi-1.0</feature>
    </featureManager>

    <!--
        Liberty's own identity keystore.
        For local dev, this is the self-signed key.jks generated in Step 4.
        Password is injected via the KEY_JKS_PASSWORD environment variable.
    -->
    <keyStore id="defaultKeyStore"
              location="${server.config.dir}/resources/security/key.jks"
              password="${env.KEY_JKS_PASSWORD}" />

    <!--
        Truststore containing the corporate Root CA and Intermediate CA certs.
        This is what allows Liberty to validate the internal service's certificate.
        Password is injected via the TRUST_JKS_PASSWORD environment variable.
    -->
    <keyStore id="outboundTrustStore"
              location="${server.config.dir}/resources/security/trust.jks"
              password="${env.TRUST_JKS_PASSWORD}" />

    <!--
        SSL configuration wiring both keystores together.
        sslProtocol: TLSv1.2 minimum. Change to TLSv1.3 if the target service requires it.
    -->
    <ssl id="defaultSSLConfig"
         keyStoreRef="defaultKeyStore"
         trustStoreRef="outboundTrustStore"
         sslProtocol="TLSv1.2" />

    <!--
        Apply this SSL config to ALL outbound HTTPS connections from Liberty.
        To restrict to a specific internal host only, replace * with the hostname:
        <outboundConnection host="internal-address-svc.corp.com" sslRef="defaultSSLConfig" />
    -->
    <outboundConnection host="*" sslRef="defaultSSLConfig" />

</server>
```

> `${env.VAR_NAME}` — Liberty reads these from environment variables at startup.
> Set `TRUST_JKS_PASSWORD` and `KEY_JKS_PASSWORD` when running the Docker container (see Step 7).

---

## 8. Step 6 — Dockerfile

For local development, `trust.jks` and `key.jks` are copied directly into the image.

```dockerfile
FROM icr.io/appcafe/websphere-liberty:kernel-java17-openj9-ubi

# Copy application WAR
COPY --chown=1001:0 myapp.war /config/apps/

# Copy Liberty server configuration
COPY --chown=1001:0 server.xml /config/

# Copy keystores directly into the image — LOCAL DEV ONLY
# For non-local environments (DEV/TEST/QA/PROD on ECS Fargate),
# certs are injected via AWS Secrets Manager. See SSL_Setup_Liberty_Docker_Wiki.md
COPY --chown=1001:0 trust.jks /config/resources/security/trust.jks
COPY --chown=1001:0 key.jks   /config/resources/security/key.jks

# Install Liberty features declared in server.xml
RUN features.sh

USER 1001
```

---

## 9. Step 7 — Build and Run Locally

```bash
# Build the Docker image
docker build -t myapp:local .

# Run the container — inject keystore passwords as environment variables
docker run -d \
  --name myapp-local \
  -p 9080:9080 \
  -p 9443:9443 \
  -e TRUST_JKS_PASSWORD=changeit \
  -e KEY_JKS_PASSWORD=localKeyPass \
  myapp:local

# Tail the startup logs — look for "server is ready to run a smarter planet"
docker logs -f myapp-local
```

### Using Docker Compose (optional)

```yaml
# docker-compose.local.yml
version: '3.8'
services:
  myapp:
    build: .
    container_name: myapp-local
    ports:
      - "9080:9080"
      - "9443:9443"
    environment:
      - TRUST_JKS_PASSWORD=changeit
      - KEY_JKS_PASSWORD=localKeyPass
```

```bash
docker compose -f docker-compose.local.yml up --build
```

---

## 10. Debugging & Troubleshooting

### Step 1 — Test HTTPS connectivity from inside the container

```bash
# Shell into the running container
docker exec -it myapp-local bash

# Test the internal service endpoint directly
curl -v https://internal-address-svc.corp.com

# Interpretation:
#   curl succeeds, Liberty HTTPS call fails → truststore issue (follow steps below)
#   curl also fails                         → network/firewall issue on your machine
#   curl fails with cert error              → CA cert issue — check what you imported
```

### Step 2 — Verify the truststore inside the container

```bash
docker exec -it myapp-local \
  keytool -list -v \
  -keystore /config/resources/security/trust.jks \
  -storepass changeit \
  | grep -E "Alias|Owner|Issuer|Valid"

# Must show corp-intermediate-ca and corp-root-ca entries.
# If empty or wrong entries → rebuild trust.jks from Step 3.
```

### Step 3 — Enable SSL debug logging in Liberty

Add **temporarily** to `server.xml` to see the full SSL handshake in Docker logs:

```xml
<logging traceSpecification="SSL=all:handshake=all" />
```

Or add to `jvm.options` in the Liberty server config directory:

```
-Djavax.net.debug=ssl:handshake
```

Then check logs:

```bash
docker logs myapp-local 2>&1 | grep -i "ssl\|handshake\|PKIX\|certificate"
```

> Remove these debug settings after diagnosis — they generate very large log volumes.

### Step 4 — Verify the full cert chain resolves

```bash
# Run against the live internal service using your CA pem file
openssl s_client -connect internal-address-svc.corp.com:443 -CAfile root-ca.pem

# Look for at the bottom of the output:
#   Verify return code: 0 (ok)    → chain is trusted, your CA pem is correct
#   Verify return code: 2 (...)   → CA cert does not match — wrong CA file
#   Verify return code: 20 (...)  → Intermediate cert missing from chain
```

### Common Errors and Fixes

| Error | Root Cause | Fix |
|---|---|---|
| `PKIX path building failed: unable to find valid certification path` | Corporate CA not in trust.jks | Import Intermediate CA + Root CA — not the leaf cert |
| `SSLHandshakeException: Received fatal alert: handshake_failure` | TLS protocol mismatch | Change `sslProtocol="TLSv1.2"` to `TLSv1.3` in server.xml or vice versa |
| `SSLHandshakeException: Certificate unknown` | Wrong cert imported (likely the leaf) | Re-extract: import Certificate[1] and [2] only |
| `hostname in certificate didn't match` | URL uses IP or wrong hostname | Use exact hostname matching the cert CN or SAN field |
| `Connection refused` | Network issue — not an SSL problem | Check if the service is reachable from your machine |
| `curl works inside container, Liberty still fails` | trust.jks not picked up by Liberty | Verify `<outboundConnection>` and `<keyStore>` config in server.xml |
| `FileNotFoundException: trust.jks` | Wrong path or file not copied into image | Verify `COPY` paths in Dockerfile match `location` in `<keyStore>` |
| `java.io.IOException: Invalid keystore format` | Corrupted JKS file | Delete and rebuild trust.jks from scratch with `keytool -import` |
| `Environment variable TRUST_JKS_PASSWORD not set` | Missing `-e` flag when running Docker | Add `-e TRUST_JKS_PASSWORD=changeit` to `docker run` command |

---

## 11. Quick Checklist

- [ ] Contacted PKI team for `corporate-ca-chain.pem` — OR extracted manually with `openssl s_client -showcerts`
- [ ] Confirmed you saved **CA certs only** — Certificate[1] and [2], NOT Certificate[0] (the leaf)
- [ ] Ran `openssl verify` to confirm the chain resolves to OK
- [ ] Created `trust.jks` with Intermediate CA and Root CA imported via `keytool -import`
- [ ] Verified `trust.jks` contents with `keytool -list` — two entries visible
- [ ] Generated self-signed `key.jks` for local Liberty identity
- [ ] Added `ssl-1.0` and `transportSecurity-1.0` features in `server.xml`
- [ ] Added `<keyStore id="outboundTrustStore">` pointing to `trust.jks` in `server.xml`
- [ ] Added `<ssl id="defaultSSLConfig">` referencing both keystores in `server.xml`
- [ ] Added `<outboundConnection host="*" sslRef="defaultSSLConfig" />` in `server.xml`
- [ ] Passwords use `${env.TRUST_JKS_PASSWORD}` and `${env.KEY_JKS_PASSWORD}` — not hardcoded
- [ ] `trust.jks` and `key.jks` are `COPY`'d into the Dockerfile
- [ ] Container runs with `-e TRUST_JKS_PASSWORD=changeit -e KEY_JKS_PASSWORD=localKeyPass`
- [ ] Tested `curl -v https://internal-svc.corp.com` from inside the running container
- [ ] Application successfully connects to the internal corporate service

---

## 12. Project Folder Structure

```
myapp/
├── src/
│   └── main/
│       └── webapp/ ...
├── server.xml                          ← Liberty config (same for all environments)
├── Dockerfile                          ← Local dev Dockerfile (JKS files copied in)
├── docker-compose.local.yml            ← Optional local compose file
├── security/                           ← Local dev only — NEVER commit to git
│   ├── trust.jks                       ← Corporate CA truststore
│   ├── key.jks                         ← Self-signed Liberty keystore
│   ├── intermediate-ca.pem             ← Intermediate CA source cert
│   └── root-ca.pem                     ← Root CA source cert
└── .gitignore
```

### Add to `.gitignore` — never commit JKS or PEM files

```gitignore
# SSL keystores and certificates — never commit to version control
security/
*.jks
*.pem
*.p12
*.pfx
*.b64
```

---

## Important Notes for Moving Beyond Local

When you promote this application to **DEV / TEST / QA / PROD** environments running on
**AWS ECS Fargate**, the approach changes completely:

```
Local dev         → JKS files baked into Docker image (this wiki)
ECS Fargate envs  → JKS files stored as base64 in AWS Secrets Manager,
                    injected as env vars, decoded at container startup
                    via entrypoint.sh (see SSL_Setup_Liberty_Docker_Wiki.md)
```

The `server.xml` remains **identical** across local and all Fargate environments —
only the delivery mechanism for the JKS files changes.

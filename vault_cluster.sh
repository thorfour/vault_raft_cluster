#!/usr/bin/sh
set -eou pipefail

clusterSize="${cluster_size:-$1}"
basePort=8200

generate_ca() {
    openssl genrsa -out myCA.key 2048
}

generate_ca_crt() {
    openssl req -x509 -new -nodes -key myCA.key -sha256 -days 1825 -out myCA.pem -subj "/C=/ST=/L=/O=/OU=/CN=/emailAddress=" 2> /dev/null
}

generate_key() {
    openssl genrsa -out vault$1.key 2048
}

generate_csr() {
    openssl req -new -key vault$1.key -out vault$1.csr -subj "/C=/ST=/L=/O=/OU=/CN=/emailAddress=" 2> /dev/null
}

generate_config() {
size=$1
port=$2
index=$3

tee "config$index.hcl" 1> /dev/null <<EOF
ui = true
storage "raft" {
    path    = "/vault"
    node_id = "vault_$index"
EOF
for ((i=0; i < $size; i++))
do

let a=$port+$i*2
let b=$a+1

# skip retry join section for own port
if [ $i -eq $j ]
then
    continue
fi

tee -a "config$index.hcl" 1> /dev/null <<EOF 
    retry_join {
        leader_api_addr = "https://vault$i:$a"
        leader_ca_cert = "-----BEGIN CERTIFICATE-----\nMIIDZTCCAk2gAwIBAgIUIv9u8d2jbx/TqjkEWU8HVzMXkIgwDQYJKoZIhvcNAQEL\nBQAwQjELMAkGA1UEBhMCWFgxFTATBgNVBAcMDERlZmF1bHQgQ2l0eTEcMBoGA1UE\nCgwTRGVmYXVsdCBDb21wYW55IEx0ZDAeFw0yMDA1MDgyMTQ4MThaFw0yNTA1MDcy\nMTQ4MThaMEIxCzAJBgNVBAYTAlhYMRUwEwYDVQQHDAxEZWZhdWx0IENpdHkxHDAa\nBgNVBAoME0RlZmF1bHQgQ29tcGFueSBMdGQwggEiMA0GCSqGSIb3DQEBAQUAA4IB\nDwAwggEKAoIBAQC6gmYEqH+Vgh0Um4bQytqo4YkAtRGyjHPo9gG1qg608Nd9JQRe\nJBkH4QMNc8i+ti4zdsy8/S15Yc1HWp/nbuxtPzDB7XzmrWMRFp0/qJ6BE5LKmGKS\nChEUdd+BbTL07NJneJs6mUcLkHNDEQ7cXjxILBbkg8smSZoUxDjED2iTIqbkV0T/\nkYGZekQMMrKZBG6cpwmxpI7ib2n7s34yCHYGub9uy637cyJLPpMiJmCEgTm2zNbz\nl02K+zcEZWZHWMsPNM1MVdVvdf16RBjCdqF1zCtGosqn3qdWEmrUAt20lYEUapbF\nSoIm8L3iXVw+vIZoIZi8J7TlvpeSCCzcvHgjAgMBAAGjUzBRMB0GA1UdDgQWBBSd\nuXzDkqCAIBJtA8RHpH4jBr5F/jAfBgNVHSMEGDAWgBSduXzDkqCAIBJtA8RHpH4j\nBr5F/jAPBgNVHRMBAf8EBTADAQH/MA0GCSqGSIb3DQEBCwUAA4IBAQAeJiZwxQMq\nu/Ku1gBMXHQkGfxLCv4Kz75AhE76wGrWe8VIshRoe6e7FCpZkPQndwulrL11GJzt\n1yhhjNs3o1/+drxWP5DAuLnAWhf7vlvKexdi3VEO/YgDbPMNzIc3xF9kUjyYzLxj\nYQ2srh75uTpEUCfUzrHcIpjCW0f1Ir4WG490Zk2+pJLtzfOlu/uPN+w3Ul0EhlT1\nQrPBa5bdLPj7sjvbAyHpPQW5MsDKLT3l8LRsAXf62wheU7GUUtnVq5lBWrAysbFG\nTiwKwA6Z9Hhei/APPs+64mm25f4NkUZtql1o5S0LD8MBbZ7Ax3JWxzTZhlLxCQe4\n8B9vBw1Jq7Zy\n-----END CERTIFICATE-----"
    }
EOF
done

let a=$port+$j*2
let b=$a+1

tee -a "config$index.hcl" 1> /dev/null <<EOF
}
listener "tcp" {
    address = "0.0.0.0:$a"
    cluster_address = "vault$index:$b"
    tls_disable = false
    tls_cert_file = "/certs/vault$index.crt"
    tls_key_file = "/certs/vault$index.key"
}
token = "root"
disable_mlock = true
cluster_addr = "https://vault$index:$b"
EOF
}

for ((j=0; j < $clusterSize; j++))
do
    echo "Generating config for $j"
    generate_config $clusterSize $basePort $j
done

for ((j=0; j < $clusterSize; j++))
do
    let port=$basePort+$j*2
    let port2=$port+1
    echo "Starting Vault in docker on ports $port and $port2"
    docker run -d --network vault --name vault$j --rm -e VAULT_API_ADDR="https://0.0.0.0:$port" -e SKIP_SETCAP=true -p $port2:$port2 -p $port:$port -v $(pwd)/config$j.hcl:/config.hcl -v $(pwd)/certs/:/certs vault vault server -config /config.hcl
done

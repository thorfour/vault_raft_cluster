#!/usr/bin/sh
set -eou pipefail

clusterSize="${cluster_size:-$1}"
basePort=8200

generate_ca() {
    openssl genrsa -out myCA.key 2048 &> /dev/null
}

generate_ca_crt() {
    openssl req -x509 -new -nodes -key myCA.key -sha256 -days 1825 -out myCA.pem -subj "/C=/ST=/L=/O=/OU=/CN=/emailAddress=" &> /dev/null
}

generate_key() {
    openssl genrsa -out vault$1.key 2048 &> /dev/null
    chmod 664 vault$1.key
}

generate_csr() {
    openssl req -new -key vault$1.key -out vault$1.csr -subj "/C=/ST=/L=/O=/OU=/CN=/emailAddress=" &> /dev/null 
}

sign_crt() {
tee "vault$1.ext" 1> /dev/null <<EOF
authorityKeyIdentifier=keyid,issuer
basicConstraints=CA:FALSE
keyUsage = digitalSignature, nonRepudiation, keyEncipherment, dataEncipherment
subjectAltName = @alt_names

[alt_names]
DNS.1 = vault$1
DNS.2 = localhost
IP.1 = 0.0.0.0
IP.2 = 127.0.0.1
EOF

openssl x509 -req -in vault$1.csr -CA myCA.pem -CAkey myCA.key -CAcreateserial \
    -out vault$1.crt -days 1825 -sha256 -extfile vault$1.ext &> /dev/null
}

generate_all_certs() {
    size=$1
    mkdir -p certs
    pushd certs

    generate_ca
    generate_ca_crt

    for ((i=0; i < $size; i++))
    do
        generate_key $i
        generate_csr $i
        sign_crt $i
    done

    popd
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
        leader_ca_cert = "$(sed ':a;N;$!ba;s,\n,\\n,g' certs/myCA.pem)"
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

main() {

docker network create vault 2> /dev/null && true

generate_all_certs $clusterSize

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

init_response=$(VAULT_CACERT=certs/myCA.pem vault operator init -format=json -key-shares 1 -key-threshold 1)

key=$(echo $init_response | jq -r .unseal_keys_b64[0])
token=$(echo $init_response | jq -r .root_token)

echo ""
echo "======================================================"
echo "Key: $key"
echo "Root Token: $token"
echo "======================================================"
echo ""

# Unseal remainder of Vault instances
for ((j = 0; j < $clusterSize; j++))
do
    let port=$basePort+$j*2
    VAULT_CACERT=certs/myCA.pem vault operator unseal -address=https://localhost:$port $key 1> /dev/null
    sleep 15
done
}

main

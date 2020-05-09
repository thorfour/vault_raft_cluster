#!/usr/bin/sh
set -eou pipefail

# TODO make this simply a ./vault_cluster 3 where it just takes the cluster size and does everything else
# will need to generate the configs
clusterSize="${cluster_size:-$1}"
basePort=8200
cfg="testconfig.hcl"

generate_config() {
tee "$cfg" 1> /dev/null <<EOF
ui = true
storage "raft" {
    path    = "/vault"
    node_id = "vault_1"
EOF
a=("$@")
for i in "${a[@]}"
do
tee -a "$cfg" 1> /dev/null <<EOF 
    retry_join {
        leader_api_addr = "https://vault2:$i"
        leader_ca_cert = "-----BEGIN CERTIFICATE-----\nMIIDZTCCAk2gAwIBAgIUIv9u8d2jbx/TqjkEWU8HVzMXkIgwDQYJKoZIhvcNAQEL\nBQAwQjELMAkGA1UEBhMCWFgxFTATBgNVBAcMDERlZmF1bHQgQ2l0eTEcMBoGA1UE\nCgwTRGVmYXVsdCBDb21wYW55IEx0ZDAeFw0yMDA1MDgyMTQ4MThaFw0yNTA1MDcy\nMTQ4MThaMEIxCzAJBgNVBAYTAlhYMRUwEwYDVQQHDAxEZWZhdWx0IENpdHkxHDAa\nBgNVBAoME0RlZmF1bHQgQ29tcGFueSBMdGQwggEiMA0GCSqGSIb3DQEBAQUAA4IB\nDwAwggEKAoIBAQC6gmYEqH+Vgh0Um4bQytqo4YkAtRGyjHPo9gG1qg608Nd9JQRe\nJBkH4QMNc8i+ti4zdsy8/S15Yc1HWp/nbuxtPzDB7XzmrWMRFp0/qJ6BE5LKmGKS\nChEUdd+BbTL07NJneJs6mUcLkHNDEQ7cXjxILBbkg8smSZoUxDjED2iTIqbkV0T/\nkYGZekQMMrKZBG6cpwmxpI7ib2n7s34yCHYGub9uy637cyJLPpMiJmCEgTm2zNbz\nl02K+zcEZWZHWMsPNM1MVdVvdf16RBjCdqF1zCtGosqn3qdWEmrUAt20lYEUapbF\nSoIm8L3iXVw+vIZoIZi8J7TlvpeSCCzcvHgjAgMBAAGjUzBRMB0GA1UdDgQWBBSd\nuXzDkqCAIBJtA8RHpH4jBr5F/jAfBgNVHSMEGDAWgBSduXzDkqCAIBJtA8RHpH4j\nBr5F/jAPBgNVHRMBAf8EBTADAQH/MA0GCSqGSIb3DQEBCwUAA4IBAQAeJiZwxQMq\nu/Ku1gBMXHQkGfxLCv4Kz75AhE76wGrWe8VIshRoe6e7FCpZkPQndwulrL11GJzt\n1yhhjNs3o1/+drxWP5DAuLnAWhf7vlvKexdi3VEO/YgDbPMNzIc3xF9kUjyYzLxj\nYQ2srh75uTpEUCfUzrHcIpjCW0f1Ir4WG490Zk2+pJLtzfOlu/uPN+w3Ul0EhlT1\nQrPBa5bdLPj7sjvbAyHpPQW5MsDKLT3l8LRsAXf62wheU7GUUtnVq5lBWrAysbFG\nTiwKwA6Z9Hhei/APPs+64mm25f4NkUZtql1o5S0LD8MBbZ7Ax3JWxzTZhlLxCQe4\n8B9vBw1Jq7Zy\n-----END CERTIFICATE-----"
    }
EOF
done
tee -a "$cfg" 1> /dev/null <<EOF
}
listener "tcp" {
    address = "0.0.0.0:8200"
    cluster_address = "vault1:8201"
    tls_disable = false
    tls_cert_file = "/certs/vault1.crt"
    tls_key_file = "/certs/vault1.key"
}
token = "root"
disable_mlock = true
cluster_addr = "https://vault1:8201"
EOF
}

apiPorts=()
clusterPorts=()
for ((i=0; i < $clusterSize; i++))
do 
    let a=$basePort+$i*2
    let b=$a+1
    echo "Ports for $i: $a, $b"
    apiPorts+=($a)
    clusterPorts+=($b)
done

retry_join=$(generate_config "${apiPorts[@]}")

#docker run --network vault --name vault${config} --rm -it -e VAULT_API_ADDR="https://0.0.0.0:${port1}" -e SKIP_SETCAP=true -p ${port2}:${port2} -p ${port1}:${port1} -v $(pwd)/config${config}.hcl:/config.hcl -v $(pwd)/certs/:/certs vault vault server -config /config.hcl

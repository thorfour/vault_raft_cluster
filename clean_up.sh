rm -rf certs
rm config*.hcl

for ((i=0; i < $1; i++))
do
    docker stop vault$i
done

docker network rm vault

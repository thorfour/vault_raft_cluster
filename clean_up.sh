rm -rf certs 2> /dev/null
rm config*.hcl 2> /dev/null 

for ((i=0; i < $1; i++))
do
    docker stop vault$i 2> /dev/null
done

docker network rm vault 2> /dev/null

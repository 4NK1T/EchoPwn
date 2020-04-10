#!/bin/bash

echo "Starting SubEnum $1"

echo "Creating directory"
set -e
if [ ! -d $PWD/EchoPwn ]; then
	mkdir EchoPwn
fi
mkdir EchoPwn/$1/
source tokens.txt

echo "Starting our subdomain enumeration force..."

echo "Starting Knock.py"
python knock/knockpy/knockpy.py "$1" >> EchoPwn/$1/fromknock.txt

echo "Starting Sublist3r..."
python3 Sublist3r/sublist3r.py -d "$1" -o EchoPwn/$1/fromsublister.txt

echo "Starting our crtsh script..."
python3 crt.py -q "%25.$1" >> EchoPwn/$1/fromcrt.txt

echo "Amass turn..."
amass enum --passive -d $1 -o EchoPwn/$1/fromamass.txt

echo "Starting subfinder..."
./subfinder -d $1 -o EchoPwn/$1/fromsubfinder.txt -v --exclude-sources dnsdumpster

echo "Starting assetfinder..."
./assetfinder --subs-only $1 > EchoPwn/$1/fromassetfinder.txt

echo "Starting aquatone-discover"
aquatone-discover -d $1 --disable-collectors dictionary -t 300
rm -rf amass_output
cat ~/aquatone/$1/hosts.txt | cut -f 1 -d ',' | sort -u >> EchoPwn/$1/fromaquadiscover.txt
rm -rf ~/aquatone/$1/

echo "Starting github-subdomains..."
python3 github-subdomains.py -t $github_token_value -d $1 | sort -u >> EchoPwn/$1/fromgithub.txt

echo "Starting findomain"
#export findomain_fb_token="$findomain_fb_token"
export findomain_spyse_token="findomain_spyse_token"
export findomain_virustotal_token="findomain_virustotal_token"

findomain -t $1 -r -u EchoPwn/$1/fromfindomain.txt

echo "Starting bufferover"
curl "http://dns.bufferover.run/dns?q=$1" --silent | jq '.FDNS_A | .[]' -r 2>/dev/null | cut -f 2 -d',' | sort -u >> EchoPwn/$1/frombufferover-dns.txt
curl "http://dns.bufferover.run/dns?q=$1" --silent | jq '.RDNS | .[]' -r 2>/dev/null | cut -f 2 -d',' | sort -u >> EchoPwn/$1/frombufferover-dns-rdns.txt
curl "http://tls.bufferover.run/dns?q=$1" --silent | jq '. | .Results | .[]'  -r 2>/dev/null | cut -f 3 -d ',' | sort -u >> EchoPwn/$1/frombufferover-tls.txt

echo "Starting our custom bruteforcer"
for sub in $(cat subdomains.txt); do echo $sub.$1 >> /tmp/sub-$1.txt; done
./massdns/bin/massdns -r massdns/lists/resolvers.txt -q -t A -o S -w /tmp/subresolved-$1.txt /tmp/sub-$1.txt
rm /tmp/sub-$1.txt
awk -F ". " "{print \$1}" /tmp/subresolved-$1.txt | sort -u >> EchoPwn/$1/fromcustbruter.txt
rm /tmp/subresolved-$1.txt
cat EchoPwn/$1/*.txt | grep $1 | grep -v '*' | sort -u  >> EchoPwn/$1/alltogether.txt

echo "Deleting other(older) results"
rm -rf EchoPwn/$1/from*

echo "Resolving - Part 1"
./massdns/bin/massdns -r massdns/lists/resolvers.txt -q -t A -o S -w /tmp/massresolved1.txt EchoPwn/$1/alltogether.txt
awk -F ". " "{print \$1}" /tmp/massresolved1.txt | sort -u >> EchoPwn/$1/resolved1.txt
rm /tmp/massresolved1.txt
rm EchoPwn/$1/alltogether.txt

echo "Removing wildcards"
python3 wildcrem.py EchoPwn/$1/resolved1.txt >> EchoPwn/$1/resolved1-nowilds.txt
rm EchoPwn/$1/resolved1.txt

echo "Starting AltDNS..."
altdns -i EchoPwn/$1/resolved1-nowilds.txt -o EchoPwn/$1/fromaltdns.txt -t 300

echo "Resolving - Part 2 - Altdns results"
./massdns/bin/massdns -r massdns/lists/resolvers.txt -q -t A -o S -w /tmp/massresolved1.txt EchoPwn/$1/fromaltdns.txt
awk -F ". " "{print \$1}" /tmp/massresolved1.txt | sort -u >> EchoPwn/$1/altdns-resolved.txt
rm /tmp/massresolved1.txt
rm EchoPwn/$1/fromaltdns.txt

echo "Removing wildcards - Part 2"
python3 wildcrem.py EchoPwn/$1/altdns-resolved.txt >> EchoPwn/$1/altdns-resolved-nowilds.txt
rm EchoPwn/$1/altdns-resolved.txt

cat EchoPwn/$1/*.txt | sort -u >> EchoPwn/$1/alltillnow.txt
rm EchoPwn/$1/altdns-resolved-nowilds.txt
rm EchoPwn/$1/resolved1-nowilds.txt

echo "Starting DNSGEN..."
dnsgen EchoPwn/$1/alltillnow.txt >> EchoPwn/$1/fromdnsgen.txt

echo "Resolving - Part 3 - DNSGEN results"
./massdns/bin/massdns -r massdns/lists/resolvers.txt -q -t A -o S -w /tmp/massresolved1.txt EchoPwn/$1/fromdnsgen.txt
awk -F ". " "{print \$1}" /tmp/massresolved1.txt | sort -u >> EchoPwn/$1/dnsgen-resolved.txt
rm /tmp/massresolved1.txt
#rm /tmp/forbrut.txt
rm EchoPwn/$1/fromdnsgen.txt

echo "Removing wildcards - Part 3"
python3 wildcrem.py EchoPwn/$1/dnsgen-resolved.txt >> EchoPwn/$1/dnsgen-resolved-nowilds.txt
rm EchoPwn/$1/dnsgen-resolved.txt

cat EchoPwn/$1/alltillnow.txt | sort -u >> EchoPwn/$1/$1.txt
rm EchoPwn/$1/dnsgen-resolved-nowilds.txt
rm EchoPwn/$1/alltillnow.txt
#rm -rf EchoPwn/$1/

echo "Appending http/s to hosts"
for i in $(cat EchoPwn/$1/$1.txt); do echo "http://$i" && echo "https://$i"; done >> EchoPwn/$1/with-protocol-domains.txt

echo "Taking screenshots..."
cat EchoPwn/$1/with-protocol-domains.txt | ./aquatone -ports xlarge -out EchoPwn/$1/aquascreenshots

echo "Notifying you on slack"
#curl -X POST -H 'Content-type: application/json' --data '{"text":"SubEnum finished scanning: '$1'"}' $slack_url

echo "Total hosts found: $(wc -l EchoPwn/$1/$1.txt)"

if [[ "$*" = *"-nmap"* ]]
then
	echo "Starting Nmap"
	mkdir Echopwn/$1/nmap
	for i in $(cat Echopwn/$1/$1.txt); do nmap -sC -sV $i -o EchoPwn/$1/nmap/$i.txt; done
fi

echo "AWS S3 check"
for i in $(cat Echopwn/$1/$1.txt); do aws s3 ls s3://$i >> EchoPwn/$1/aws.txt; done

echo "DirSearch"
cat EchoPwn/$1/$1.txt | xargs -P10 -I % sh -c "python3 dirsearch/dirsearch.py -e php,asp,aspx,jsp,html,zip,jar -w dirsearch/db/dicc.txt -t 80 -u %1$1"
for i in $(cat Echopwn/$1/$1.txt); do python3 dirsearch/dirsearch.py -e php,asp,aspx,jsp,html,zip,jar -w dirsearch/db/dicc.txt -t 80 -u $i | tee Echopwn/$1/dirseach/$i.txt; done

echo "Finished successfully."
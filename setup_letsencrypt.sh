#!/bin/bash

# Controleer of het script met sudo rechten wordt uitgevoerd
if [ "$(id -u)" != "0" ]; then
   echo "Dit script moet worden uitgevoerd met sudo rechten" 1>&2
   exit 1
fi

# Functie om hulpbericht te tonen
usage() {
  echo "Gebruik: $0 -api <cloudflare_api_token> -domain <domein> -ip <ip_adres> -pdns_api <powerdns_api_token> -pdns_server <powerdns_server_url>"
  exit 1
}

# Argumenten parsen
while [ "$1" != "" ]; do
    case $1 in
        -api )              shift
                            CF_API_TOKEN=$1
                            ;;
        -domain )           shift
                            DOMAIN=$1
                            ;;
        -ip )               shift
                            IP_ADDRESS=$1
                            ;;
        -pdns_api )         shift
                            PDNS_API_TOKEN=$1
                            ;;
        -pdns_server )      shift
                            PDNS_SERVER_URL=$1
                            ;;
        * )                 usage
                            ;;
    esac
    shift
done

# Controleer of alle vereiste argumenten zijn meegegeven
if [ -z "$CF_API_TOKEN" ] || [ -z "$DOMAIN" ] || [ -z "$IP_ADDRESS" ] || [ -z "$PDNS_API_TOKEN" ] || [ -z "$PDNS_SERVER_URL" ]; then
    usage
fi

# Update en installeer Certbot en de Cloudflare plugin
apt-get update
apt-get install -y certbot python3-certbot-dns-cloudflare curl jq

# Maak credentials bestand aan
mkdir -p /root/.secrets/certbot
echo "dns_cloudflare_api_token = $CF_API_TOKEN" > /root/.secrets/certbot/cloudflare.ini
chmod 600 /root/.secrets/certbot/cloudflare.ini

# Vraag het certificaat aan
certbot certonly \
  --dns-cloudflare \
  --dns-cloudflare-credentials /root/.secrets/certbot/cloudflare.ini \
  -d $DOMAIN \
  -d *.$DOMAIN

# Voeg cronjob toe voor automatische vernieuwing
(crontab -l 2>/dev/null; echo "0 0 * * * /usr/bin/certbot renew --quiet --dns-cloudflare-credentials /root/.secrets/certbot/cloudflare.ini") | crontab -

# Update PowerDNS met nieuw record
PDNS_ZONE=$(echo $DOMAIN | awk -F'.' '{print $(NF-1)"."$NF}')
UPDATE_DATA="{
  \"rrsets\": [
    {
      \"name\": \"$DOMAIN.\",
      \"type\": \"A\",
      \"changetype\": \"REPLACE\",
      \"ttl\": 3600,
      \"records\": [
        {
          \"content\": \"$IP_ADDRESS\",
          \"disabled\": false
        }
      ]
    }
  ]
}"

curl -X PATCH -H "X-API-Key: $PDNS_API_TOKEN" -H "Content-Type: application/json" \
    -d "$UPDATE_DATA" $PDNS_SERVER_URL/api/v1/servers/localhost/zones/$PDNS_ZONE.

echo "Certbot installatie en certificaat aanvraag voltooid."
echo "PowerDNS record bijgewerkt."

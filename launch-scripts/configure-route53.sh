#!/bin/bash -eo pipefail

# configure-route53.sh
# Initializes HOSTED ZONE w/ standard A, CNAME records.
# WARNING! 	this code deletes all zones related to given domain.
# 			only use when setting up for the first time. 

# TRAP stuff START ##########################################################
export RED=`tput setaf 1`
export GREEN=`tput setaf 2`
export YELLOW=`tput setaf 3`
export RESET=`tput sgr0`
function missingarg(){
	echo "${RED}[ERROR] MISSING ARGS${RESET}${0##*/}"
	exit 1
}
function cleanup(){
	echo "${RED}[ERROR]${RESET}${0##*/}:$1"
	echo "Reversing any changes made..."
	delete_all_zones_and_records_for_domain 
  exit 1
}
function success(){
	echo "${GREEN}[SUCCESS]${RESET}${0##*/}"
	exit 0
}
# TRAP stuff END #############################################################

trap '[[ -z $1 || -z $2 ]] && missingarg' EXIT
if [[ -z $1 || -z $2 ]]; then exit 1; fi
trap '[ "$?" -eq 0 ] && success || cleanup $LINENO' EXIT


function delete_all_zones_and_records_for_domain() {
	sh $(dirname $0)/delete-all-zones-and-records.sh $dn
}
function create_hosted_zone_for_domain(){
	echo "Creating a hosted zone for domain"
	created_hosted_zone=$(aws route53 create-hosted-zone \
		--name $dn --caller-reference $(date +%Y-%m-%d:%H:%M:%S)\
		| jq -r '.HostedZone .Id')
}
function prepare_upsert_for_a_and_cname(){
	# Make A and CNAME record sets rqst in JSON
	arec_cname_upsert_rqst=$(sh \
		$(dirname $0)/prepare-upsert-for-a-and-cname.sh \
		$dn $eip_public_ip)	
}
function update_record_set(){
	sh $(dirname $0)/update-record-set.sh $created_hosted_zone $arec_cname_upsert_rqst
}
function get_hosted_zone_nameservers(){
	formatted='';
	ns=$(aws route53 get-hosted-zone \
		--id $created_hosted_zone\
		| jq -r .DelegationSet.NameServers[])
	for i in $ns; do formatted+="{\"Name\":\"$i\"}"; done
	formatted="["$(echo $formatted | sed 's@"}{"@"},{"@g')"]"
	echo $formatted
}
# function get_domain_ns_whois(){
# 	nameservers=$(whois $dn | grep 'Name Server' | head -4 | sed 's@Name Server: @ @g')
# 	formatted="";
# 	for i in $nameservers; do formatted+="{\"Name\":\"$i\"}"; done
# 	formatted="["$(echo $formatted | sed 's@"}{"@"},{"@g')"]"
# 	echo $formatted
# }
function update_route53_domain_nameservers(){
	opid=$(aws --region=us-east-1 \
		route53domains update-domain-nameservers       \
		--domain-name $dn --nameservers $formatted     \
		--output text --query 'OperationId')|| exit $? \
	&& echo $opid   \
	&& until aws \
	 	--region=us-east-1 route53domains get-operation-detail  \
	 	--operation-id $opid --query 'Status' | grep -m 1 "SUCCESSFUL"; do 
	 	sleep 5
	 	echo "Waiting for DNS to update..."
	done
}
function initialize_zone_with_a_and_cname_records(){
	delete_all_zones_and_records_for_domain 
	create_hosted_zone_for_domain
	prepare_upsert_for_a_and_cname
	update_record_set
	get_hosted_zone_nameservers
	update_route53_domain_nameservers
}
dn=$1; eip_public_ip=$2
initialize_zone_with_a_and_cname_records $dn $eip_public_ip

exit 0



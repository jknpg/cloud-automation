#!/bin/bash -eo pipefail

# Delete-all-zones-and-records.sh
# Lists and deletes all zones, while recursively deleting all record-sets for each zone 

# TRAP stuff START ##########################################################
function missingarg(){
	echo "${RED}[ERROR] MISSING ARGS${RESET} ${0##*/}:$1"
	exit 1
}
function err_report(){
	echo "${RED}[ERROR]${RESET} ${0##*/}:$1"
	exit 1
}
function success(){
	echo "${GREEN}[PASS]${RESET}\
	There are no zones associated with domain."
	exit 0
}
# TRAP stuff END ##################################################################

trap '[[ -z $1 ]] && missingarg' EXIT
if [[ -z $1 ]]; then exit 1; fi
trap '[ "$?" -eq 0 ] && success || err_report $LINENO' EXIT

function list_all_zones_for_domain(){
	zone_list="$(aws route53 list-hosted-zones \
		--output text --query 'HostedZones[?Name==`'$1'.`].Id')"
	count=$(echo $zone_list | wc -w)
	if [[ $count -eq 0 ]]; then exit 0; fi
	echo "Found zones for this domain."
}
function delete_all_zones_for_this_domain(){
	local dn=$1; local processes="";
	list_all_zones_for_domain $dn
	echo "Deleting all hosted zones for domain: $dn..."
	for zid in $(echo $zone_list \
		| sed 's/,/ /g' | sed 's'@'/hostedzone/'@' '@'g')
	do
		echo "Deleting hosted zone $zid..."\
		&& delete_all_records_for_zone $zid\
    &&(deletion_id=$(aws route53 delete-hosted-zone \
  	--id $zid --output text --query 'ChangeInfo.Id') \
		&& until [ $(aws route53 get-change --id $deletion_id \
			| jq -r '.ChangeInfo.Status')=="INSYNC" ]; do
		 	echo "Trying..."
			sleep 0.5
		done \
		&&echo "Change id: $deletion_id")\
		&&echo "Deleted zone $zid"\
		& processes="$processes $!"
	done
	for p in $processes; do
	  wait $p || let "result=1"
	  if [ "$result" == "1" ]; then exit 1; fi
	done
}
function 	delete_all_records_for_zone(){
	local zid=$1; 
	echo "Deleting all record sets for zone: $zid..."
	aws route53 list-resource-record-sets \
	--hosted-zone-id $zid | jq -c '.ResourceRecordSets[]' \
	| while read -r rec; do
			read -r name type <<< $(jq -r '.Name,.Type' <<< "$rec")
		  if [ $type != "NS" -a $type != "SOA" ]; then
		  	echo "${YELLOW}Change process entered for $rec..."
		    (change_id=$(aws route53 change-resource-record-sets \
		      --hosted-zone-id $zid --change-batch '{"Changes":
		      [{"Action":"DELETE","ResourceRecordSet":'"$rec"'}]}' \
		      --output text --query 'ChangeInfo.Id')\
				&& echo "${GREEN}Change id: $change_id${RESET}" \
				&& until [ $(aws route53 get-change --id $change_id \
					| jq -r '.ChangeInfo.Status')=="INSYNC" ]; do
				 	echo "Trying..."
				 	sleep 0.5
				done) &
				wait $! || let "result=1"
			  if [ "$result" == "1" ]; then exit 1; fi
	  	fi 
		done
}	
result=""
delete_all_zones_for_this_domain $1
exit 0
#!/bin/bash
read -p "Enter the customer name (eg: without spaces, same name is been used for listen url): " client
read -p "Enter the environment name (eg: staging,live): " env

base_dir="./tyk-api-creation"
tyk_root="/opt/tyk-gateway"

if [[ "$env" == "live" || "$env" == "staging" ]]; then
    echo "Valid input"
else
    echo "Invalid input. Please enter one of the allowed values (live,staging)."
    exit 0
fi


if [[ $env == "live" ]]
then
    clientname=$client
else
    clientname=$client-$env
fi

database=$base_dir/tykapi.db
result=$(sqlite3 "$database" "SELECT EXISTS(SELECT 1 FROM tykapi WHERE clientname = '$clientname');")

if [ "$result" -eq 1 ]; then
    echo "API '$search_text' alreday present."
    exit 1
fi


#read -p "Enter the site  url protocal (eg: http or https): " httptype
httptype="https"
read -p "Enter the site url (eg: eg1.example.com or eg1.staging.example.com ): " baseurl
read -p "Enter the site X-Site-Key (eg: 1111,222): " skey
read -p "Enter the site X-Site-User (eg: 1111,222): " ukey

server_key="*****************************"
server_api_url="http://localhost:8080"
final_results=0
TO="admin@example.com"

if [[ $env == "live" ]]
then
	client_api_url="https://api.example.com"
else
	client_api_url="https://api.staging.example"
fi

app_dir="$tyk_root/apps"
policy_dir="$tyk_root/policies"

app_base_file="$base_dir/app-base.json"
policy_base_file="$base_dir/policy-base.json"

tmp_app_file=$base_dir/tmp/app-$clientname.json
tmp_policy_file=$base_dir/tmp/policy-$clientname.json

sqlid=$(sqlite3 $database "SELECT MAX(id) FROM tykapi;")
id=$(expr $sqlid + 1 )


slug=$clientname-api
api_id=$clientname-api-$id
org_id=$id
listen_path=$clientname




#Create copy of base file
cp $app_base_file $tmp_app_file
cp $policy_base_file $tmp_policy_file



#Replacements in apps file
#Replace app name
sed -i "s/\"name\"\:\ \"clientname\"\,/\"name\"\:\ \"$clientname\"\,/g" $tmp_app_file

#Replace slug
sed -i "s/\"slug\"\:\ \"clientname-api\"\,/\"slug\"\:\ \"$slug\"\,/g" $tmp_app_file

#Replace api_id
sed -i "s/\"api_id\"\:\ \"clientname_id_1\"\,/\"api_id\"\:\ \"$api_id\"\,/g" $tmp_app_file

#Replace org_id
sed -i "s/\"org_id\"\:\ \"orgid\"\,/\"org_id\"\:\ \"$org_id\"\,/g" $tmp_app_file

#Replace X-Site-Key
sed -i "s/\"X-Site-Key\"\:\ \"skey\"\,/\"X-Site-Key\"\:\ \"$skey\"\,/g" $tmp_app_file

#Replace X-User-Key
sed -i "s/\"X-Site-User\"\:\ \"ukey\"/\"X-Site-user\"\:\ \"$ukey\"/g" $tmp_app_file

#Replace listen path
sed -i "s/\"listen_path\"\:\ \"path\"\,/\"listen_path\"\:\ \"\/$clientname\"\,/g" $tmp_app_file

#Replace target_url
sed -i "s/\"target_url\"\:\ \"httptype\:\/\/baseurl\/api\"\,/\"target_url\"\:\ \"$httptype\:\/\/$baseurl\/api\"\,/g" $tmp_app_file


#Replacements in policies file
#Replace POLICY ID
sed -i "s/\"PID\": {/\"POLICYID-$id\": {/g" $tmp_policy_file

#Replace api_id
sed -i "s/\"clientname_id_1\": {/\"$api_id\": {/g" $tmp_policy_file

#Replace api_id
sed -i "s/\"api_id\"\:\ \"clientname_id_1\"\,/\"api_id\"\:\ \"$api_id\"\,/g" $tmp_policy_file

#Replace api_name
sed -i "s/\"api_name\"\:\ \"clientname\"\,/\"api_name\"\:\ \"$clientname\"\,/g" $tmp_policy_file

#Replace name
sed -i "s/\"name\"\:\ \"clientname\"\,/\"name\"\:\ \"$clientname\"\,/g" $tmp_policy_file

#copy files to tyk config directory
mv $tmp_app_file $app_dir/$clientname.json
mv $tmp_policy_file $policy_dir/$clientname.json

#reload tyk
reload_results=$(curl -H "x-tyk-authorization: $server_key" -s $server_api_url/tyk/reload/group | awk -F ':' '{ print $2 }' | sed "s/\"//g" )

if [ $reload_results == "ok,message" ]
then 
    ((final_results+=1))
fi

#create API keys
apikeys=$(curl -s -X POST \
  -H "x-tyk-authorization: $server_key" \
  -H "Content-Type: application/json" \
  -d "{
    \"allowance\": 1000,
    \"rate\": 1000,
    \"per\": 1,
    \"expires\": -1,
    \"quota_max\": -1,
    \"org_id\": \"$org_id\",
    \"quota_renews\": 1449051461,
    \"quota_remaining\": -1,
    \"quota_renewal_rate\": 60,
    \"access_rights\": {
      \"$api_id\": {
        \"api_id\": \"$api_id\",
        \"api_name\": \"$clientname\",
        \"versions\": [\"Default\"]
      }
    },
    \"meta_data\": {}
  }" $server_api_url/tyk/keys/create | awk -F ':' '{ print $2}' | sed "s/\"//g" | sed "s/\,status//g")

if [[ $? -eq 0 ]]
then
    ((final_results+=1))
fi


#store details in DB
sqlite3 $database "insert into tykapi (clientname,slug,api_id,org_id,skey,ukey,listen_path,httptype,baseurl,key) values ('$clientname','$slug','$api_id','$org_id','$skey','$ukey','/$listen_path','$httptype','$baseurl','$apikeys');"

if [[ $? -eq 0 ]]
then
    ((final_results+=1))
fi



#echo $final_results
if [[ $final_results == 3 ]]
then
    curl --silent -o /dev/null --user 'api:**************************************' https://api.mailgun.net/v3/exmaple.com/messages -F from='admin@example.com' -F to=$TO -F subject="API url created" -F text="$(echo -e "Hi, \nThe API url $client_api_url/$listen_path created successfully in the prod API server\n\nAPI key: $apikeys")"
else
    curl --silent -o /dev/null --user 'api:**************************************' https://api.mailgun.net/v3/example/messages -F from='admin@example.com' -F to=$TO -F subject="API url $client_api_url/$listen_path creation failed" -F text="$(echo -e "Hi, \nnThe API url $client_api_url/$listen_path creation failed")"
fi

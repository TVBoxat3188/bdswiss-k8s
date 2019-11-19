#AWS_REGION=eu-west-2 aws-ssm-env --paths=/mt4-trading-api/web/demo
path=$2

case $1 in

        delete)
		if [ "$path" == "" -o "$path" == "/" -o "$path" == "/mt4-trading-api" -o "$path" == "/mt4-trading-api/" ]
			then
				echo "Not aceptable parameter"
				exit 1
		fi
		echo -n "Are you sure that you want to delete all ENV variables under $path?:"
		read answer
		[ "$answer" != "yes" ] && echo "Exiting" &&  exit 0 
                for param in `aws ssm  get-parameters-by-path  --path $path | grep Name | awk '{print$2}' | sed 's/,//g' | sed 's:"::g' `; do aws ssm  delete-parameters --names $param; done
                ;;

        create)
		FILE=$3
		while read LINE; do
			ENV_PARAM=`echo "$LINE" | awk -F ':' '{print$1}'`
			ENV_VALUE=`echo "$LINE" | awk -F "$ENV_PARAM:" '{print$2}'`
			echo $ENV_PARAM $ENV_VALUE
			aws --profile bdswiss ssm put-parameter --overwrite --name $path/$ENV_PARAM  --value $ENV_VALUE --type String
		done < $FILE
                ;;

        *)
                echo "Usage: $0 delete /path/server/
	$0 create /path/server/ file.env"
                exit 1
                ;;
esac
exit 0


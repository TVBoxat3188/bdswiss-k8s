
# Author Alexey Ostrovsky <aostrovsky@rightandabove.com>
# Date: 26-07-2019

EKS_STACK_NUMBER=1
EKS_CLUSTER_NAME="$2-${EKS_STACK_NUMBER}"
REGION=eu-west-2
INTERACTIVE=1
DEBUG=0

[ $DEBUG == 1 ] && set -x

echo $1
case $1 in
create)

eksctl create cluster \
--region $REGION \
--name ${EKS_CLUSTER_NAME} \
--version 1.13 \
--nodegroup-name ${EKS_STACK_NUMBER} \
--node-type t3.small \
--nodes 2 \
--nodes-min 2 \
--nodes-max 6 \
--node-ami auto \
--ssh-access \
--ssh-public-key aws-bdswiss-kube-nodes



echo  "Tiller Setup"
[ $INTERACTIVE == 1 ] && read

kubectl -n kube-system create serviceaccount tiller && \
kubectl create clusterrolebinding tiller   --clusterrole cluster-admin   --serviceaccount=kube-system:tiller && \
helm init --service-account tiller && \
kubectl -n kube-system  rollout status deploy/tiller-deploy 


echo "Prometheus setup"
[ $INTERACTIVE == 1 ] && read

helm install   --name mon   --namespace monitoring   stable/prometheus-operator -f monitoring/prometheus-values.yaml
kubectl get --raw /apis/custom.metrics.k8s.io/v1beta1  
kubectl --namespace monitoring get pods -l "release=mon"
helm install --name prometheus-adapter stable/prometheus-adapter --set prometheus.url="http://mon-prometheus-operator-prometheus.monitoring.svc",prometheus.port="9090" --set rbac.create="true" --namespace kube-system
kubectl -n kube-system rollout status deploy/prometheus-adapter
kubectl get --raw /apis/custom.metrics.k8s.io/v1beta1
kubectl -n monitoring create cm mon-grafana-ingress-controller --from-file=monitoring/grafana-nginx-ingress-dashboard.json
kubectl -n monitoring label cm mon-grafana-ingress-controller grafana_dashboard=nginx_ingress_controller


echo "Metric server setup"
[ $INTERACTIVE == 1 ] && read

rm -rf metrics-server
git clone https://github.com/kubernetes-incubator/metrics-server.git
cd metrics-server
sed -i 's/runAsNonRoot: true/runAsNonRoot: false/g' deploy/1.8+/metrics-server-deployment.yaml
kubectl apply -f deploy/1.8+/
cd ../
rm -rf metrics-server


echo "All kuber logs to AWS setup"
[ $INTERACTIVE == 1 ] && read

#Logs
#Atach required policy to node role
export ROLE_NAME=`aws   --region=$REGION cloudformation describe-stacks --stack-name eksctl-${EKS_CLUSTER_NAME}-nodegroup-${EKS_STACK_NUMBER} | jq -r '.Stacks[].Outputs[] | select(.OutputKey=="InstanceRoleARN") | .OutputValue'  | cut -f2 -d/`
aws  iam  attach-role-policy  --role-name=$ROLE_NAME --policy-arn=arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy

kubectl apply -f logging/cloudwatch-namespace.yaml
kubectl create configmap cluster-info \
--from-literal=cluster.name=${EKS_CLUSTER_NAME} \
--from-literal=logs.region=$REGION -n amazon-cloudwatch

kubectl apply -f logging/fluentd.yml
sleep 10
kubectl get pods -n amazon-cloudwatch


echo "Deploy Node autoscaler"
[ $INTERACTIVE == 1 ] && read

# Deploy Node autoscaler
export NODE_GROUP_NAME=`aws   --region=$REGION cloudformation describe-stack-resources --stack-name eksctl-${EKS_CLUSTER_NAME}-nodegroup-${EKS_STACK_NUMBER}  | jq -r '.StackResources[]  | select(.LogicalResourceId=="NodeGroup") | .PhysicalResourceId'`
aws autoscaling create-or-update-tags --tags ResourceId=$NODE_GROUP_NAME,ResourceType=auto-scaling-group,Key=k8s.io/cluster-autoscaler/enabled,Key=k8s.io/cluster-autoscaler/${EKS_CLUSTER_NAME},PropagateAtLaunch=true
aws iam create-policy --policy-name ClusterAutoScaler-${EKS_CLUSTER_NAME} --policy-document file://clusterautoscaler/ClusterAutoScaler.json
aws  iam  attach-role-policy  --role-name=$ROLE_NAME --policy-arn="arn:aws:iam::`aws sts get-caller-identity|jq -r ".Account"`:policy/ClusterAutoScaler"


sed "s:<YOUR CLUSTER NAME>:${EKS_CLUSTER_NAME}:g" clusterautoscaler/cluster-autoscaler-autodiscover.yaml.template > clusterautoscaler/cluster-autoscaler-autodiscover.yaml

kubectl apply -f clusterautoscaler/cluster-autoscaler-autodiscover.yaml
# You can check logs
#kubectl logs -f deployment/cluster-autoscaler -n kube-system



echo "Deploy ingress controller"
[ $INTERACTIVE == 1 ] && read 

# Deploy ingress controller
# https://kubernetes.github.io/ingress-nginx/deploy/#prerequisite-generic-deployment-command
cd ingress/
openssl genrsa 4096 > my-aws-private.key
openssl req -new -x509 -nodes -sha1 -days 3650 -extensions v3_ca -key my-aws-private.key > my-aws-public.crt
aws iam upload-server-certificate --server-certificate-name selfsigned.bdswiss.com-${EKS_CLUSTER_NAME} --certificate-body file://my-aws-public.crt  --private-key file://my-aws-private.key
kubectl apply -f ingress-mandatory.yaml
kubectl apply -f ingress-service-l7.yaml
kubectl apply -f ingress-patch-configmap-l7.yaml
cd ../

;;

delete)

echo "Making sure you have deleted all LB services from cluster"
LB=`kubectl get svc  --all-namespaces  | awk '{print$5}' | grep -vP "EXTERNAL-IP|none"`
if [ "$LB" != '' ]
	then
		echo "There are still some pods are running in current cluster.
Please first switch context to it. Delete all name spaces. Specialy services which use Loadbalancers.
Then remove cluster.
PLESE BE VERY CAREFULL WITH DELETE OPERATIONS. DOUBLE CHECK THAT YOU ARE WORKING IN RIGHT CONTEXT
"
exit 0
fi
		

export ROLE_NAME=`aws --region=$REGION  cloudformation describe-stacks --stack-name eksctl-${EKS_CLUSTER_NAME}-nodegroup-${EKS_STACK_NUMBER} | jq -r '.Stacks[].Outputs[] | select(.OutputKey=="InstanceRoleARN") | .OutputValue'  | cut -f2 -d/`
aws  iam  detach-role-policy  --role-name=$ROLE_NAME --policy-arn=arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy
aws  iam  detach-role-policy  --role-name=$ROLE_NAME --policy-arn="arn:aws:iam::`aws sts get-caller-identity|jq -r ".Account"`:policy/ClusterAutoScaler"
aws iam delete-policy --policy-arn="arn:aws:iam::`aws sts get-caller-identity|jq -r ".Account"`:policy/ClusterAutoScaler-${EKS_CLUSTER_NAME}"

eksctl delete cluster --region $REGION --name ${EKS_CLUSTER_NAME}

;;

*)
echo "Usage: $0 create CLUSTER-NAME"

;;

esac

# Usefull commands
# Load generator
# kubectl run -i --tty load-generator --image=busybox /bin/sh
# Kick deployment update when secret or config map changed
# kubectl patch deployment mydeployment -p '{"spec":{"template":{"spec":{"containers":[{"name":"mycontainer","env":[{"name":"RESTART_","value":"'$(date +%s)'"}]}]}}}}'
# kubectl port-forward -n monitoring service/mon-grafana 30002:80
# kubectl port-forward -n monitoring service/mon-prometheus-operator-prometheus 9090
# kubectl port-forward -n monitoring service/mon-prometheus-operator-alertmanager  9093
# Update config for alertmanager:  sed "s/ALERTMANAGER_CONFIG/$(cat alertmanager.yaml | base64 -w0)/g" alertmanager-secret-k8s.yaml | kubectl apply -f -
# search for oom killer: filter @message like /(?i)oom_kill/

# App Deploy
#kubectl create secret generic mt4-trading-api-server-prod --from-file=.env
#kubectl apply -f app.yaml 
#kubectl apply -f service.yaml 


# CloudWatch Logs Insights Query
# fields @timestamp, @message, kubernetes.labels.app | filter  kubernetes.labels.app like /mt4-trading-api-server/ | sort @timestamp desc |  stats count(*) by bin(30s)
# aws cloudwatch --region $REGION put-dashboard  --dashboard-name "mt4-trading-api-server Specific Erros" --dashboard-body "$(< log-dashboard.json)"

# Cloudwatch Metric Filter
# { ($.kubernetes.labels.app=mt4-trading-api-server) &&  ($.log = *error*) }
# aws --region $REGION logs put-metric-filter   --log-group-name "/aws/containerinsights/mp4-api-dev-1/application"   --filter-name mt4-trading-api-server-log-error_filter-2   --filter-pattern "{ ($.kubernetes.labels.app=mt4-trading-api-server) &&  ($.log = *error*) }"   --metric-transformations   metricName=mt4-trading-api-server-log-error_count,metricNamespace=BDSwees/MT4/LogMetrics,metricValue=1,defaultValue=0
# aws --region $REGION cloudwatch put-metric-alarm --alarm-name mt4-trading-api-server_ERROR_MONINTOR --alarm-description "Alarm when number of Errors increased/detected" --metric-name mt4-trading-api-server-log-error_count --namespace BDSwees/MT4/LogMetrics --statistic Sum --period 300 --threshold 100 --comparison-operator GreaterThanThreshold  --evaluation-periods 1


# Dashboard setup
#kubectl apply -f https://raw.githubusercontent.com/kubernetes/dashboard/v1.10.1/src/deploy/recommended/kubernetes-dashboard.yaml
#kubectl apply -f https://raw.githubusercontent.com/kubernetes/heapster/master/deploy/kube-config/influxdb/heapster.yaml
#kubectl apply -f https://raw.githubusercontent.com/kubernetes/heapster/master/deploy/kube-config/influxdb/influxdb.yaml
#kubectl apply -f https://raw.githubusercontent.com/kubernetes/heapster/master/deploy/kube-config/rbac/heapster-rbac.yaml
#kubectl create clusterrolebinding dashboard-admin -n default  --clusterrole=cluster-admin  --serviceaccount=default:dashboard
#kubectl create serviceaccount dashboard -n default
#kubectl get secret $(kubectl get serviceaccount dashboard -o jsonpath="{.secrets[0].name}") -o jsonpath="{.data.token}" | base64 --decode
#kubectl proxy --port=8001 --address='0.0.0.0' --disable-filter=true
# URL: http://localhost:8001/api/v1/namespaces/kube-system/services/https:kubernetes-dashboard:/proxy/#!/login



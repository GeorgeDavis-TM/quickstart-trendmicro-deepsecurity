#!/bin/bash
## create listenter on alb and nlb
## createlistener <alb name> <alb fqdn> <dsm console port> <StackName> <firstlb> <region> <alb-https-target-grp> <dsm relay port> <alb-relay-target-grp> <dsm relay port> 
## <nlb name> <nlb fqdn> <nlb-target-grp>
## createlistener     1           2             3               4         5         6               7                    8                   9                    10
##     11          12          13
## create-console-listener-alb-nlb.sh ${DSIALB} ${DSIALBFQDN} ${DSIPGUIPort} ${AWS::StackName} 1 ${AWS::Region} ${DSIALBHTTPSGUIGroupName} ${DSIPRelayPort} ${DSIALBHTTPSRelayGroupName} ${DSIPHeartbeatPort} ${DSINLB} ${DSINLBFQDN} ${DSINLBTCPHeartbeatGroupName}
## create-console-listener-alb-nlb.sh     1           2             3                 4         5       6                   7                      8                    9
##      10              11          12                    13

if [ $5 -eq 1 ]; then
  openssl req -nodes -new -sha256 -newkey rsa:2048 -subj '/CN='DeepSecurityManager'/O=Trend Micro/OU=Deep Security Manager' -keyout /etc/cfn/privatekey -out /etc/cfn/csr;
  openssl x509 -req -days 3650 -in /etc/cfn/csr -signkey /etc/cfn/privatekey -out /etc/cfn/certificatebody;
  aws iam upload-server-certificate --server-certificate-name DeepSecurityElbCertificate-$4 --certificate-body file:///etc/cfn/certificatebody --private-key file:///etc/cfn/privatekey --region $6
fi

loop=1

certid=" "
until [ -n "$certid" -a "$certid" != " " ]
do
  if [ $loop -eq 1 ]; then echo 'checking for cert availability in iam'; else echo 'cert not yet available in iam'; fi
  loop=$((loop+1))
  sleep 10
  certid=$(aws iam get-server-certificate --server-certificate-name DeepSecurityElbCertificate-$4 --query ServerCertificate.ServerCertificateMetadata.Arn --output text --region $6)
done

loadbalancer=" "
loop=1

until [ -n "$loadbalancercert" -a "$loadbalancercert" != " " ]
do
  if [ $loop -eq 1 ]; then echo 'attempting to create listener'; else echo 'listener not yet created, retrying command'; fi
  loop=$((loop+1))
  sleep 10
  
  # HTTPSGUIListener:
  aws elbv2 create-listener \
    --load-balancer-arn $1 \ # LoadBalancer ARN
    --certificates CertificateArn=$certid \ # Certificate ARN
    --region $6 \ # Region
    --protocol HTTPS \
    --port $3 \ # DSIPGUIPort
    --default-actions Type=forward,TargetGroupArn=$7 \ # DSIALBHTTPSGUIGroupName 

# HTTPSGUIListener:
#   Type: AWS::ElasticLoadBalancingV2::Listener
#   Properties:
#     DefaultActions:
#       - Type: forward
#         ForwardConfig:
#           TargetGroups: 
#             - TargetGroupArn: !Ref ALBHTTPSGUIGroup
#     LoadBalancerArn: !Ref DSMALB
#     Port: !Ref DSIPGUIPort
#     Protocol: HTTPS
#     SslPolicy: ELBSecurityPolicy-2016-08

# HTTPSRelayListener:
  aws elbv2 create-listener \
    --load-balancer-arn $1 \ # LoadBalancer ARN
    --certificates CertificateArn=$certid \ # Certificate ARN
    --region $6 \ # Region
    --protocol HTTPS \
    --port $8 \ # DSIPRelayPort
    --default-actions Type=forward,TargetGroupArn=$9 \ # DSIALBHTTPSRelayGroupName 

# HTTPSRelayListener:
#   Type: AWS::ElasticLoadBalancingV2::Listener
#   Properties:
#     DefaultActions:
#       - Type: forward
#         ForwardConfig:
#           TargetGroups: 
#             - TargetGroupArn: !Ref ALBHTTPSRelayGroup
#     LoadBalancerArn: !Ref DSMALB
#     Port: !Ref DSIPRelayPort
#     Protocol: HTTPS
#     SslPolicy: ELBSecurityPolicy-2016-08

# TCPHeartbeatListener:
  aws elbv2 create-listener \
    --load-balancer-arn $11 \ # LoadBalancer ARN
    --certificates CertificateArn=$certid \ # Certificate ARN
    --region $6 \ # Region
    --protocol TCP \
    --port $10 \ # DSIPHeartbeatPort
    --default-actions Type=forward,TargetGroupArn=$13 \ # DSINLBTCPHeartbeatGroupName

# TCPHeartbeatListener:
#   Type: AWS::ElasticLoadBalancingV2::Listener
#   Properties:
#     DefaultActions:
#       - Type: forward
#         ForwardConfig:
#           TargetGroups: 
#             - TargetGroupArn: !Ref ALBHTTPSRelayGroup
#     LoadBalancerArn: !Ref DSMNLB
#     Port: !Ref DSIPHeartbeatPort
#     Protocol: TCP
#     SslPolicy: ELBSecurityPolicy-2016-08  

  loadbalancercert=$(aws elbv2 describe-listeners --load-balancer-arn $1 --region $6 --query 'Listeners[0].Certificates[*].CertificateArn' --output text | grep $certid)
done

echo 'load balancer listener created'

# aws elbv2 create-load-balancer-policy --load-balancer-name $1 --policy-name DSMConsoleStickySessions --policy-type-name LBCookieStickinessPolicyType --region $6 --policy-attributes AttributeName=CookieExpirationPeriod,AttributeValue=600
# aws elbv2 set-load-balancer-policies-of-listener --load-balancer-name $1 --load-balancer-port $3 --policy-names DSMConsoleStickySessions --region $6

## Get current instance id
TOKEN=`curl -X PUT "http://169.254.169.254/latest/api/token" -H "X-aws-ec2-metadata-token-ttl-seconds: 60"`
instanceId=`curl -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/instance-id`

## HTTPSGUIListener
aws elbv2 register-targets --target-group-arn $7 --targets Id=$instanceId,Port=$3

## HTTPSRelayListener
aws elbv2 register-targets --target-group-arn $9 --targets Id=$instanceId,Port=$8

## TCPHeartbeatListener
aws elbv2 register-targets --target-group-arn $13 --targets Id=$instanceId,Port=$10
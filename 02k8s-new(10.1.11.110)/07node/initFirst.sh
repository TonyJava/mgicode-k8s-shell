 kubernetes 服务 IP (一般是 SERVICE_CIDR 中第一个IP)
export CLUSTER_KUBERNETES_SVC_IP="192.169.0.1"
# 集群 DNS 服务 IP (从 SERVICE_CIDR 中预分配)
export CLUSTER_DNS_SVC_IP="192.169.0.2"
# 集群 DNS 域名
export CLUSTER_DNS_DOMAIN="cluster.local."
# 服务网段 (Service CIDR），部署前路由不可达，部署后集群内使用IP:Port可达
export SERVICE_CIDR="192.169.0.0/16"

#VIP
export MASTER_IP=10.1.11.128 
export KUBE_APISERVER="https://${MASTER_IP}:6443"
#export BOOTSTRAP_TOKEN=$(head -c 16 /dev/urandom | od -An -t x | tr -d ' ')
#已经在05中生成到/ssl/token.csv中，这里取出要一样
  BOOTSTRAP_TOKEN= "996616cfee63f7d440bfee6c8998690e"
cd /ssl/

cat  > /ssl/kube-proxy-csr.json <<EOF
{
  "CN": "system:kube-proxy",
  "hosts": [],
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "C": "CN",
      "ST": "BeiJing",
      "L": "BeiJing",
      "O": "k8s",
      "OU": "System"
    }
  ]
}
EOF

cfssl gencert -ca=/ssl/ca.pem -ca-key=/ssl/ca-key.pem -config=/ssl/ca-config.json \
-profile=kubernetes  /ssl/kube-proxy-csr.json | cfssljson -bare kube-proxy
ls kube-proxy*



#kubelet 启动时向 kube-apiserver 发送 TLS bootstrapping 请求，
#需要先将 bootstrap token 文件中的 kubelet-bootstrap 用户赋予 system:node-bootstrapper 角色，
#然后 kubelet 才有权限创建认证请求(certificatesigningrequests)
#--user=kubelet-bootstrap 是文件 /ssl/token.csv 中指定的用户名，
#同时也写入了文件 /ssl/bootstrap.kubeconfig；
kubectl create clusterrolebinding kubelet-bootstrap  \
--clusterrole=system:node-bootstrapper  \
--user=kubelet-bootstrap


#创建 kubelet bootstrapping kubeconfig 文件
rm -rf /ssl/bootstrap.kubeconfig
 # 设置集群参数
kubectl config set-cluster kubernetes \
  --certificate-authority=/ssl/ca.pem \
  --embed-certs=true \
  --server=${KUBE_APISERVER} \
  --kubeconfig=/ssl/bootstrap.kubeconfig
# 设置客户端认证参数
 #--token=${BOOTSTRAP_TOKEN} \
kubectl config set-credentials kubelet-bootstrap \
  --token=996616cfee63f7d440bfee6c8998690e  \
  --kubeconfig=/ssl/bootstrap.kubeconfig
# 设置上下文参数
kubectl config set-context default \
  --cluster=kubernetes \
  --user=kubelet-bootstrap \
  --kubeconfig=/ssl/bootstrap.kubeconfig
# 设置默认上下文
kubectl config use-context default --kubeconfig=/ssl/bootstrap.kubeconfig




#创建 kube-proxy kubeconfig 文件
rm -rf /ssl/kube-proxy.kubeconfig
# 设置集群参数
kubectl config set-cluster kubernetes \
  --certificate-authority=/ssl/ca.pem \
  --embed-certs=true \
  --server=${KUBE_APISERVER} \
  --kubeconfig=/ssl/kube-proxy.kubeconfig
# 设置客户端认证参数
kubectl config set-credentials kube-proxy \
  --client-certificate=/ssl/kube-proxy.pem \
  --client-key=/ssl/kube-proxy-key.pem \
  --embed-certs=true \
  --kubeconfig=/ssl/kube-proxy.kubeconfig
# 设置上下文参数
kubectl config set-context default \
  --cluster=kubernetes \
  --user=kube-proxy \
  --kubeconfig=/ssl/kube-proxy.kubeconfig
# 设置默认上下文
kubectl config use-context default --kubeconfig=/ssl/kube-proxy.kubeconfig




#######################################################
# --hairpin-mode promiscuous-bridge \\
mkdir -p /k8s/
cd /k8s/
cat > /k8s/kubelet.service <<EOF
[Unit]
Description=Kubernetes Kubelet
Documentation=https://github.com/GoogleCloudPlatform/kubernetes
After=docker.service
Requires=docker.service
[Service]
EnvironmentFile=/etc/kubernetes/k8sCliEvn
WorkingDirectory=/var/lib/kubelet
ExecStart=/usr/local/bin/kubelet \\
  --address=\${NODE_ADDRESS} \\
  --hostname-override=\${NODE_ADDRESS} \\
  --pod-infra-container-image=registry.access.redhat.com/rhel7/pod-infrastructure:latest \\
  --experimental-bootstrap-kubeconfig=/etc/kubernetes/bootstrap.kubeconfig \\
  --kubeconfig=/etc/kubernetes/kubelet.kubeconfig \\
  --require-kubeconfig \\
  --cert-dir=/etc/kubernetes/ssl \\
  --cluster_dns=\${CLUSTER_DNS_SVC_IP} \\
  --cluster_domain=\${CLUSTER_DNS_DOMAIN} \\
  --allow-privileged=true \\
  --serialize-image-pulls=false \\
  --logtostderr=true \\
  --network-plugin=cni \\
  --cni-conf-dir=/etc/cni/net.d \\
  --cni-bin-dir=/opt/cni/bin \\
  --v=2
ExecStopPost=/sbin/iptables -A INPUT -s 10.0.0.0/8 -p tcp --dport 4194 -j ACCEPT
ExecStopPost=/sbin/iptables -A INPUT -s 172.16.0.0/12 -p tcp --dport 4194 -j ACCEPT
ExecStopPost=/sbin/iptables -A INPUT -s 192.168.0.0/16 -p tcp --dport 4194 -j ACCEPT
ExecStopPost=/sbin/iptables -A INPUT -p tcp --dport 4194 -j DROP
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
cat  /k8s/kubelet.service
sleep 5

cat > /k8s/kube-proxy.service <<EOF
[Unit]
Description=Kubernetes Kube-Proxy Server
Documentation=https://github.com/GoogleCloudPlatform/kubernetes
After=network.target
[Service]
EnvironmentFile=/etc/kubernetes/k8sCliEvn
WorkingDirectory=/var/lib/kube-proxy
ExecStart=/usr/local/bin/kube-proxy \\
  --bind-address=\${NODE_ADDRESS} \\
  --hostname-override=\${NODE_ADDRESS} \\
  --cluster-cidr=\${SERVICE_CIDR} \\
  --kubeconfig=/etc/kubernetes/kube-proxy.kubeconfig \\
  --logtostderr=true \\
  --proxy-mode=iptables \\
  --v=2
Restart=on-failure
RestartSec=5
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF
cat  /k8s/kube-proxy.service
sleep 5



#3.3 创建安装的shell
cat > /k8s/install-client.sh <<EOF

mkdir -p /working/
cd /working/

chmod 777 /etc/kubernetes/*
wget http://10.1.11.20/k8s/v1.6.2/kubectl
wget http://10.1.11.20/k8s/v1.6.2/kube-proxy
wget http://10.1.11.20/k8s/v1.6.2/kubelet
cp -r /working/{kubectl,kube-proxy,kubelet} /usr/local/bin/
chmod 777 /usr/local/bin/*

 mkdir  -p /var/lib/kubelet/ 
 mkdir -p /var/lib/kube-proxy/


 systemctl daemon-reload
 systemctl enable kubelet
 systemctl start kubelet
 systemctl status kubelet

 sleep 3

 systemctl daemon-reload
 systemctl enable kube-proxy
 systemctl start kube-proxy
 systemctl status kube-proxy

 sleep 3
 #授权加入k8s网络
 kubectl certificate approve \$( kubectl get csr ) 

#显示
kubectl get nodes --show-labels
#journalctl -f
ip addr

EOF
cat /k8s/install-client.sh
sleep 2;

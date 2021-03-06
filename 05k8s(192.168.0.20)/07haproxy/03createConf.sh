# author:pengrk
# email:546711211@qq.com
# qq group:573283836

#http://jarit.iteye.com/blog/990859

NODE_IPS="192.168.0.2"
NODE_NAME="balance01 "

HAPROXY_TCP_PORT="8081"
MASTER01_IP_TCP_PORT="192.168.0.6:8081"
MASTER02_IP_TCP_PORT="192.168.0.7:8081"

HAPROXY_HTTP_PORT="8080"
MASTER01_IP_HTTP_PORT="192.168.0.6:8080"
MASTER02_IP_HTTP_PORT="192.168.0.7:8080"

cd /balanceHaProxy/

for ip in $NODE_IPS ;do
cat > /balanceHaProxy/haproxyConfig${ip##*.} <<EOF
#全局配置
global
    #设置日志
    log 127.0.0.1 local3 info
    chroot /usr/local/haproxy
    #用户与用户组
    #user haproxy
    #group haproxy
    user root
    group root
    #守护进程启动
    daemon
    #最大连接数
    maxconn 4000

#默认配置
defaults
    log global
    mode http
    #option httplog
    option dontlognull
    timeout connect 5000
    timeout client 50000
    timeout server 50000

 ####################################################################
listen http_front
        bind 0.0.0.0:1080           #监听端口  
        stats refresh 30s           #统计页面自动刷新时间  
        stats uri /haproxy?stats            #统计页面url  
        stats realm Haproxy Manager #统计页面密码框上提示文本  
        stats auth admin:admin      #统计页面用户名和密码设置  
        #stats hide-version         #隐藏统计页面上HAProxy的版本信息

 ####################################################################
listen gateway_cluster
  bind 0.0.0.0:${HAPROXY_TCP_PORT}
  mode tcp
  balance roundrobin
  maxconn 20000 
  server master01 ${MASTER01_IP_TCP_PORT} check inter 2000 rise 3 fall 3 weight 30
  server master02 ${MASTER02_IP_TCP_PORT}  check inter 2000 rise 3 fall 3 weight 30

listen gateway_http_cluster
  bind 0.0.0.0:${HAPROXY_HTTP_PORT}
  mode http
  option httpclose
  #后端可以获取客户端的真实ip
  option forwardfor
  balance roundrobin
  maxconn 20000 
  server master01 ${MASTER01_IP_HTTP_PORT} check inter 2000 rise 3 fall 3 weight 30
  server master02 ${MASTER02_IP_HTTP_PORT}  check inter 2000 rise 3 fall 3 weight 30

EOF


    echo -e "\033[32m ###############/balanceKeepAlive/keepAliveConfig${ip##*.} ########### \033[0m"
    cat /balanceHaProxy/haproxyConfig${ip##*.}
    echo -e "\033[32m ###########内容显示完成########### \033[0m"

    sleep 5

done;

 



#   listen   web_proxy *:80
#        appsession JSESSIONID len 52 timeout 3h
#        #插入cookie的方式
#         cookie SRV insert indirect nocache
#        #模式有http tcp health
#        mode http
#        stats enable
#        stats hide-version
#        #查看状态
#         stats uri /haproxy-stats
#        stats refresh 10s
#        monitor-uri /haproxy_test
#        #负载均衡方案:轮调
#         balance roundrobin
#        option httpclose
#        #后端可以获取客户端的真实ip
#        option forwardfor
#        #健康检查
#         option httpchk HEAD /login HTTP/1.0
#        #option  httpchk GET /ping.jsp 
#        #后端真实服务
#         server  webA 192.168.1.226:8081 cookie A check  
#        server  webB 192.168.1.246:8888 cookie B check

#  {{range $key, $pairs := tree "hello/" | byKey}}{{range $serverid, $pair := $pairs}}
#   server app {{.Value}} check inter 2000 fall 3 weight 1 {{end}}{{end}}

# {{ range service "web" }}
# server {{ .Name }}{{ .Address }}:{{ .Port }}{{ end }}

# server web01 10.5.2.45:2492
# server web02 10.2.6.61:2904
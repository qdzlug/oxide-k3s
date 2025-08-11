k3s_cluster:
  children:
    server:
      hosts:
%{ for i in range(server_count) ~}
        ${node_ips[i]}: {}
%{ endfor ~}
    agent:
      hosts:
%{ for i in range(server_count, length(node_ips)) ~}
        ${node_ips[i]}: {}
%{ endfor ~}

  vars:
    ansible_port: 22
    ansible_user: ${ansible_user}
    k3s_version: "${k3s_version}"
    token: "${k3s_token}"
    api_endpoint: "${api_endpoint}"
    extra_server_args: "--tls-san ${internal_ip} --tls-san ${external_ip}"

lb:
  hosts:
    ${nginx_lb_ip}:
      traefik_backend_hosts:
%{ for ip in backend_ips ~}
        - ${ip}
%{ endfor ~}
  vars:
    nginx_lb_ip: "${nginx_lb_ip}"
    nginx_lb_internal_ip: "${nginx_lb_internal_ip}"

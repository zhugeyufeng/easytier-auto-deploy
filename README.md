# easytier-auto-deploy
 This is a shell script for myself to deploy easytier as a system service

 how to use (must run as root):

 global:
 ```
 bash <(curl -sL https://raw.githubusercontent.com/zhugeyufeng/easytier-auto-deploy/main/et-auto-install.sh)
 ```

 in China (pulls the release through a GitHub proxy):
 ```
 bash <(curl -sL https://g.zh.yydy.link:9527/https://raw.githubusercontent.com/zhugeyufeng/easytier-auto-deploy/main/et-auto-install-cn.sh)
 ```

 The service file is generated locally by the script, `resource/*.service` are kept as reference only.

 Update Time:2026-09-06

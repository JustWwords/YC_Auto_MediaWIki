# Авто развёртывание MediaWiki на Yandex Cloud 

## Содержание

### Terraform
Terraform сам создаёт на Yandex Cloud 2+ машины для:
 * Mediaiki 
 * PostgreSQL

Также 1 машину для:
 * Обратный прокси Nginx
 * Zabbix сервер

Так же создаёт inventory.yml для Ansible

### Ansible
Ansible:
#### default_packages
 1. Устанавливаются стандартные пакеты на все машины
 
#### nginx_proxy
 2. Устанавливается nginx
 3. Создаётся nginx.conf
 4. Заменяется nginx.conf 

#### wiki_server
 5. Устанавливаются пакеты
 6. Устанавливается MediaWiki
 7. Настраивается БД PostgreSQL
 8. Запрашивается Конфигурация MediaWiki на сервере

#### wiki_server_LS
 9. На все машины с wiki добавляется LocalSettings.php
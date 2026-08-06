# Инструкция по развертыванию инфраструктуры

Данное руководство описывает пошаговый процесс развертывания веб-ресурса MediaWiki, кластера СУБД PostgreSQL (с репликацией), сервера резервного копирования и системы мониторинга Zabbix 7.4 на базе инфраструктуры Yandex Cloud.

---

## Этап 1. Подготовка, установка ПО

Перед началом работы выполните следующие команды в терминале вашей машины для установки утилит, пакетов и коллекций:

```bash
# 1. Обновление репозиториев
sudo apt update && sudo apt install -y curl wget unzip git python3-pip python3-venv

# 2. Установка Terraform
wget -O- https://apt.releases.hashicorp.com/gpg | gpg --dearmor | sudo tee /usr/share/keyrings/hashicorp-archive-keyring.gpg > /dev/null
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(grep -oP '(?<=UBUNTU_CODENAME=).*' /etc/os-release || lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list
sudo apt update
sudo apt-get install terraform
curl -sSL https://storage.yandexcloud.net/yandexcloud-yc/install.sh | bash

# 3. Установка Ansible через
sudo apt install pipx
pipx install --include-deps ansible

# 4. Установка коллекции Ansible для работы с Zabbix (версия 4.2.0)
ansible-galaxy collection install community.zabbix:4.2.0 --force

# 5. Установка дополнительных коллекций и Python-зависимостей
ansible-galaxy collection install ansible.posix community.postgresql
python3 -m pip install --user psycopg2-binary
```
Подробнее о настройке Terraform при работе с Yandex.Colud можно найти на [yandex.cloud](https://yandex.cloud/ru/docs/terraform/quickstart#configure-provider)

---

## Этап 2. Подготовка инфраструктуры

1. **Создание ресурсов**: Запустите Terraform для развертывания виртуальных машин в облаке:
   * `vm_1` — Обратный прокси Nginx + Zabbix сервер.
   * `vm_2`, `vm_3`, `vm_4` — Серверы приложений MediaWiki и баз данных PostgreSQL.
   
  В файле `terraform.tfvars` можно изменить характеристики создаваемых машин, добавить новые машины, убрать лишние. Подроднее на 
  [yandex.cloud](https://yandex.cloud/ru/docs/tutorials/infrastructure-management/terraform-modules#configure-terraform) и 
  [yandex.cloud](https://yandex.cloud/en/docs/compute/tf-ref)
  
2. **Запуск первичного плейбука**: Выполните Ansible-плейбук для установки базовых пакетов и настройки конфигураций (Nginx Proxy, базовые пакеты СУБД и MediaWiki):
   ```bash
   ansible-playbook playbook.yml -i inventory.yml
   ```

---

## Этап 3. Первоначальный запуск и настройка MediaWiki через браузер

1. Откройте в браузере IP-адрес вашего прокси-сервера (`vm_1`). Вы будете автоматически перенаправлены на страницу первичной веб-установки движка MediaWiki.
2. Пройдите шаги инсталлятора, указав параметры подключения к СУБД PostgreSQL, настроенные на предыдущем шаге через Ansible:
   * **Хост базы данных**
   * **Имя базы данных**: `my_wiki`
   * **Пользователь БД**: `wikiuser`
   * **Пароль**: `pass123`
3. По завершении установки браузер предложит скачать готовый конфигурационный файл **`LocalSettings.php`**. Скачайте его на свою управляющую машину.

### Изменение `LocalSettings.php`:
Перед загрузкой файла обратно на сервер, откройте его в текстовом редакторе, найдите переменную `$wgServer` и измениете в ней внешний IP-адрес вашего прокси-сервера (`vm_1`):
```php
$wgServer = "http://IP_vm_1";
```

4. **Завершение развертывания MediaWiki**:
   
Если выполнение ansible не прервалось и ждёт ввода пути к LocalSetting.php, введите путь к файлу или оставьте пустым, чтобы выбрать стандартную директорию (`~/Загрузки/LocalSettings.php`).
Если выполнение прервалось, можете запустить копирование через команду:
   ```bash
   ansible-playbook playbook.yml --tags "wiki_server_LS"
   ```

---

## Этап 4. Развертывание мониторинга Zabbix

Процесс продолжится автомтически, если не прервался.
Запустить оставшуюся часть автоматизации Ansible для развертывания сервера Zabbix на `vm_1` можно через следующую команду:
```bash
ansible-playbook playbook.yml --tags "zabbix_server,zabbix_host,backup_scripts"
```

---

## Этап 5. Первоначальная веб-настройка Zabbix-интерфейса

1. Перейдите в браузере по адресу: `http://IP_vm_1:8080`.
2. **Check of pre-requisites**: Проверьте, что все системные параметры PHP находятся в состоянии **OK**. Нажмите **Next step**.
3. **Configure DB connection**: Заполните параметры подключения к локальной базе данных, созданной через Ansible:
   * **Database type**: `PostgreSQL`
   * **Database host**: `localhost`
   * **Database port**: `0` (по умолчанию)
   * **Database name**: `zabbix`
   * **Database schema**: `[Оставьте пустым]`
   * **User**: `zabbix`
   * **Password**: `pass123` (или тот, что в плейбуке)
4. Завершите инсталляцию.
5. **Авторизация**: Войдите в панель управления, используя стандартные учетные данные Zabbix:
   * **Username**: `Admin`
   * **Password**: `zabbix`

---

## Этап 6. Настройка мониторинга HTTP-сервисов в веб-интерфейсе

Поскольку мониторинг доступности HTTP-сервисов реализуется без добавления новых хостов в систему, все метрики кодов ответа и времени загрузки привязываются непосредственно к штатному хосту `Zabbix server`.

### 1. Добавление Веб-сценариев (Web Scenarios)
1. В левом навигационном меню перейдите в раздел **Data collection** -> **Hosts**.
2. В строке с именем **Zabbix server** кликните на ссылку **Web** (или выберите вкладку *Web scenarios*).
3. В правом верхнем углу нажмите кнопку **Create web scenario**.
4. На вкладке **Scenario** настройте общие параметры:
   * **Name**: Имя сценария (например, `VM 3`).
   * **Update interval**: Время обновления (по умолчанию, `1m`).
5. Перейдите на вкладку **Steps** и нажмите **Add** для создания шага проверки:
   * **Name**: Имя шага (например, `Test`).
   * **URL**: Введите полный путь к индексной странице проверяемой ВМ, например:
     `http://[IP_vm_3]/mediawiki/mediawiki-1.46.0/index.php/Заглавная_страница`.
   * Нажмите **Add** для сохранения шага, затем **Add** для сохранения всего сценария.
6. Повторите процедуру создания веб-сценария для каждой машины из группы `wiki` (`vm_2`, `vm_3`, `vm_4`).

### 2. Создание Триггеров
Чтобы Zabbix фиксировал события падения веб-сервисов на главном дашборде, необходимо привязать триггеры к созданным веб-сценариям.

1. Перейдите в раздел **Data collection** -> **Hosts** -> Нажмите на **Triggers** у хоста **Zabbix server**.
2. В верхнем правом углу нажмите **Create trigger**.
3. В открывшемся окне конфигурации **New trigger** заполните параметры аварийного события:
   * **Name**: Понятное имя инцидента, например: `VM_3 MediaWiki is down`.
   * **Event name**: Дублирует имя или содержит детали, например: `VM_3 MediaWiki is down`.
   * **Severity**: Выберите уровень важности (Например, `Warning`).
   * **Expression**:  Нажмите *Add* и сформируйте выражение через конфигуратор.
     *Пример выражения для фиксации сбоя веб-сценария:*
     ```ini
     last(/Zabbix server/web.test.fail[VM 3])<>0
     ```
     *(Функция возвращает номер шага, на котором произошел сбой. Если значение не равно 0 — фиксируется авария).*
4. Убедитесь, что чекбокс **Enabled** активен, и нажмите кнопку **Add** внизу формы для активации триггера. При смене статус-кода со стороны целевого сервера приложений на аварийный, событие мгновенно отобразится в разделе *Monitoring -> Problems*.

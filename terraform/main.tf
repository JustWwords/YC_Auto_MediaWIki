resource "yandex_compute_disk" "boot-disk" {
  for_each = var.virtual_machines
  name     = each.value["disk_name"]
  type     = "network-hdd"
  zone     = "ru-central1-a"
  size     = each.value["disk"]
  image_id = each.value["template"]
}

resource "yandex_vpc_network" "network-1" {
  name = "network1"
}

resource "yandex_vpc_subnet" "subnet-1" {
name = "subnet1"
zone = "ru-central1-a"
network_id = yandex_vpc_network.network-1.id
v4_cidr_blocks = ["192.168.10.0/24"]
}

resource "yandex_compute_instance" "virtual_machine" {
  for_each        = var.virtual_machines
  name = each.value["vm_name"]

  resources {
    cores  = each.value["vm_cpu"]
    memory = each.value["ram"]
  }

  boot_disk {
    disk_id = yandex_compute_disk.boot-disk[each.key].id
  }

  network_interface {
    subnet_id = yandex_vpc_subnet.subnet-1.id
    nat       = true
  }

  metadata = {
    ssh-keys = "user:${file("~/.ssh/id_ed25519.pub")}"
  } 
 
}

#Можно и лучше, сделать циклом, но как смог
resource "local_file" "ansible_inventory" {
  content = templatefile("${path.module}/inventory.tftpl", {
    vm_1_ip = yandex_compute_instance.virtual_machine["vm-1"].network_interface.0.nat_ip_address
    vm_2_ip = yandex_compute_instance.virtual_machine["vm-2"].network_interface.0.nat_ip_address
    vm_3_ip = yandex_compute_instance.virtual_machine["vm-3"].network_interface.0.nat_ip_address
  })

  filename = "/home/user/Projects/YC Vm/ansible/inventory.yml"
}

resource "ansible_playbook" "nginx_deployment" {
  playbook       = "/home/user/Projects/YC Vm/ansible/playbook.yml"
  name           = "localhost" 

  depends_on = [local_file.ansible_inventory]
}

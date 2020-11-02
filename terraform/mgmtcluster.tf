# - ssh keypair -
resource "openstack_compute_keypair_v2" "keypair" {
  name = "${var.prefix}-keypair"
}

# - management cluster -
resource "openstack_networking_floatingip_v2" "mgmtcluster_floatingip" {
  pool       = var.external
  depends_on = [openstack_networking_router_interface_v2.router_interface]
}
resource "openstack_networking_port_v2" "mgmtcluster_port" {
  network_id = openstack_networking_network_v2.network_mgmt.id
  security_group_ids = [
    openstack_compute_secgroup_v2.security_group_mgmt.id,
  ]
  fixed_ip {
    subnet_id  = openstack_networking_subnet_v2.subnet_mgmt.id
  }
}
resource "openstack_networking_floatingip_associate_v2" "mgmtcluster_floatingip_association" {
  floating_ip = openstack_networking_floatingip_v2.mgmtcluster_floatingip.address
  port_id     = openstack_networking_port_v2.mgmtcluster_port.id
}

resource "openstack_compute_instance_v2" "mgmtcluster_server" {
  name              = "${var.prefix}-mgmtcluster"
  image_name        = var.image
  flavor_name       = var.flavor
  availability_zone = var.availability_zone
  key_pair          = openstack_compute_keypair_v2.keypair.name

  network { port = openstack_networking_port_v2.mgmtcluster_port.id }

  user_data = <<-EOF
#cloud-config
package_update: true
package_upgrade: true
power_state:
  mode: reboot
  condition: True
runcmd:
  - curl -sfL https://get.k3s.io | K3S_TOKEN=${random_string.k3s_token.result} INSTALL_K3S_EXEC="server --write-kubeconfig-mode 644 --disable servicelb,traefik,local-storage" sh -
final_message: "The system is finally up, after $UPTIME seconds"
EOF

  connection {
    host        = openstack_networking_floatingip_v2.mgmtcluster_floatingip.address
    private_key = openstack_compute_keypair_v2.keypair.private_key
    user        = var.ssh_username
  }

  provisioner "file" {
    content     = openstack_compute_keypair_v2.keypair.private_key
    destination = "/home/${var.ssh_username}/.ssh/id_rsa"
  }

  provisioner "file" {
    source      = "files/bootstrap.sh"
    destination = "/home/${var.ssh_username}/bootstrap.sh"
  }

  provisioner "local-exec" {
    command = "sleep 120"
  }

  provisioner "remote-exec" {
    inline = [
      "chmod 0600 /home/${var.ssh_username}/.ssh/id_rsa",
      "bash /home/${var.ssh_username}/bootstrap.sh"
    ]
  }
}

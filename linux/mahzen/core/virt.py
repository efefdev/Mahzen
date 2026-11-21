"""Sanal makine ve sanal makine ağı (NAT) algılama.

Telefonda Göster, bilgisayarın yerel ağ adresinde dinler. Linux bir sanal makinede NAT ağıyla çalışıyorsa bu
adres ana bilgisayarın içindeki özel bir ağdadır ve Wi-Fi'deki telefon ona ulaşamaz. Bu modül o durumu tahmin eder.
"""

from __future__ import annotations

import ipaddress
import subprocess

# Sanal makine programlarının varsayılan NAT / paylaşımlı ağları.
VM_NAT_NETWORKS = [ipaddress.ip_network(n) for n in (
    "10.0.2.0/24",       # VirtualBox NAT, QEMU kullanıcı ağı
    "192.168.64.0/24",   # UTM / Apple Virtualization paylaşımlı ağ (macOS)
    "192.168.65.0/24",   # Apple Virtualization paylaşımlı ağın ikinci aralığı
    "192.168.122.0/24",  # libvirt / virt-manager varsayılan ağı
    "192.168.56.0/24",   # VirtualBox yalnızca-ana-bilgisayar ağı
    "10.211.55.0/24",    # Parallels paylaşımlı ağ
    "10.37.129.0/24",    # Parallels yalnızca-ana-bilgisayar ağı
)]
# WSL2'nin NAT ağı bu aralıktan rastgele bir alt ağ seçer.
WSL_NAT_NETWORK = ipaddress.ip_network("172.16.0.0/12")

_VM_PRODUCTS = ("qemu", "kvm", "vmware", "virtualbox", "parallels", "virtual", "hyper-v", "bochs", "apple virtual")


def in_virtual_machine() -> bool:
    """Sanal makinede mi çalışıyoruz? (UTM/QEMU, VMware, VirtualBox, Parallels, Hyper-V, Apple Virtualization)"""
    try:
        return subprocess.run(["systemd-detect-virt", "--vm", "--quiet"], timeout=3).returncode == 0
    except (OSError, subprocess.SubprocessError):
        pass
    try:
        with open("/sys/class/dmi/id/product_name", encoding="utf-8", errors="ignore") as f:
            product = f.read().lower()
        return any(k in product for k in _VM_PRODUCTS)
    except OSError:
        return False


def in_wsl() -> bool:
    """Windows'un Linux alt sistemi (WSL) içinde mi çalışıyoruz?"""
    try:
        with open("/proc/sys/kernel/osrelease", encoding="utf-8", errors="ignore") as f:
            return "microsoft" in f.read().lower()
    except OSError:
        return False


def unreachable_from_phone(address: str, vm: bool, wsl: bool) -> bool:
    """`address`, bir sanal makinenin NAT ağında ve telefondan büyük olasılıkla ulaşılamaz mı?
    Gerçek bir ağda da kullanılabilen aralıklarda yanlış uyarı vermemek için yalnızca sanal makinede bakılır."""
    try:
        ip = ipaddress.ip_address(address)
    except ValueError:
        return False
    if wsl and ip in WSL_NAT_NETWORK:
        return True
    return vm and any(ip in network for network in VM_NAT_NETWORKS)


def phone_network_warning(address: str) -> bool:
    """Bu bilgisayarda, bu adres için Telefonda Göster'de ağ uyarısı gösterilmeli mi?"""
    wsl = in_wsl()
    return unreachable_from_phone(address, in_virtual_machine() or wsl, wsl)

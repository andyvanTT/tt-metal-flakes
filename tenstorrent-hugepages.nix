{ ... }:
{
  boot.kernelParams = [
    "default_hugepagesz=2M"
    "hugepagesz=1G"
    "hugepages=4"
  ];

  services.envfs.enable = true;

  fileSystems."/dev/hugepages-1G" = {
    device = "hugetlbfs";
    fsType = "hugetlbfs";
    options = [ "pagesize=1G" "mode=1777" ];
  };
}

# modules/features/amdgpu.nix
# AMD GPU (RADV/Mesa) with 32-bit support for gaming
{ pkgs, ... }:
{
  hardware.graphics = {
    enable = true;
    enable32Bit = true;
  };
  environment.systemPackages = with pkgs; [
    lact # GPU control/monitoring
  ];
  systemd.services.lactd = {
    description = "AMDGPU Control Daemon";
    wantedBy = [ "multi-user.target" ];
    serviceConfig.ExecStart = "${pkgs.lact}/bin/lact daemon";
  };
}

# release.nix — what this version of Space Elevator is.
#
# A plain attrset with no inputs, so the updater can read it straight
# out of a config's locked copy without evaluating anything else.
#
#   version       Bumped in the release commit. The release workflow
#                 refuses a tag that disagrees with it.
#   nixosRelease  The NixOS release these modules are written for.
#                 Generated configs pin nixpkgs to it, and `update`
#                 moves them when it changes. `nix flake check` fails
#                 if flake.lock's nixpkgs is a different release.
{
  version = "0.4.0";
  nixosRelease = "26.05";
}

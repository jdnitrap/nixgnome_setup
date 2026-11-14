#local-ai.nix
# Local AI: Ollama with the Vulkan backend so the Radeon 840M iGPU does the work.
# Hermes Agent needs at least 64K tokens of context, so the server default is raised.

{ config, pkgs, lib, ... }:

{
  services.ollama = {
    enable = true;
    package = pkgs.ollama-vulkan;
    environmentVariables = {
      OLLAMA_CONTEXT_LENGTH = "65536";
      OLLAMA_KEEP_ALIVE = "30m";
      # Ollama skips integrated GPUs unless told otherwise; the 840M is the only GPU here.
      OLLAMA_IGPU_ENABLE = "1";
    };
  };

  # GPU render node access for John (video is already in user-accounts.nix).
  users.users.John.extraGroups = [ "render" ];
}

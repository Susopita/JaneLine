{ pkgs ? import <nixpkgs> {} }:

pkgs.mkShell {
  # Definimos las herramientas que necesitas en tu entorno
  buildInputs = with pkgs; [
    git
    gnumake
    iverilog    # Este es el paquete que instala iverilog y vvp
    helix
  ];

  # (Opcional) Script que se ejecuta automáticamente al entrar al entorno
  shellHook = ''
    echo "========================================="
    echo "🚀 Entorno de desarrollo temporal listo."
    echo "📦 Herramientas disponibles: make, iverilog, hx (helix)"
    echo "========================================="
  '';
}

# Procesador RISC-V Pipeline (Reorganizado)

Este repositorio contiene la implementación en Verilog de un procesador RISC-V (basado en la arquitectura RV32I del libro *Digital Design and Computer Architecture* de Harris & Harris). El proyecto ha sido reorganizado de manera modular para separar los componentes de diseño, simulación e implementación física.

## Estructura del Proyecto

El proyecto está organizado de la siguiente manera:

*   **`src/`**: Código fuente de diseño (RTL) del procesador.
    *   **`src/riscvsingle.v`**: Top del procesador que conecta el camino de datos y la unidad de control.
    *   **`src/controller/`**: Módulos decodificadores y unidad de control (`controller.v`, `maindec.v`, `aludec.v`).
    *   **`src/datapath/`**: Módulos que componen el camino de datos del procesador (`datapath.v`, `alu.v`, `regfile.v`, `extend.v`).
    *   **`src/common/`**: Componentes genéricos reutilizables (`adder.v`, `flopr.v`, `mux2.v`, `mux3.v`).
*   **`sim/`**: Entorno de simulación y verificación.
    *   **`sim/testbench.v`**: Banco de pruebas (Testbench) principal del sistema.
    *   **`sim/imem.v`**: Modelo de simulación para la memoria de instrucciones.
    *   **`sim/dmem.v`**: Modelo de simulación para la memoria de datos.
    *   **`sim/riscvtest.txt`**: Archivo de texto en formato hexadecimal que contiene las instrucciones del programa de prueba.
*   **`fpga/`**: Archivos específicos para la implementación en placa física real.
    *   **`fpga/top.v`**: Módulo envoltorio (Wrapper) top-level para la síntesis en FPGA.
    *   **`fpga/constraints.xdc`**: Archivo de restricciones físicas para la asignación de pines y configuración de reloj en Vivado.
*   **`Makefile`**: Script de automatización para simplificar la compilación y visualización de ondas.
*   **`shell.nix`**: Configuración del entorno de desarrollo usando Nix.

---

## Cómo Ejecutar la Simulación

### 1. Entrar al entorno de Nix
Si usas Nix, puedes entrar a una terminal con todas las herramientas necesarias instaladas (`iverilog`, `vvp`, `gtkwave`, `make`):
```bash
nix-shell
```

### 2. Comandos del Makefile
Desde la raíz del proyecto, tienes disponibles las siguientes tareas automatizadas:

*   **Compilar y simular:**
    ```bash
    make
    # o bien
    make run
    ```
    Esto creará el ejecutable de simulación en `build/sim.out`, ejecutará la prueba cargando el programa `sim/riscvtest.txt` en la memoria de instrucciones virtual, e imprimirá en pantalla si la simulación ha tenido éxito.

*   **Ver Ondas (GTKWave):**
    ```bash
    make wave
    ```
    Compila y ejecuta la simulación (si no se ha hecho ya), y abre de forma interactiva la herramienta GTKWave cargando el archivo de trazas `sim/sim.vcd` generado.

*   **Limpiar temporales:**
    ```bash
    make clean
    ```
    Elimina la carpeta `build/` y el archivo `sim/sim.vcd` para dejar limpio el repositorio.

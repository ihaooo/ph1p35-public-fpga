# Simulation

Public self-checking test benches are in this directory and `tests/`.

Run all ModelSim tests from the repository root:

```powershell
powershell -ExecutionPolicy Bypass -File sim/modelsim/run_all.ps1
```

If ModelSim is unavailable, run the same public tests with Icarus Verilog:

```powershell
powershell -ExecutionPolicy Bypass -File sim/iverilog/run_all.ps1
```

The test suite excludes models, MCU firmware, stain detection RTL and private
top-level integration.


# Low-Cost High-Frequency Trading System with FPGA HLS

## Team

- **Students:** Pedro F. Leao, Lucas P. Flores
- **Advisor:** Carlos Raimundo Erig Lima
- **Project Start:** April 2025

## Overview

Modern financial markets require ultra-low-latency trading systems, where microseconds can materially impact performance. Traditional software-based high-frequency trading (HFT) systems are constrained by sequential CPU execution, operating system overhead, and limited parallelism.

This project proposes a **low-cost FPGA-based HFT platform** using **MATLAB HDL Coder** targeting the **Intel Cyclone V DE10-Nano**. The goal is to evaluate whether hardware-native parallelism can provide deterministic low latency and strong throughput compared with software-only approaches.

## Problem Statement

Conventional HFT implementations face several limitations:

- High latency due to sequential CPU processing
- Non-deterministic overhead from operating systems
- Parallelism limits from von Neumann architectures
- High cost of specialized commercial FPGA solutions

These limitations motivate an alternative architecture based on FPGA parallelism and timing determinism, combined with modern high-level synthesis (HLS) tools that lower development complexity.

## Objectives

The main objective is to design and validate an automated FPGA HFT system using MATLAB-to-HDL code generation.

### Specific Goals

- Implement an automated hardware-parallel trading pipeline on DE10-Nano
- Convert MATLAB algorithms into optimized HDL with HDL Coder
- Build a modular architecture including:
  - Financial protocol handling (FIX/FAST study and simplified integration)
  - Order book processing
  - Trading decision engine
- Benchmark performance against software implementations and reported literature results

## Related Work

- **Boutros et al. (2017)**: FPGA-based HFT using HLS, showing significant latency reduction versus software-only systems.
- **Leber et al. (2011)**: FPGA acceleration for HFT with sub-microsecond latency in critical pipeline stages.

These studies support the feasibility of FPGA acceleration for market data processing and order execution logic.

## Methodology

The project is structured in four phases:

1. **Literature Review**

   - Study FPGA-HFT systems and required financial protocols (FIX, FAST)

2. **Environment and Platform Setup**

   - Configure MATLAB HDL Coder toolchain
   - Analyze Intel Cyclone V DE10-Nano capabilities and constraints

3. **System Development**

   - Market data feed simulator via Ethernet
   - Simplified hardware-optimized order book processor
   - Trading decision engine
   - Latency/throughput analysis module

4. **Validation and Comparison**
   - Stress and functional testing
   - Performance comparison with software baselines and literature references

## Proposed Architecture

The initial architecture is modular and pipeline-oriented:

1. **Market Data Input Module**
2. **Protocol Parser / Message Normalization**
3. **Order Book Update Engine**
4. **Strategy Decision Engine**
5. **Order Output / Execution Interface**
6. **Metrics and Instrumentation Module**

This structure allows independent optimization and synthesis of critical path components.

## Evaluation Plan

Evaluation is based on three dimensions: correctness, latency determinism, and throughput scalability.

### Test Procedures

- Simulated market feeds with varying message rates
- Order book integrity validation under continuous updates
- Throughput stress tests for maximum sustainable rate

### Core Metrics

- End-to-end latency (message reception to order decision/output)
- Market message throughput
- FPGA resource utilization (LUTs, registers, BRAM)
- Jitter of internal FPGA processing latency

## Expected Results

- Functional FPGA HFT prototype with hardware-native parallelism
- Demonstration of MATLAB HDL Coder feasibility for critical financial workloads
- Comparative latency/throughput analysis across implementation approaches
- Cost-benefit assessment of low-cost FPGA platforms for HFT research and education

## Feasibility and Constraints

- **Budget:** low, based on DE10-Nano and academic MATLAB licenses
- **Infrastructure:** development workstation + FPGA board
- **Main risks:** timing closure complexity and limited low-cost FPGA resources
- **Ethics:** not applicable for real trading impact, since only simulated market data is used

## Expected Impact

- **Technological:** practical evidence of modern HLS use in latency-critical finance
- **Educational:** support for teaching embedded systems and high-performance finance
- **Economic:** lower-cost path for HFT prototyping
- **Scientific:** insights into hardware parallelism for real-time market data processing

## Deliverables

For the first stage (TCC1), expected deliverables include:

- Consolidated literature review on HFT and FPGA systems
- Full technical specification of the proposed architecture
- Functional prototype of network and order book base modules
- Technical feasibility report for the selected platform

## Repository Structure

Current top-level folders:

- `matlab/` MATLAB models and HDL Coder assets
- `vhdl/` generated/handwritten HDL modules and integration files
- `c/` software baseline, utilities, and comparison tooling

## References

1. Andrew Boutros, Brett Grady, Mustafa Abbas, and Paul Chow. _Build Fast, Trade Fast: FPGA-Based High-Frequency Trading Using High-Level Synthesis._ 2017 International Conference on ReConFigurable Computing and FPGAs (ReConFig), Cancun, Mexico, 2017.
2. Christian Leber, Benjamin Geib, and Heiner Litz. _High Frequency Trading Acceleration Using FPGAs._ 2011 21st International Conference on Field Programmable Logic and Applications, Chania, Greece, 2011.

Embedded robot guidance system (bare-metal HCS12 firmware)

A bare-metal embedded system developed in HCS12 assembly for a robot guidance application, integrating sensor input, real-time control logic, and motor actuation without an operating system.

Features
- bare-metal firmware implementation (no OS)
- real-time sensor acquisition using on-chip ADC
- memory-mapped I/O for hardware interfacing
- motor control using output compare timers and GPIO
- polling-based control logic for stable operation
- low-level debugging using register and memory inspection

Technologies
- HCS12 assembly
- embedded systems programming
- memory-mapped I/O
- ADC interfacing
- timers and GPIO
- real-time control systems

System overview
The system reads sensor inputs through the ADC, processes the data using control logic, and drives motors through GPIO and timers to guide robot movement.

What I implemented
- developed firmware in HCS12 assembly for real-time robot control
- interfaced optical sensors via ADC for continuous signal acquisition
- implemented motor control using output compare timers and GPIO signals
- designed polling-based control logic for reliable sensor reading and movement
- debugged system behavior using register-level inspection and hardware indicators

What I learned
- bare-metal embedded programming without an operating system
- interfacing hardware using memory-mapped I/O
- real-time system design and timing considerations
- debugging low-level embedded systems
- integrating sensors, control logic, and actuators into a complete system

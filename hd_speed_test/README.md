Disk/Partition Speed Benchmark Utility
-------------------------------------------------------------------
Features
  - Shows a concise disk overview (device/model/rotation/type)
  - Shows full device/partition table with mountpoints
  - Lets you select a mounted partition to test (safe: tests via a temp file)
  - Runs multiple write/read tests (dd) using different file sizes
  - Uses GNU time if available (more precise); falls back to shell builtin time
  - Handles permissions: tries normal write, then sudo if needed
  - Appends results to a CSV log in the current working directory by default
  - Can render a PNG comparison graph using gnuplot (-p)
  - Can render an ASCII bar chart inside the terminal (-t)
  - Can ask to apt-install missing tools (time, gnuplot), or auto-install with -y

Notes
-------------------------------------------------------------------
  - This script benchmarks filesystem performance for a selected mounted partition.
  - It DOES NOT overwrite raw devices; it creates and deletes a temporary test file.
  - Results are appended to the log file; they are never overwritten.
  - Locale is forced to C to ensure decimal dot in numbers (CSV-friendly).
-------------------------------------------------------------------
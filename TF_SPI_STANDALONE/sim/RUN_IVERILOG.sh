#!/bin/sh
set -eu
cd "$(dirname "$0")"
iverilog -g2012 -s sd_spi_byte_tb -o /tmp/sd_spi_byte_tb.vvp ../rtl/sd_spi_byte.v sd_spi_byte_tb.v
vvp /tmp/sd_spi_byte_tb.vvp

OUTPUT_ARCH("riscv")
ENTRY(_start)

SECTIONS
{
  . = 0x00010000;
  .text.init : { *(.text.init) }

  . = 0x00011000;
  .tohost :   { *(.tohost) }
  .data :     { *(.data) }
  .bss :      { *(.bss) }
  _end = .;
}

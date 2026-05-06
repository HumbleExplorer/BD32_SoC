/*
 * address  description         comment
 * ------------------------------------------------------------------
 * 0x0      mode register       0=push-pull
 *                              1=open-drain
 * 0x4      direction register  0=input
 *                              1=output
 * 0x8      output register     mode-register=0? 0=drive pad low
 *                                               1=drive pad high
 *                              mode-register=1? 0=drive pad low
 *                                               1=open-drain
 * 0xc      input register      returns data at pad
 * 0x10     trigger type        0=level
 *                              1=edge
 * 0x14     trigger level/edge0 trigger-type=0? 0=no trigger when low
 *                                              1=trigger when low
 *                              trigger-type=1? 0=no trigger on falling edge
 *                                              1=trigger on falling edge
 * 0x18     trigger level/edge1 trigger-type=0? 0=no trigger when high
 *                                              1=trigger when high
 *                              trigger-type=1? 0=no trigger on rising edge
 *                                              1=trigger on rising edge
 * 0x1c     trigger status      0=no trigger detected/irq pending
                                1=trigger detected/irq pending
 * 0x20     irq enable          0=disable irq generation
 *                              1=enable irq generation
 */
`include "../SoC_Config.sv"
`timescale 1ns / 1ps
module apb_gpio #(
    parameter ADDR_WIDTH = `ADDR_WIDTH,
    parameter DATA_WIDTH = `DATA_WIDTH,
    parameter ALIGN_BYTES = `ALIGN_BYTES,
    parameter GPIO_NUM = `GPIO_NUM,
    localparam INPUT_STAGES = 2 
)(
    input   logic                       PCLK,
    input   logic                       PRESETn,
    input   logic   [ADDR_WIDTH-1:0]    PADDR,
    input   logic                       PSEL,
    input   logic                       PENABLE,
    input   logic                       PWRITE,
    input   logic   [ALIGN_BYTES-1:0]   PSTRB,
    input   logic   [DATA_WIDTH-1:0]    PWDATA,
    output  logic   [DATA_WIDTH-1:0]    PRDATA,
    output  logic                       PREADY,
    output  logic                       PSLVERR,
    output  logic                       irq_o,
`ifdef GPIO_SIM
    input   logic   [DATA_WIDTH-1:0]    gpio_i,
    output  logic   [DATA_WIDTH-1:0]    gpio_o,
    output  logic   [DATA_WIDTH-1:0]    gpio_oe
`else
    inout   logic   [GPIO_NUM-1:0]    gpio_io
`endif

);
`ifndef GPIO_SIM
logic   [DATA_WIDTH-1:0]    gpio_i;
logic   [DATA_WIDTH-1:0]    gpio_o;
logic   [DATA_WIDTH-1:0]    gpio_oe;
genvar i;
generate
    for(i=0; i<GPIO_NUM; i++) begin : gpio_tristate
        assign gpio_io[i] = gpio_oe[i] ? gpio_o[i] : 1'bz;
        assign gpio_i[i] = gpio_io[i];
    end
endgenerate

`endif
  //////////////////////////////////////////////////////////////////
  //
  // Constants
  //

typedef enum logic[3:0] {
    MODE      = 4'b0000,
    DIRECTION = 4'b0001,
    OUTPUT    = 4'b0010,
    INPUT     = 4'b0011,
    TR_TYPE   = 4'b0100,
    TR_LVL0   = 4'b0101,
    TR_LVL1   = 4'b0110,
    TR_STAT   = 4'b0111,
    IRQ_ENA   = 4'b1000
} gpio_reg_sel_e;

logic [3:0] reg_sel;
assign reg_sel = PADDR[5:2];

//////////////////////////////////////////////////////////////////
//
// Variables
//

//Control registers
logic   [DATA_WIDTH-1:0]    mode_reg;
logic   [DATA_WIDTH-1:0]    dir_reg;
logic   [DATA_WIDTH-1:0]    out_reg;
logic   [DATA_WIDTH-1:0]    in_reg;
logic   [DATA_WIDTH-1:0]    tr_type_reg;
logic   [DATA_WIDTH-1:0]    tr_lvl0_reg;
logic   [DATA_WIDTH-1:0]    tr_lvl1_reg;
logic   [DATA_WIDTH-1:0]    tr_status_reg;
logic   [DATA_WIDTH-1:0]    irq_ena_reg;

//Trigger registers
logic   [DATA_WIDTH-1:0]    tr_rising_edge_reg;
logic   [DATA_WIDTH-1:0]    tr_falling_edge_reg;
logic   [DATA_WIDTH-1:0]    tr_status;

//Input register, to prevent metastability
logic   [DATA_WIDTH-1:0]    input_regs  [INPUT_STAGES];


//////////////////////////////////////////////////////////////////
//
// Functions
//

//Is this a valid read access?
function automatic bit is_read();
    return PSEL & PENABLE & ~PWRITE;
endfunction : is_read

//Is this a valid write access?
function automatic bit is_write();
    return PSEL & PENABLE & PWRITE;
endfunction : is_write

//Is this a valid write to address 0x...?
//Take 'address' as an argument
function automatic bit is_write_to_addr(input [3:0] reg_addr);
    return is_write() & (gpio_reg_sel_e'(reg_sel) == reg_addr);
endfunction : is_write_to_addr

//What data is written?
//- Handles PSTRB, takes previous register/data value as an argument
function automatic logic [DATA_WIDTH-1:0] get_write_value (input [DATA_WIDTH-1:0] original_val);
    for (int n=0; n < ALIGN_BYTES; n++)
    get_write_value[n*8 +: 8] = PSTRB[n] ? PWDATA[n*8 +: 8] : original_val[n*8 +: 8];
endfunction : get_write_value

//Clear bits on write
//- Handles PSTRB
function automatic logic [DATA_WIDTH-1:0] get_clearonwrite_value (input [DATA_WIDTH-1:0] original_val);
    for (int n=0; n < ALIGN_BYTES; n++)
    get_clearonwrite_value[n*8 +: 8] = PSTRB[n] ? original_val[n*8 +: 8] & ~PWDATA[n*8 +: 8] : original_val[n*8 +: 8];
endfunction : get_clearonwrite_value

/*
* APB accesses
*/
//The core supports zero-wait state accesses on all transfers.
//It is allowed to drive PREADY with a hard wired signal
assign PREADY  = 1'b1; //always_ff ready
assign PSLVERR = 1'b0; //Never an error

/*
* APB Writes
*/
//APB write to Mode register
always_ff @(posedge PCLK,negedge PRESETn)
    if      (!PRESETn               ) mode_reg <= #1 {DATA_WIDTH{1'b0}};
    else if ( is_write_to_addr(MODE)) mode_reg <= #1 get_write_value(mode_reg);

//APB write to Direction register
always_ff @(posedge PCLK,negedge PRESETn)
    if      (!PRESETn                    ) dir_reg <= #1 {DATA_WIDTH{1'b0}};
    else if ( is_write_to_addr(DIRECTION)) dir_reg <= #1 get_write_value(dir_reg);


//APB write to Output register
//treat writes to Input register same
always_ff @(posedge PCLK,negedge PRESETn)
    if      (!PRESETn                   ) out_reg <= #1 {DATA_WIDTH{1'b0}};
    else if ( is_write_to_addr(OUTPUT) ||
              is_write_to_addr(INPUT )  ) out_reg <= #1 get_write_value(out_reg);


//APB write to Trigger Type register
always_ff @(posedge PCLK,negedge PRESETn)
    if      (!PRESETn                  ) tr_type_reg <= #1 {DATA_WIDTH{1'b0}};
    else if ( is_write_to_addr(TR_TYPE)) tr_type_reg <= #1 get_write_value(tr_type_reg);


//APB write to Trigger Level/Edge0 register
always_ff @(posedge PCLK,negedge PRESETn)
    if      (!PRESETn                  ) tr_lvl0_reg <= #1 {DATA_WIDTH{1'b0}};
    else if ( is_write_to_addr(TR_LVL0)) tr_lvl0_reg <= #1 get_write_value(tr_lvl0_reg);


//APB write to Trigger Level/Edge1 register
always_ff @(posedge PCLK,negedge PRESETn)
    if      (!PRESETn                  ) tr_lvl1_reg <= #1 {DATA_WIDTH{1'b0}};
    else if ( is_write_to_addr(TR_LVL1)) tr_lvl1_reg <= #1 get_write_value(tr_lvl1_reg);


//APB write to Trigger Status register
//Writing a '1' clears the status register
always_ff @(posedge PCLK,negedge PRESETn)
    if      (!PRESETn                  ) tr_status_reg <= #1 {DATA_WIDTH{1'b0}};
    else if ( is_write_to_addr(TR_STAT)) tr_status_reg <= #1 get_clearonwrite_value(tr_status_reg) | tr_status;
    else                                 tr_status_reg <= #1 tr_status_reg | tr_status;


//APB write to Interrupt Enable register
always_ff @(posedge PCLK,negedge PRESETn)
    if      (!PRESETn                  ) irq_ena_reg <= #1 {DATA_WIDTH{1'b0}};
    else if ( is_write_to_addr(IRQ_ENA)) irq_ena_reg <= #1 get_write_value(irq_ena_reg);


/*
* APB Reads
*/
always_comb begin
    case (gpio_reg_sel_e'(reg_sel))
        MODE     : PRDATA = mode_reg;
        DIRECTION: PRDATA = dir_reg;
        OUTPUT   : PRDATA = out_reg;
        INPUT    : PRDATA = in_reg;
        TR_TYPE  : PRDATA = tr_type_reg;
        TR_LVL0  : PRDATA = tr_lvl0_reg;
        TR_LVL1  : PRDATA = tr_lvl1_reg;
        TR_STAT  : PRDATA = tr_status_reg;
        IRQ_ENA  : PRDATA = irq_ena_reg;
        default  : PRDATA = {DATA_WIDTH{1'b0}};
    endcase
end

/*
* Internals
*/
always_ff @(posedge PCLK or negedge PRESETn) begin
    if (!PRESETn) begin
        for (int n=0; n<INPUT_STAGES; n++) input_regs[n] <= #1 {DATA_WIDTH{1'b0}};
        in_reg <= #1 {DATA_WIDTH{1'b0}};
    end else begin
        for (int b=0; b<DATA_WIDTH; b++) begin
            input_regs[0][b] <= #1 (gpio_i[b] === 1'bz) ? 1'b0 : gpio_i[b];
        end
        for (int n=1; n<INPUT_STAGES; n++) begin
            input_regs[n] <= #1 input_regs[n-1];
        end
        in_reg <= #1 input_regs[INPUT_STAGES-1];
    end
    
end

// mode
// 0=push-pull    drive out_reg value onto transmitter input
// 1=open-drain   always_ff drive '0' onto transmitter
always_ff @(posedge PCLK or negedge PRESETn)
    if (!PRESETn) begin
        gpio_o <= #1 {DATA_WIDTH{1'b0}};
    end else begin
        for (int n=0; n<DATA_WIDTH; n++)
            gpio_o[n] <= #1 mode_reg[n] ? 1'b0 : out_reg[n];
    end

// direction  mode          out_reg
// 0=input                           disable transmitter-enable (output enable)
// 1=output   0=push-pull            always_ff enable transmitter
//            1=open-drain 1=Hi-Z   disable transmitter
//                         0=low    enable transmitter
always_ff @(posedge PCLK or negedge PRESETn)
    if (!PRESETn) begin
        gpio_oe <= #1 {DATA_WIDTH{1'b0}};
    end else begin
        for (int n=0; n<DATA_WIDTH; n++)
            gpio_oe[n] <= #1 dir_reg[n] & ~(mode_reg[n] ? out_reg[n] : 1'b0);
    end

/*
* Triggers
*/


//detect rising edge
always_ff @(posedge PCLK, negedge PRESETn)
    if (!PRESETn) tr_rising_edge_reg <= #1 {DATA_WIDTH{1'b0}};
    else          tr_rising_edge_reg <= #1 ~in_reg & input_regs[INPUT_STAGES-1];


//detect falling edge
always_ff @(posedge PCLK, negedge PRESETn)
    if (!PRESETn) tr_falling_edge_reg <= #1 {DATA_WIDTH{1'b0}};
    else          tr_falling_edge_reg <= #1 ~input_regs[INPUT_STAGES-1] & in_reg;


//trigger status
always_comb begin
    for (int n=0; n<DATA_WIDTH; n++) begin
        case (tr_type_reg[n])
            0: tr_status[n] = (tr_lvl0_reg[n] & ~in_reg[n]) |
                              (tr_lvl1_reg[n] &  in_reg[n]);
            1: tr_status[n] = (tr_lvl0_reg[n] & tr_falling_edge_reg[n]) |
                              (tr_lvl1_reg[n] & tr_rising_edge_reg [n]);
            default:tr_status[n] = 'h0;
        endcase
    end
end

/*
* Interrupt
*/
always_ff @(posedge PCLK, negedge PRESETn)
    if (!PRESETn) irq_o <= #1 1'b0;
    else          irq_o <= #1 |(irq_ena_reg & tr_status_reg);

endmodule

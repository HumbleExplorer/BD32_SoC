/////////////////////////////////////////////////////////////////////
//   ,------.                    ,--.                ,--.          //
//   |  .--. ' ,---.  ,--,--.    |  |    ,---. ,---. `--' ,---.    //
//   |  '--'.'| .-. |' ,-.  |    |  |   | .-. | .-. |,--.| .--'    //
//   |  |\  \ ' '-' '\ '-'  |    |  '--.' '-' ' '-' ||  |\ `--.    //
//   `--' '--' `---'  `--`--'    `-----' `---' `-   /`--' `---'    //
//                                             `---'               //
//   APB Master BFM                                                //
//                                                                 //
/////////////////////////////////////////////////////////////////////
//                                                                 //
//             Copyright (C) 2020 ROA Logic BV                     //
//             www.roalogic.com                                    //
//                                                                 //
//   This source file may be used and distributed without          //
//   restriction provided that this copyright statement is not     //
//   removed from the file and that any derivative work contains   //
//   the original copyright notice and the associated disclaimer.  //
//                                                                 //
//    This soure file is free software; you can redistribute it    //
//  and/or modify it under the terms of the GNU General Public     //
//  License as published by the Free Software Foundation,          //
//  either version 3 of the License, or (at your option) any later //
//  versions. The current text of the License can be found at:     //
//  http://www.gnu.org/licenses/gpl.html                           //
//                                                                 //
//    This source file is distributed in the hope that it will be  //
//  useful, but WITHOUT ANY WARRANTY; without even the implied     //
//  warranty of MERCHANTABILITY or FITTNESS FOR A PARTICULAR       //
//  PURPOSE. See the GNU General Public License for more details.  //
//                                                                 //
/////////////////////////////////////////////////////////////////////
`timescale 1ns/1ps
`timescale 1ns / 1ps
module apb_master_bfm #(
    parameter PADDR_WIDTH = 32,
    parameter PDATA_WIDTH = 32
)(
    input   logic                       PRESETn,
                                        PCLK,

    //APB Master Interface
    output  logic                       PSEL,
    output  logic                       PENABLE,
    output  logic   [PADDR_WIDTH  -1:0] PADDR,
    output  logic   [PDATA_WIDTH/8-1:0] PSTRB,
    output  logic   [PDATA_WIDTH  -1:0] PWDATA,
    input   logic   [PDATA_WIDTH  -1:0] PRDATA,
    output  logic                       PWRITE,
    input   logic                       PREADY,
    input   logic                       PSLVERR
);

always @(negedge PRESETn) reset();


/////////////////////////////////////////////////////////
//
// Tasks
//
task automatic reset();
    //Reset AHB Bus
    PSEL      = 1'b0;
    PENABLE   = 1'b0;
    PADDR     = 'hx;
    PSTRB     = 'hx;
    PWDATA    = 'hx;
    PWRITE    = 'hx;

    @(posedge PRESETn);
    #1;
endtask


task automatic write (
    input [PADDR_WIDTH  -1:0] address,
    input [PDATA_WIDTH/8-1:0] strb,
    input [PDATA_WIDTH  -1:0] data
);
// Setup
    PSEL    = 1'b1;
    PENABLE = 1'b0;
    PADDR   = address;
    PSTRB   = strb;
    PWDATA  = data;
    PWRITE  = 1'b1;
    @(posedge PCLK);
    #1;
// Enable
    PENABLE = 1'b1;
    @(posedge PCLK);

    while (!PREADY) @(posedge PCLK);// 没到ready就一直等
    #1;
    PSEL    = 1'b0;
    PADDR   = {PADDR_WIDTH{1'bx}};
    PSTRB   = {PDATA_WIDTH/8{1'bx}};
    PWDATA  = {PDATA_WIDTH{1'bx}};
    PWRITE  = 1'bx;
    PENABLE = 1'b0;
endtask


task automatic read (
    input  [PADDR_WIDTH -1:0] address,
    output [PDATA_WIDTH -1:0] data
);
    PSEL    = 1'b1;
    PADDR   = address;
    PSTRB   = {PDATA_WIDTH/8{1'bx}};
    PWDATA  = {PDATA_WIDTH{1'bx}};
    PWRITE  = 1'b0;
    @(posedge PCLK);
    #1;

    PENABLE = 1'b1;
    @(posedge PCLK);

    while (!PREADY) @(posedge PCLK);
    #1;
    data = PRDATA;

    PSEL    = 1'b0;
    PADDR   = {PADDR_WIDTH{1'bx}};
    PWRITE  = 1'bx;
    PENABLE = 1'b0;
endtask

endmodule : apb_master_bfm

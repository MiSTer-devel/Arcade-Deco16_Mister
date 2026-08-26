/* SPDX-FileCopyrightText: 2026 Jose Tejada Gomez
 * SPDX-License-Identifier: GPL-3.0-or-later
 * Date: 29-3-2025 */

module jtcninja_header(
    input            clk,
                     header, prog_we,
    
    output reg       cninja=0,
    output reg       cbust=0,
    output reg       dseal=0,
    output reg       vapor=0,
    output reg       edrndy=0,
    input      [3:0] prog_addr,
    input      [7:0] prog_data
);

always @(posedge clk) begin
    if( header && prog_addr[3:0]==0 && prog_we )
        cninja <= prog_data[0];
    if( header && prog_addr[3:0]==0 && prog_we )
        cbust <= prog_data[1];
    if( header && prog_addr[3:0]==0 && prog_we )
        dseal <= prog_data[2];
    if( header && prog_addr[3:0]==0 && prog_we )
        vapor <= prog_data[3];
    if( header && prog_addr[3:0]==0 && prog_we )
        edrndy <= prog_data[4];
end

endmodule

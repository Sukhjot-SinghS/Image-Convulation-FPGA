`timescale 1ns / 1ps

module hazard_unit (
    input  wire external_stall, // The existing stall signal from pipeline.v
    input  wire alu_busy,       // From Shaurya's rv32m_alu (via execute.v)
    output wire combined_stall  // Goes to IF_ID, PC, and ID_EX registers
);

    // If the external system wants to stall OR the hardware divider is running, freeze the pipeline.
    assign combined_stall = external_stall || alu_busy;

endmodule

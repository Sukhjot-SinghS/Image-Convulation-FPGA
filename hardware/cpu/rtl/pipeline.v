//////////////// Including Stages ////////////////////////////
`include "IF_ID.v"
`include "execute.v"
`include "wb.v"
`include "hazard_unit.v"  
`include "rv32m_alu.v"

//////////////// Including OPCODES ////////////////////////////
// `include "opcode.vh"


 module pipe
#(
	parameter [31:0]         	RESET = 32'h0000_0000
)
(
	input               	clk,
	input                 	reset,
	input               	stall,
	output          	exception,  
	output [31:0] pc_out,

	// Add these two lines to the port list:
    //output [31:0] next_pc_pipe,
    //output [31:0] inst_fetch_pc_pipe,

	// interface of instruction Memory
	input               	inst_mem_is_valid,
	input       	[31: 0] inst_mem_read_data,
	input       	[31: 0] dmem_read_data_temp,
	input               	dmem_write_valid,
	input               	dmem_read_valid,

	output        dmem_re_o,
    output [31:0] dmem_raddr_o,
    output        dmem_we_o,
    output [31:0] dmem_waddr_o,
    output [31:0] dmem_wdata_o,
    output [3:0]  dmem_wstrb_o,


	output        mmio_write_enable,
    output        mmio_read_enable,
    output [31:0] mmio_write_address,
    output [31:0] mmio_write_data,
    input  [31:0] mmio_read_data
);
    
	//Declaring Wires and Registers

	//Data Memory Wires
    
	wire      	[31: 0] dmem_read_data;
	wire              	dmem_write_ready;
	wire              	dmem_read_ready;
	wire      	[31: 0] dmem_write_address;
	wire      	[31: 0] dmem_read_address;
	wire        	[1:0]  dmem_read_offset;
	wire      	[31: 0] dmem_write_data;
	wire      	[ 3: 0] dmem_write_byte;
	wire              	inst_mem_is_ready;
	wire              	dmem_read_valid_checker;
    
	//Instruction Fetch/Decode Stage
    
	reg       	[31: 0] immediate;
	wire               	immediate_sel;
	wire       	[ 4: 0] src1_select;
	wire       	[ 4: 0] src2_select;
	wire       	[ 4: 0] dest_reg_sel;
	wire       	[ 2: 0] alu_operation;
	wire               	arithsubtype;
	wire               	mem_write;
	wire               	mem_to_reg;
	wire               	illegal_inst;
	wire       	[31: 0] execute_immediate;
	wire               	alu;
	wire               	lui;
	wire               	jal;
	wire               	jalr;
	wire               	branch;
	wire               	stall_read;
	wire      	[31: 0] instruction;
	wire      	[31: 0] reg_rdata2 ;
	wire      	[31: 0] reg_rdata1;
	reg       	[31: 0] regs [31: 1];

	//hazard unit 
	wire alu_busy;
	wire combined_stall;

	// PC

	wire        	[31: 0] pc;
	wire        	[31: 0] inst_fetch_pc;
	reg        	[31: 0] fetch_pc ;  

	//Stalls
    
	wire 	wb_stall_first;
	wire 	wb_stall_second;
	wire	wb_stall;   	 
        	 
       	 
	//Execute Stage

    
	wire         	[31: 0] next_pc;
	wire        	[31: 0] write_address;
	wire                 	branch_taken;
	wire                	branch_stall;
	wire        	[31:0] alu_operand1;
	wire        	[31:0] alu_operand2;

	// Write Back
    
	wire                	wb_alu_to_reg;
	wire        	[31: 0] wb_result;
	wire        	[ 2: 0] wb_alu_operation;
	wire                	wb_mem_write;
	wire                	wb_mem_to_reg;
	wire        	[ 4: 0] wb_dest_reg_sel;
	wire                	wb_branch;
	wire                	wb_branch_nxt;
	wire        	[31: 0] wb_write_address;
	wire        	[ 1: 0] wb_read_address;
	wire        	[ 3: 0] wb_write_byte;
	wire        	[31: 0] wb_write_data;
	wire        	[31: 0] wb_read_data;
	wire       	[31: 0] inst_mem_address;

	wire                is_mext;

	wire is_mmio_write = (dmem_write_address >= 32'h8000_0000);
    wire is_mmio_read  = (dmem_read_address  >= 32'h8000_0000);

    // Drive the MMIO output ports!
    assign mmio_write_enable  = wb_mem_write && is_mmio_write;
    assign mmio_read_enable   = mem_to_reg   && is_mmio_read;  // Satish's Read Enable (using load flag)
    assign mmio_write_data    = wb_write_data;
    assign mmio_write_address = dmem_write_address;
    
    // (Notice we deleted 'wire [31:0] mmio_read_data' because it is an input port now!)
//------------------------------------------------------//
assign dmem_write_address       	= wb_write_address; 	// assigning where to write
assign dmem_read_address        	= alu_operand1 + execute_immediate;  // Assigning address to read from the data memory
assign dmem_read_offset = dmem_read_address[1:0];
assign dmem_read_ready          	= mem_to_reg;   // load instruction flag to read from memory
assign dmem_write_ready         	= wb_mem_write && !is_mmio_write; 	// flag to write into the memory
assign dmem_write_data          	= wb_write_data;	// assigning data to write
assign dmem_write_byte          	= wb_write_byte;	// flag for writing the data bytes
assign dmem_read_data = is_mmio_read ? mmio_read_data : dmem_read_data_temp;
assign dmem_read_valid_checker  	= !is_mmio_read;

assign dmem_re_o    = dmem_read_ready;
assign dmem_raddr_o = dmem_read_address;
assign dmem_we_o    = dmem_write_ready;
assign dmem_waddr_o = dmem_write_address;
assign dmem_wdata_o = dmem_write_data;
assign dmem_wstrb_o = dmem_write_byte;


// -----------------------------------------------------//


// instantiating Instruction fetch module -----------------------
IF_ID IF_ID_stage (
	.clk            	(clk),
	.reset          	(reset),
	.stall          	(stall),
	.exception      	(exception),

	// Instruction memory interface
	.inst_mem_is_valid  (inst_mem_is_valid),
	.inst_mem_read_data (inst_mem_read_data),

	// Previously pipe.* signals (now explicit ports)
	.stall_read_i   	(stall_read),
	.inst_fetch_pc  	(inst_fetch_pc),
	.instruction_i  	(instruction),

	// WB-stage signals
	.wb_stall       	(wb_stall),
	.wb_alu_to_reg  	(wb_alu_to_reg),
	.wb_mem_to_reg  	(wb_mem_to_reg),
	.wb_dest_reg_sel	(wb_dest_reg_sel),
	.wb_result      	(wb_result),
	.wb_read_data   	(wb_read_data),
	

	// Instruction memory address offset
	.inst_mem_offset	(inst_mem_address[1:0]),

	// Output wires (write-only)
	.execute_immediate_w (execute_immediate),
	.immediate_sel_w	(immediate_sel),
	.alu_w          	(alu),
	.lui_w          	(lui),
	.jal_w          	(jal),
	.jalr_w         	(jalr),
	.branch_w       	(branch),
	.is_mext_w          (is_mext),
	.mem_write_w    	(mem_write),
	.mem_to_reg_w   	(mem_to_reg),
	.arithsubtype_w 	(arithsubtype),
	.pc_w           	(pc),
	.src1_select_w  	(src1_select),
	.src2_select_w  	(src2_select),
	.dest_reg_sel_w 	(dest_reg_sel),
	.alu_operation_w	(alu_operation),
	.illegal_inst_w 	(illegal_inst),
	.instruction_o  	(instruction) 
);



assign reg_rdata1 =
	(src1_select == 5'd0) ? 0:
	(!wb_stall && wb_alu_to_reg &&
 	(wb_dest_reg_sel == src1_select))
    	? (wb_mem_to_reg ? wb_read_data : wb_result)
    	: regs[src1_select];//todo

assign reg_rdata2 = (src2_select == 5'd0) ? 0:
	(!wb_stall && wb_alu_to_reg &&
 	(wb_dest_reg_sel == src2_select))
    	? (wb_mem_to_reg ? wb_read_data : wb_result)
    	: regs[src2_select];//todo


integer i;
always @(posedge clk or negedge reset) begin
	if (!reset) begin
    	for (i = 1; i < 32; i = i + 1)
        	regs[i] <= 32'b0;
	end
	else if (wb_alu_to_reg && !stall_read && !wb_stall) begin
    	regs[wb_dest_reg_sel] <=
        	wb_mem_to_reg ? wb_read_data : wb_result;//todo
	end
end


//hazard unit changes 


hazard_unit u_hazard (
    .external_stall (stall),
    .alu_busy       (alu_busy),
    .combined_stall (combined_stall)
);


////////////////////////////////////////////////////////////
// Stall register
////////////////////////////////////////////////////////////

assign stall_read = combined_stall || !reset;


// instantiating execute module 
execute execute (
	// -----------------
	// Clock / Reset
	// -----------------
	
	.clk          	(clk),
	.reset        	(reset),

	// -----------------
	// FROM ID/EX
	
    .reg_rdata1        (reg_rdata1),
    .reg_rdata2        (reg_rdata2),
    .execute_imm       (execute_immediate),
    .pc                (pc),
    .fetch_pc          (fetch_pc),
	.is_mext_i          (is_mext),
    .immediate_sel     (immediate_sel),
    .mem_write         (mem_write),
    .jal               (jal),
    .jalr              (jalr),
    .lui               (lui),
    .alu               (alu),
    .branch            (branch),
    .arithsubtype      (arithsubtype),
    .mem_to_reg        (mem_to_reg),
    .stall_read        (stall_read),

    .dest_reg_sel      (dest_reg_sel),
    .alu_op            (alu_operation),
    .dmem_raddr        (write_address[1:0]),//2 bits read strobe 

    // -----------------
	// FROM WB
	// -----------------
	.wb_branch_i  	(wb_branch),
	.wb_branch_nxt_i  (wb_branch_nxt),

	// -----------------
	// EX → PIPE
	// -----------------
	.alu_operand1 	(alu_operand1),
	.alu_operand2 	(alu_operand2),
	.write_address	(write_address),
	.branch_stall 	(branch_stall),
	.next_pc      	(next_pc),
	.branch_taken 	(branch_taken),

	// -----------------
	// EX → WB
	// -----------------
	
	.wb_result         (wb_result),
    .wb_mem_write      (wb_mem_write),
    .wb_alu_to_reg     (wb_alu_to_reg),
    .wb_dest_reg_sel   (wb_dest_reg_sel),
    .wb_branch         (wb_branch),
    .wb_branch_nxt     (wb_branch_nxt),
    .wb_mem_to_reg     (wb_mem_to_reg),
    .wb_read_address   (wb_read_address),
    .mem_alu_operation (wb_alu_operation),


	.alu_busy_o (alu_busy)
);



always @(posedge clk or negedge reset) begin
	if (!reset)
    	fetch_pc <= RESET;
	else if (!stall_read)
    	fetch_pc <= branch_stall
                     	? fetch_pc + 4
                     	: next_pc;
end


// instantiating Writeback module ----------------------------------
wb wb_stage (
   .clk(clk),
   .reset(reset),        
         .stall_read_i       (stall_read),
    .fetch_pc_i         (fetch_pc),
    .wb_branch_i        (wb_branch), 
    .wb_mem_to_reg_i    (wb_mem_to_reg),
    .mem_write_i        (mem_write && !branch_stall),
    .write_address_i    (write_address),
    .alu_operand2_i     (alu_operand2),
    .alu_operation_i    (alu_operation),
    .wb_alu_operation_i (wb_alu_operation),
    .wb_read_address_i  (wb_read_address),
    .dmem_read_data_i   (dmem_read_data),
    .dmem_write_valid_i (dmem_write_valid),
        // Outputs
		.inst_mem_address_o (inst_mem_address),
    .inst_mem_is_ready_o(inst_mem_is_ready),
    .wb_stall_o         (wb_stall),
    .wb_write_address_o (wb_write_address),
    .wb_write_data_o    (wb_write_data),
    .wb_write_byte_o    (wb_write_byte),
    .wb_read_data_o     (wb_read_data),
    .inst_fetch_pc_o    (inst_fetch_pc),
    .wb_stall_first_o   (wb_stall_first),
    .wb_stall_second_o  (wb_stall_second)
);

assign pc_out = fetch_pc;

// At the bottom of pipeline.v, connect them to the internal wires:
//assign next_pc_pipe = next_pc;
//assign inst_fetch_pc_pipe = inst_fetch_pc;

endmodule
# Add Core Signals
gtkwave::addSignalsFromList {
    tb_rv32m_alu.clk
    tb_rv32m_alu.DUT.pc_out[31:0]
    tb_rv32m_alu.DUT.alu_busy
    tb_rv32m_alu.DUT.exec.u_hw_math.state[1:0]
    tb_rv32m_alu.DUT.exec.u_hw_math.counter[4:0]
    tb_rv32m_alu.DUT.exec.u_hw_math.valid
    tb_rv32m_alu.DUT.exec.u_hw_math.result[31:0]
}

# Format signals
gtkwave::highlightSignalsFromList {tb_rv32m_alu.DUT.pc_out[31:0] tb_rv32m_alu.DUT.exec.u_hw_math.result[31:0]}
gtkwave::setCurrentTranslateProc "hex"
gtkwave::unhighlightSignalsFromList {tb_rv32m_alu.DUT.pc_out[31:0] tb_rv32m_alu.DUT.exec.u_hw_math.result[31:0]}

# Zoom to see the 32-cycle DIV stall (Approx 40us mark)
gtkwave::setZoomRange 40000 42000

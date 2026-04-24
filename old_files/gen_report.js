const {
  Document, Packer, Paragraph, TextRun, Table, TableRow, TableCell,
  Header, Footer, AlignmentType, HeadingLevel, BorderStyle, WidthType,
  ShadingType, VerticalAlign, PageNumber, TabStopType, TabStopPosition
} = require('docx');
const fs = require('fs');

// ─── Palette ──────────────────────────────────────────────────────────────────
const BLUE_HDR  = "2E5F8E";
const LT_BLUE   = "D5E8F0";
const LT_GRAY   = "F2F2F2";
const WHITE     = "FFFFFF";
const GREEN     = "E2EFDA";
const YELLOW    = "FFF2CC";
const RED_LIGHT = "FCE4D6";

// ─── Helpers ──────────────────────────────────────────────────────────────────
const thinBorder = { style: BorderStyle.SINGLE, size: 1, color: "CCCCCC" };
const borders    = { top: thinBorder, bottom: thinBorder, left: thinBorder, right: thinBorder };

function statusBg(s) {
  if (!s) return WHITE;
  const t = s.toLowerCase();
  if (t === "done")             return GREEN;
  if (t.startsWith("done"))     return GREEN;
  if (t === "partial")          return YELLOW;
  if (t === "wip")              return YELLOW;
  if (t.includes("wip"))        return YELLOW;
  if (t === "not started")      return RED_LIGHT;
  if (t === "met")              return GREEN;
  if (t.includes("met"))        return GREEN;
  if (t === "tbd")              return LT_GRAY;
  if (t === "resolved")         return GREEN;
  if (t === "ongoing")          return YELLOW;
  if (t === "new")              return RED_LIGHT;
  if (t === "high")             return RED_LIGHT;
  if (t === "medium")           return YELLOW;
  if (t === "low")              return LT_GRAY;
  return WHITE;
}

function hCell(text, width) {
  return new TableCell({
    borders,
    width: { size: width, type: WidthType.DXA },
    shading: { fill: BLUE_HDR, type: ShadingType.CLEAR },
    margins: { top: 80, bottom: 80, left: 140, right: 140 },
    verticalAlign: VerticalAlign.CENTER,
    children: [new Paragraph({
      alignment: AlignmentType.CENTER,
      children: [new TextRun({ text, bold: true, color: "FFFFFF", size: 18, font: "Arial" })]
    })]
  });
}

function dCell(text, width, bg = WHITE, bold = false, center = false) {
  return new TableCell({
    borders,
    width: { size: width, type: WidthType.DXA },
    shading: { fill: bg, type: ShadingType.CLEAR },
    margins: { top: 80, bottom: 80, left: 140, right: 140 },
    verticalAlign: VerticalAlign.CENTER,
    children: [new Paragraph({
      alignment: center ? AlignmentType.CENTER : AlignmentType.LEFT,
      children: [new TextRun({ text, bold, size: 18, font: "Arial" })]
    })]
  });
}

function makeTable(colWidths, headerLabels, dataRows) {
  const total = colWidths.reduce((a,b) => a+b, 0);
  const hRow = new TableRow({
    tableHeader: true,
    children: headerLabels.map((h, i) => hCell(h, colWidths[i]))
  });
  const dRows = dataRows.map(row => new TableRow({
    children: row.map((cell, i) => {
      const bg = (cell && cell.bg) ? cell.bg : WHITE;
      const txt = (cell && cell.text !== undefined) ? cell.text : (cell || "");
      const bold = (cell && cell.bold) ? cell.bold : false;
      const center = (cell && cell.center) ? cell.center : false;
      return dCell(txt, colWidths[i], bg, bold, center);
    })
  }));
  return new Table({
    width: { size: total, type: WidthType.DXA },
    columnWidths: colWidths,
    rows: [hRow, ...dRows]
  });
}

function gap(before = 160, after = 0) {
  return new Paragraph({ spacing: { before, after }, children: [new TextRun("")] });
}

function h1(text) {
  return new Paragraph({
    heading: HeadingLevel.HEADING_1,
    spacing: { before: 280, after: 120 },
    children: [new TextRun({ text, bold: true, size: 28, font: "Arial", color: BLUE_HDR })]
  });
}

function h2(text) {
  return new Paragraph({
    heading: HeadingLevel.HEADING_2,
    spacing: { before: 160, after: 80 },
    children: [new TextRun({ text, bold: true, size: 22, font: "Arial", color: BLUE_HDR })]
  });
}

// Content width: US Letter 12240, margins 1440 each side → 9360 DXA
const CW = 9360;

// ─── 1 · Scope Tracking ───────────────────────────────────────────────────────
// widths: 400+4300+900+1160+2600 = 9360
const scopeW = [400, 4300, 900, 1160, 2600];
const scopeRows = [
  [
    {text:"MS1"},
    {text:"RV32M 8-op ALU (MUL, MULH, MULHSU, MULHU, DIV, DIVU, REM, REMU) via rv32m_alu with DSP48E1 inference and 32-cycle iterative divider FSM."},
    {text:"Done",   bg:GREEN},
    {text:"Mar 31, 2026"},
    {text:"Testbench verified"}
  ],
  [
    {text:"MS2"},
    {text:"Pipeline stall, hazard unit connections, and decoder extension for RV32M instructions integrated inside the IF/ID stage."},
    {text:"Done",   bg:GREEN},
    {text:"Apr 3, 2026"},
    {text:"Design / RTL verified"}
  ],
  [
    {text:"GS1"},
    {text:"3\u00d73 conv engine (conv_engine.v) with DSP48E1 MAC array \u2014 9-tap dot product per output pixel."},
    {text:"Partial", bg:YELLOW},
    {text:"Apr 18, 2026"},
    {text:"Testbench verified"}
  ],
  [
    {text:"GS2"},
    {text:"Line buffer (line_buffer.v) with pipelined BRAM \u2014 synchronous latency resolved via pipeline register insertion."},
    {text:"Partial", bg:YELLOW},
    {text:"Apr 18, 2026"},
    {text:"Testbench verified"}
  ],
  [
    {text:"GS3"},
    {text:"MMIO decoder: kernel regs 0x80000000\u20130x80000020, START at 0x80000024, STATUS at 0x80000028, NORM at 0x80000030, SW_DONE at 0x80000034."},
    {text:"Partial", bg:YELLOW},
    {text:"Apr 12, 2026"},
    {text:"Design: 2965104"}
  ],
  [
    {text:"STR1"},
    {text:"Triple-Channel RGB Processing: Expand the datapath to handle full RGB color channels, utilizing 27 DSP48E1 blocks (~11% of available DSPs)."},
    {text:"Not Started", bg:RED_LIGHT},
    {text:"\u2014"},
    {text:"\u2014"}
  ],
  [
    {text:"STR2"},
    {text:"Interactive Kernel Switching: Enable live, interactive kernel switching by using on-board physical switches during the live FPGA demonstration."},
    {text:"Not Started", bg:RED_LIGHT},
    {text:"\u2014"},
    {text:"\u2014"}
  ],
];

// ─── 2 · Design Goals ─────────────────────────────────────────────────────────
// 1200+1800+4500+1860 = 9360
const goalsW = [1200, 1800, 4500, 1860];
const goalsRows = [
  [{text:"Latency"},     {text:"\u2264 (W\u00d7H + 4) cycles"},  {text:"TBD \u2014 functional timing verification pending board bring-up."}, {text:"TBD",             bg:LT_GRAY}],
  [{text:"Throughput"},  {text:"1 pixel/cycle"},                  {text:"1 pixel/cycle (sim-verified in tb_conv_engine)"},                    {text:"Met",             bg:GREEN}],
  [{text:"LUT"},         {text:"\u2264 40,000"},                  {text:"13,641 LUTs used (21.52% of 63,400) \u2014 Vivado synth Apr 19 2026"},{text:"Met",             bg:GREEN}],
  [{text:"FF"},          {text:"\u2264 40,000"},                  {text:"5,429 FFs used (4.28% of 126,800) \u2014 Vivado synth Apr 19 2026"},  {text:"Met",             bg:GREEN}],
  [{text:"BRAM"},        {text:"\u2264 8"},                       {text:"5 RAMB36E1 used (3.70% of 135) \u2014 Vivado synth Apr 19 2026"},     {text:"Met",             bg:GREEN}],
  [{text:"DSP"},         {text:"\u2264 12"},                      {text:"4 DSP48E1 used (1.67% of 240) \u2014 Vivado synth Apr 19 2026"},      {text:"Met",             bg:GREEN}],
  [{text:"Correctness"}, {text:"100% SW reference match"},        {text:"Simulation tests passing"},                                         {text:"Met (simulation)",bg:GREEN}],
];

// ─── 3 · Demo Plan ────────────────────────────────────────────────────────────
// 1200+4080+4080 = 9360
const demoW = [1200, 4080, 4080];
const demoRows = [
  [{text:"Input"},      {text:"Load 8-bit grayscale BMP via UART \u2192 BRAM controller \u2192 img_bram_in"}, {text:"Sim-verified; GUI sends image bytes over serial."}],
  [{text:"Processing"}, {text:"CPU \u2192 MMIO \u2192 conv engine \u2192 poll STATUS until done"},             {text:"MMIO integrated; sw_gaussian_blur.c runs on pipeline."}],
  [{text:"Output"},     {text:"UART TX \u2192 GUI display + save to PNG"},                                    {text:"CustomTkinter GUI ready; output save to PNG implemented."}],
];

// ─── 4 · Gantt Chart (day-by-day, matching v4 style) ─────────────────────────
// Activity(900) + Owner(1260) + 36 days × 200 = 9360
const G_ACT = 900, G_OWN = 1260, G_DAY = 200;
const ganttColWidths = [G_ACT, G_OWN, ...Array(36).fill(G_DAY)];
const G_GREEN = "b6d7a8";   // light green – early/planning phase
const G_BLUE  = "4472C4";   // blue – active implementation

function gCell(w, text, opts = {}) {
  const { bg, bold, center, span } = opts;
  return new TableCell({
    borders,
    ...(span > 1 ? { columnSpan: span } : {}),
    width: { size: w * (span || 1), type: WidthType.DXA },
    shading: { fill: bg || "FFFFFF", type: ShadingType.CLEAR },
    margins: { top: 40, bottom: 40, left: 40, right: 40 },
    verticalAlign: VerticalAlign.CENTER,
    children: [new Paragraph({
      alignment: center ? AlignmentType.CENTER : AlignmentType.LEFT,
      children: text ? [new TextRun({ text, bold: !!bold, size: 16, font: "Arial" })] : []
    })]
  });
}

// Build 36 individual day cells from a pattern: [{count, color}]  color=null → white
function dayCells(pattern) {
  const cells = [];
  for (const { count, color } of pattern) {
    for (let i = 0; i < count; i++)
      cells.push(gCell(G_DAY, "", { bg: color || "FFFFFF" }));
  }
  return cells;
}

// Patterns derived from v4 color layout (36 days: Mar22–Apr26)
const ganttPersons = [
  { act: "rv32m_alu.v + Testbench + GUI",          owner: "Shaurya", pattern: [{count:9,color:G_GREEN},{count:20,color:G_BLUE},{count:7,color:null}] },
  { act: "hazard_unit.v + System Integration",      owner: "Sukhjot", pattern: [{count:1,color:null},{count:4,color:G_GREEN},{count:2,color:null},{count:22,color:G_BLUE},{count:7,color:null}] },
  { act: "conv_engine + line_buffer + img_bram",    owner: "Soumik",  pattern: [{count:3,color:null},{count:4,color:G_GREEN},{count:4,color:null},{count:17,color:G_BLUE},{count:8,color:null}] },
  { act: "MMIO decoder + conv_datapath + top_fsm",  owner: "Satish",  pattern: [{count:9,color:null},{count:4,color:G_GREEN},{count:22,color:G_BLUE},{count:1,color:null}] },
  { act: "UART controller + C workloads",           owner: "Abhirup", pattern: [{count:11,color:null},{count:18,color:G_BLUE},{count:7,color:null}] },
];

function makeGanttTable() {
  // Row 0: month labels
  const monthRow = new TableRow({ children: [
    gCell(G_ACT, ""),
    gCell(G_OWN, ""),
    gCell(G_DAY, "March", { center: true, span: 10 }),
    gCell(G_DAY, "April",  { center: true, span: 26 }),
  ]});

  // Row 1: "Activity" | "Owner" | day numbers 22-31, 1-26
  const marchDays = [22,23,24,25,26,27,28,29,30,31];
  const aprilDays = Array.from({length:26},(_,i)=>i+1);
  const dateRow = new TableRow({ children: [
    gCell(G_ACT, "Activity", { bold: true }),
    gCell(G_OWN, "Owner",    { bold: true }),
    ...marchDays.map(d => gCell(G_DAY, String(d), { center: true })),
    ...aprilDays.map(d => gCell(G_DAY, String(d), { center: true })),
  ]});

  const dataRows = ganttPersons.map(p => new TableRow({ children: [
    gCell(G_ACT, p.act,   { bg: LT_GRAY }),
    gCell(G_OWN, p.owner, { bg: LT_GRAY, bold: true }),
    ...dayCells(p.pattern)
  ]}));

  return new Table({ width: { size: CW, type: WidthType.DXA }, columnWidths: ganttColWidths, rows: [monthRow, dateRow, ...dataRows] });
}

// ─── 5 · Risks ────────────────────────────────────────────────────────────────
// 300+1760+900+700+1260+4440 = 9360
const riskW = [300, 1760, 900, 700, 1260, 4440];
const riskRows = [
  [
    {text:"1"},
    {text:"DIV multi-cycle handling"},
    {text:"Resolved", bg:GREEN},
    {text:"High",     bg:RED_LIGHT},
    {text:"Shaurya"},
    {text:"FSM gates start on ~div_busy; re-trigger loop fixed."}
  ],
  [
    {text:"2"},
    {text:"Kernel write lockout missing"},
    {text:"Ongoing",  bg:YELLOW},
    {text:"Medium",   bg:YELLOW},
    {text:"Satish"},
    {text:"Gate kernel reg writes on ~conv_busy in mmio_decoder; enforce all 9 writes before asserting START."}
  ],
  [
    {text:"3"},
    {text:"MMIO address mismatch (doc vs RTL)"},
    {text:"New",      bg:RED_LIGHT},
    {text:"Low",      bg:LT_GRAY},
    {text:"Satish / Shaurya"},
    {text:"Doc lists START=0x80000028; RTL uses 0x80000024. Confirm final addresses before demo."}
  ],
  [
    {text:"4"},
    {text:"FPGA synthesis not complete"},
    {text:"Ongoing",  bg:YELLOW},
    {text:"High",     bg:RED_LIGHT},
    {text:"Shaurya"},
    {text:"Run Vivado implementation before Apr 25 to get resource report and confirm timing closure."}
  ],
  [
    {text:"5"},
    {text:"Infinite software freeze during HW polling"},
    {text:"New",      bg:RED_LIGHT},
    {text:"High",     bg:RED_LIGHT},
    {text:"Abhirup"},
    {text:"Implement maximum cycle timeout in the C polling loop while(HW_DONE_REG == 0)."}
  ],
  [
    {text:"6"},
    {text:"Output BRAM boundary index overflow"},
    {text:"New",      bg:RED_LIGHT},
    {text:"Low",      bg:LT_GRAY},
    {text:"Abhirup"},
    {text:"Verify C-loop indices physically map to 0..15875 to prevent overwriting hardware MMIO registers."}
  ],
  [
    {text:"7"},
    {text:"Vivado stale cache / zombie .hex files"},
    {text:"Resolved", bg:GREEN},
    {text:"High",     bg:RED_LIGHT},
    {text:"Sukhjot"},
    {text:"Bypass Vivado auto-import by hardcoding absolute file paths ($readmemh) directly in instr_mem.v."}
  ],
  [
    {text:"8"},
    {text:"Combinatorial loop in MMIO read path"},
    {text:"Resolved", bg:GREEN},
    {text:"High",     bg:RED_LIGHT},
    {text:"Sukhjot"},
    {text:"Added 1-cycle latency flip-flop (is_mmio_read_wb) to memory mux to break loop."}
  ],
];

// ─── 6 · Contributions ────────────────────────────────────────────────────────
// 1200+5300+1000+1860 = 9360
const contribW = [1200, 5300, 1000, 1860];
const contribRows = [
  [{text:"Shaurya"}, {text:"rv32m_alu.v \u2014 all 8 RV32M ops with DSP48E1 inference and 32-cycle iterative divider FSM. tb_rv32m_alu.v. CustomTkinter Python GUI implementation."}, {text:"Done / WIP", bg:YELLOW}, {text:"Apr 5, 2026"}],
  [{text:"Sukhjot"}, {text:"hazard_unit.v and base CPU upgrades. System integration (linking convolution engine to GUI/software) and bug fixing."},                                    {text:"Done / WIP", bg:YELLOW}, {text:"Apr 19, 2026"}],
  [{text:"Soumik"},  {text:"conv_engine.v, line_buffer.v, img_bram_in/out.v \u2014 Phase 2 RTL."},                                                                                    {text:"WIP",        bg:YELLOW}, {text:"Apr 12, 2026"}],
  [{text:"Satish"},  {text:"mmio_decoder.v and conv_datapath.v \u2014 Memory mapping and datapath wiring. top_fsm.v state logic."},                                                   {text:"WIP",        bg:YELLOW}, {text:"Apr 25, 2026"}],
  [{text:"Abhirup"}, {text:"UART controller, bare-metal C benchmark codes (sw_blur.c)."},                                                                                            {text:"WIP",        bg:YELLOW}, {text:"Apr 19, 2026"}],
];

// ─── 7 · GitHub ───────────────────────────────────────────────────────────────
// commit count table: 5*1872 = 9360
const countW = [1872, 1872, 1872, 1872, 1872];
const countRows = [
  [{text:"12",center:true},{text:"31",center:true},{text:"6",center:true},{text:"27",center:true},{text:"27",center:true}]
];

// key commits: 1000+2700+5660 = 9360
const commitW = [1000, 2700, 5660];
const commitRows = [
  [{text:"8b22e70",bold:true}, {text:"Integrate coprocessor, UART + SW utilities (Clean)"},          {text:"Full Phase 2 integration: fixed line_buffer BRAM latency, wired top_fsm drain, brought in UART controller and C workloads."}],
  [{text:"2965104",bold:true}, {text:"Full MMIO decoder for kernel regfile + status reads"},          {text:"Maps kernel weights to 0x80000000\u20130x80000020, START to 0x80000024, STATUS to 0x80000028; adds SW_DONE doorbell."}],
  [{text:"87ff069",bold:true}, {text:"Add CustomTkinter GUI for FPGA coprocessor"},                  {text:"Premium dark-mode GUI: sends 128\u00d7128 image over UART, reads 126\u00d7126 convolved output, displays side-by-side comparison, saves convolved PNG."}],
  [{text:"56357c8",bold:true}, {text:"Add RV32M ALU module"},                                        {text:"Initial rv32m_alu.v: 8-op RV32M ALU with single-cycle multiply (DSP48E1) and 32-cycle iterative restoring divider FSM."}],
  [{text:"903e18e",bold:true}, {text:"Add sw_sobel + rename to blur (Sukhjot)"},                     {text:"Renamed sw_sobel.c \u2192 sw_gaussian_blur.c; updated Python GUI to save convolved output as timestamped PNG."}],
];

// ─── 8 · TA Feedback (blank) ─────────────────────────────────────────────────
// 4*2340 = 9360
const taW = [2340, 2340, 2340, 2340];
function makeTATable() {
  const hRow = new TableRow({
    tableHeader: true,
    children: ["Feedback Item","Date Received","Action Taken","Status"].map((h,i) => hCell(h, taW[i]))
  });
  const blanks = Array(3).fill(null).map(() => new TableRow({
    children: Array(4).fill(null).map((_,i) => dCell("", taW[i]))
  }));
  return new Table({ width:{size:CW,type:WidthType.DXA}, columnWidths:taW, rows:[hRow,...blanks] });
}

// ─── Build Document ───────────────────────────────────────────────────────────
const doc = new Document({
  styles: {
    default: { document: { run: { font: "Arial", size: 20 } } },
    paragraphStyles: [
      {
        id: "Heading1", name: "Heading 1", basedOn: "Normal", next: "Normal", quickFormat: true,
        run: { size: 28, bold: true, font: "Arial", color: BLUE_HDR },
        paragraph: { spacing: { before: 280, after: 120 }, outlineLevel: 0 }
      },
      {
        id: "Heading2", name: "Heading 2", basedOn: "Normal", next: "Normal", quickFormat: true,
        run: { size: 22, bold: true, font: "Arial", color: BLUE_HDR },
        paragraph: { spacing: { before: 160, after: 80 }, outlineLevel: 1 }
      }
    ]
  },
  sections: [{
    properties: {
      page: {
        size: { width: 12240, height: 15840 },
        margin: { top: 1440, right: 1440, bottom: 1440, left: 1440 }
      }
    },
    headers: {
      default: new Header({
        children: [new Paragraph({
          border: { bottom: { style: BorderStyle.SINGLE, size: 6, color: BLUE_HDR, space: 1 } },
          tabStops: [{ type: TabStopType.RIGHT, position: TabStopPosition.MAX }],
          children: [
            new TextRun({ text: "CS 224 \u2014 Group 18  |  Project Design Status Report", bold: true, size: 18, font: "Arial", color: BLUE_HDR }),
            new TextRun({ text: "\tNexys A7 (Artix-7 XC7A100T)", size: 18, font: "Arial", color: "555555" }),
          ]
        })]
      })
    },
    footers: {
      default: new Footer({
        children: [new Paragraph({
          border: { top: { style: BorderStyle.SINGLE, size: 4, color: BLUE_HDR, space: 1 } },
          alignment: AlignmentType.CENTER,
          children: [
            new TextRun({ text: "Page ", size: 18, font: "Arial" }),
            new TextRun({ children: [PageNumber.CURRENT], size: 18, font: "Arial" }),
            new TextRun({ text: " of ", size: 18, font: "Arial" }),
            new TextRun({ children: [PageNumber.TOTAL_PAGES], size: 18, font: "Arial" }),
          ]
        })]
      })
    },
    children: [
      // ── Title ──
      new Paragraph({
        alignment: AlignmentType.CENTER,
        spacing: { before: 120, after: 80 },
        children: [new TextRun({ text: "Hardware-Accelerated Grayscale Image Convolution Coprocessor", bold: true, size: 44, font: "Arial", color: BLUE_HDR })]
      }),
      new Paragraph({
        alignment: AlignmentType.CENTER,
        spacing: { before: 0, after: 80 },
        children: [new TextRun({ text: "Group 18  \u2014  CS 224,  Nexys A7 (Artix-7 XC7A100T)", bold: true, size: 26, font: "Arial" })]
      }),
      new Paragraph({
        alignment: AlignmentType.CENTER,
        spacing: { before: 0, after: 320 },
        border: { bottom: { style: BorderStyle.SINGLE, size: 8, color: BLUE_HDR, space: 4 } },
        children: [new TextRun({ text: "Project Design Status Report  |  April 2026", size: 22, font: "Arial", color: "555555" })]
      }),

      // ── 1. System Summary ──
      h1("1.  System Summary"),
      new Paragraph({
        spacing: { before: 80, after: 200 },
        children: [new TextRun({
          text: "A hardware-accelerated 3\u00d73 grayscale convolution coprocessor on Nexys A7 (Artix-7), driven by a custom RV32I + RV32M 3-stage pipeline with DSP48E1-inferred MAC units and a memory-mapped MMIO coprocessor interface. Integration stage \u2014 Phase 1 (RV32M 8-op extension) complete; Phase 2 coprocessor RTL simulation-verified; full FPGA board-level synthesis pending. RV32M ops, the conv engine, and line buffer are simulation-verified; MMIO decoder integrated. CustomTkinter GUI and C software workloads active.",
          size: 20, font: "Arial"
        })]
      }),

      // ── 2. Scope ──
      h1("2.  Scope Tracking"),
      makeTable(scopeW, ["#","Feature","Status","Target Date","Evidence"], scopeRows),
      gap(160),

      // ── 3. Goals ──
      h1("3.  Design Goals Tracking"),
      makeTable(goalsW, ["Metric","Target","Current","Status"], goalsRows),
      gap(160),

      // ── 4. Demo ──
      h1("4.  Demonstration Plan Status  (Apr 25\u201326)"),
      makeTable(demoW, ["Stage","Planned","Current Status"], demoRows),
      gap(160),

      // ── 5. Gantt ──
      h1("5.  Gantt Chart  (Mar 22 \u2013 Apr 26)"),
      makeGanttTable(),
      gap(160),

      // ── 6. Risks ──
      h1("6.  Risk Tracking"),
      makeTable(riskW, ["#","Risk","Status","Severity","Owner","Mitigation"], riskRows),
      gap(160),

      // ── 7. Contributions ──
      h1("7.  Per-Person Contribution"),
      makeTable(contribW, ["Member","Contribution","Status","Last Updated"], contribRows),
      gap(160),

      // ── 8. GitHub ──
      h1("8.  GitHub Snapshot"),
      new Paragraph({
        spacing: { before: 80, after: 80 },
        children: [
          new TextRun({ text: "Repository: ", bold: true, size: 20, font: "Arial" }),
          new TextRun({ text: "https://github.com/Sukhjot-SinghS/Image-Convulation-FPGA", size: 20, font: "Arial" }),
        ]
      }),
      new Paragraph({
        spacing: { before: 0, after: 100 },
        children: [new TextRun({ text: "Total commits: 103", size: 20, font: "Arial" })]
      }),
      h2("Commit Counts by Member"),
      makeTable(countW, ["Shaurya","Sukhjot","Soumik","Satish","Abhirup"], countRows),
      gap(160),
      h2("Key Commits"),
      makeTable(commitW, ["Hash","Message","Description"], commitRows),
      gap(160),

      // ── 9. TA Feedback ──
      h1("9.  Changes Based on TA Inputs"),
      makeTATable(),
      gap(160),
    ]
  }]
});

Packer.toBuffer(doc).then(buf => {
  fs.writeFileSync("Project_Design_Status_Report_Group18_Final.docx", buf);
  console.log("Done \u2714  Project_Design_Status_Report_Group18_Final.docx");
});

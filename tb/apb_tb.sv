`timescale 1ns/1ps
// =====================================================================
// APB Verification Environment (single file)
//   1. apb_if      : interface, clocking blocks, SVA protocol checks + cover props
//   2. apb_pkg     : transaction, generator, driver, monitor, coverage,
//                    scoreboard (+ reference model), env, tests
//   3. apb_tb      : top - clock/reset, DUT, bus tap, test launcher
//
// Run (Vivado xsim):
//   xvlog -sv apb_master.sv apb_slave.sv apb_wrapper.sv apb_tb.sv
//   xelab apb_tb -debug typical -s apb_sim
//   xsim apb_sim -runall -testplusarg TEST=full
//
// +TEST=  smoke | strb | corner | random | b2b | raw | err | zero_wstrb | full(default)
// +ZERO_WSTRB  lets random writes use PSTRB=0000 (DUT currently zeroes memory -> mismatch)
// =====================================================================

// ---------------------------------------------------------------------
// 1. INTERFACE
// ---------------------------------------------------------------------
interface apb_if (input logic PCLK);

  logic        PRESETn;

  // system side (driven by driver)
  logic        SWRITE;
  logic [31:0] SADDR, SWDATA;
  logic [3:0]  SSTRB;
  logic [2:0]  SPROT;
  logic        transfer;

  // APB bus (tapped from inside the wrapper by the top)
  logic        PSEL, PENABLE, PWRITE;
  logic [31:0] PADDR, PWDATA;
  logic [3:0]  PSTRB;
  logic [2:0]  PPROT;
  logic        PREADY, PSLVERR;
  logic [31:0] PRDATA;

  // knobs / counters
  bit          en_rd_strb_chk = 1;   // turn OFF when deliberately injecting read-with-PSTRB errors
  int unsigned assert_fails   = 0;

  initial begin
    SWRITE = 0; SADDR = 0; SWDATA = 0; SSTRB = 0; SPROT = 0; transfer = 0;
  end

  clocking drv_cb @(posedge PCLK);
    default input #1step output #1;
    output SWRITE, SADDR, SWDATA, SSTRB, SPROT, transfer;
    input  PSEL, PENABLE, PREADY;
  endclocking

  clocking mon_cb @(posedge PCLK);
    default input #1step;
    input PRESETn, PSEL, PENABLE, PWRITE, PADDR, PWDATA, PSTRB, PPROT,
          PREADY, PSLVERR, PRDATA;
  endclocking

  // ---------------- protocol assertions ----------------
  // --- APB state-machine rules ---
  a_penable_needs_psel : assert property (@(posedge PCLK) disable iff (!PRESETn)
      PENABLE |-> PSEL)
    else begin assert_fails++; $error("[SVA] PENABLE high without PSEL"); end

  a_setup_first : assert property (@(posedge PCLK) disable iff (!PRESETn)
      $rose(PSEL) |-> !PENABLE)
    else begin assert_fails++; $error("[SVA] first cycle of transfer must have PENABLE=0"); end

  a_setup_one_cycle : assert property (@(posedge PCLK) disable iff (!PRESETn)
      (PSEL && !PENABLE) |=> (PSEL && PENABLE))
    else begin assert_fails++; $error("[SVA] SETUP must last exactly one cycle and move to ACCESS"); end

  a_wait_hold : assert property (@(posedge PCLK) disable iff (!PRESETn)
      (PSEL && PENABLE && !PREADY) |=> (PSEL && PENABLE))
    else begin assert_fails++; $error("[SVA] ACCESS must hold while PREADY=0"); end

  // --- stability SETUP -> ACCESS (and through wait states) ---
  a_ctrl_stable_setup : assert property (@(posedge PCLK) disable iff (!PRESETn)
      (PSEL && !PENABLE) |=> ($stable(PWRITE) && $stable(PADDR) && $stable(PSTRB) &&
                              $stable(PPROT)  && $stable(PWDATA)))
    else begin assert_fails++; $error("[SVA] control/addr/data changed between SETUP and ACCESS"); end

  a_ctrl_stable_wait : assert property (@(posedge PCLK) disable iff (!PRESETn)
      (PSEL && PENABLE && !PREADY) |=> ($stable(PWRITE) && $stable(PADDR) && $stable(PSTRB) &&
                                        $stable(PPROT)  && $stable(PWDATA)))
    else begin assert_fails++; $error("[SVA] control/addr/data changed during wait state"); end

  // --- master behaviour vs system 'transfer' handshake ---
  a_start : assert property (@(posedge PCLK) disable iff (!PRESETn)
      (!PSEL && transfer) |=> (PSEL && !PENABLE))
    else begin assert_fails++; $error("[SVA] master did not start SETUP after transfer request"); end

  a_back2back : assert property (@(posedge PCLK) disable iff (!PRESETn)
      (PSEL && PENABLE && PREADY && transfer) |=> (PSEL && !PENABLE))
    else begin assert_fails++; $error("[SVA] master must go ACCESS->SETUP when transfer still asserted"); end

  a_to_idle : assert property (@(posedge PCLK) disable iff (!PRESETn)
      (PSEL && PENABLE && PREADY && !transfer) |=> !PSEL)
    else begin assert_fails++; $error("[SVA] master must go IDLE when transfer deasserted"); end

  // --- read strobe rule (master side, switchable) ---
  a_rd_strb_zero : assert property (@(posedge PCLK) disable iff (!PRESETn)
      (PSEL && !PWRITE && en_rd_strb_chk) |-> (PSTRB == 4'b0000))
    else begin assert_fails++; $error("[SVA] PSTRB must be 0 on read transfers"); end

  // --- slave behaviour ---
  a_zero_wait : assert property (@(posedge PCLK) disable iff (!PRESETn)
      (PSEL && PENABLE) |-> PREADY)
    else begin assert_fails++; $error("[SVA] zero-wait-state slave must assert PREADY in ACCESS"); end

  a_wr_noerr : assert property (@(posedge PCLK) disable iff (!PRESETn)
      (PSEL && PENABLE && PREADY && PWRITE) |=> !PSLVERR)
    else begin assert_fails++; $error("[SVA] PSLVERR set after write"); end

  a_rd_err : assert property (@(posedge PCLK) disable iff (!PRESETn)
      (PSEL && PENABLE && PREADY && !PWRITE && (PSTRB != 0)) |=> PSLVERR)
    else begin assert_fails++; $error("[SVA] slave missed PSLVERR on read with PSTRB!=0"); end

  a_rd_ok : assert property (@(posedge PCLK) disable iff (!PRESETn)
      (PSEL && PENABLE && PREADY && !PWRITE && (PSTRB == 0)) |=> !PSLVERR)
    else begin assert_fails++; $error("[SVA] spurious PSLVERR on legal read"); end

  a_prdata_stable : assert property (@(posedge PCLK) disable iff (!PRESETn)
      !(PSEL && PENABLE && PREADY && !PWRITE && (PSTRB == 0)) |=> $stable(PRDATA))
    else begin assert_fails++; $error("[SVA] PRDATA changed without a legal read"); end

  // --- reset behaviour (no disable iff) ---
  a_reset_bus : assert property (@(posedge PCLK)
      !PRESETn |-> (!PSEL && !PENABLE))
    else begin assert_fails++; $error("[SVA] PSEL/PENABLE not low during reset"); end

  a_reset_slave : assert property (@(posedge PCLK)
      !PRESETn |=> (PRDATA == 32'h0 && !PSLVERR))
    else begin assert_fails++; $error("[SVA] PRDATA/PSLVERR not cleared by reset"); end

  // --- X checks ---
  a_no_x_ctrl : assert property (@(posedge PCLK) disable iff (!PRESETn)
      !$isunknown({PSEL, PENABLE, PREADY}))
    else begin assert_fails++; $error("[SVA] X/Z on PSEL/PENABLE/PREADY"); end

  a_no_x_addr : assert property (@(posedge PCLK) disable iff (!PRESETn)
      PSEL |-> !$isunknown({PWRITE, PADDR, PSTRB, PPROT}))
    else begin assert_fails++; $error("[SVA] X/Z on control/address while PSEL"); end

  a_no_x_wdata : assert property (@(posedge PCLK) disable iff (!PRESETn)
      (PSEL && PWRITE) |-> !$isunknown(PWDATA))
    else begin assert_fails++; $error("[SVA] X/Z on PWDATA during write"); end

  // ---------------- cover properties ----------------
  c_b2b     : cover property (@(posedge PCLK) disable iff (!PRESETn)
      (PSEL && PENABLE && PREADY) ##1 (PSEL && !PENABLE));
  c_to_idle : cover property (@(posedge PCLK) disable iff (!PRESETn)
      (PSEL && PENABLE && PREADY) ##1 !PSEL);
  c_rd_err  : cover property (@(posedge PCLK) disable iff (!PRESETn)
      (PSEL && PENABLE && PREADY && !PWRITE && (PSTRB != 0)) ##1 PSLVERR);

endinterface


// ---------------------------------------------------------------------
// 2. PACKAGE : all verification classes
// ---------------------------------------------------------------------
package apb_pkg;

  localparam int MEM_DEPTH      = 1024;    // must match APB_Slave MEM_DEPTH
  localparam int TIMEOUT_CYCLES = 200000;

  // =================================================================
  // TRANSACTION
  // =================================================================
  class apb_tx;
    // ---- randomised stimulus ----
    rand bit          write;
    rand bit [31:0]   addr;
    rand bit [31:0]   wdata;
    rand bit [3:0]    strb;
    rand bit [2:0]    prot;
    rand int unsigned idle_before;   // idle cycles requested before this tx (0 = back-to-back)

    // ---- observed by monitor ----
    bit [31:0]   rdata;
    bit          slverr;
    int unsigned gap;                // measured idle cycles before SETUP

    // ---- global knobs ----
    static int unsigned wr_weight         = 50;  // % writes
    static bit          allow_zero_wstrb  = 0;   // allow write with PSTRB=0000
    static bit          allow_rd_strb_err = 0;   // allow read with PSTRB!=0 (error injection)

    // direction (write/read) is picked in apb_generator.send_random using wr_weight
    // (a dist on 'write' interacted badly with the strb constraint and skewed the mix)

    // hot region near 0 => plenty of read-after-write hits; plus first/last word
    constraint c_addr_wide {
      addr dist { [0:15] :/ 60, [16:MEM_DEPTH-2] :/ 30, (MEM_DEPTH-1) :/ 10 };
    }
    constraint c_addr_narrow { addr inside {[0:3]}; }   // disabled by default

    constraint c_strb {
      if (write) {
        if (allow_zero_wstrb) strb dist { 0 :/ 10, [1:14] :/ 60, 15 :/ 30 };
        else                  strb dist { [1:14] :/ 60, 15 :/ 40 };
      } else {
        if (allow_rd_strb_err) strb dist { 0 :/ 70, [1:15] :/ 30 };
        else                   strb == 0;
      }
    }

    constraint c_wdata {
      wdata dist { 32'h0000_0000 :/ 5, 32'hFFFF_FFFF :/ 5, 32'h8080_8080 :/ 3,
                   [32'h1 : 32'hFFFF_FFFE] :/ 87 };
    }

    constraint c_idle { idle_before dist { 0 :/ 50, 1 :/ 20, [2:5] :/ 20, [6:10] :/ 10 }; }

    function new();
      c_addr_narrow.constraint_mode(0);
    endfunction

    function apb_tx copy();
      apb_tx c = new();
      c.write = write; c.addr = addr; c.wdata = wdata; c.strb = strb; c.prot = prot;
      c.idle_before = idle_before;
      c.rdata = rdata; c.slverr = slverr; c.gap = gap;
      return c;
    endfunction

    function string convert2string();
      return $sformatf("%s addr=0x%0h wdata=0x%08h strb=%04b prot=%03b | rdata=0x%08h err=%0b gap=%0d",
                       write ? "WR" : "RD", addr, wdata, strb, prot, rdata, slverr, gap);
    endfunction
  endclass


  // =================================================================
  // COVERAGE
  // =================================================================
  class apb_coverage;
    // sampled copies (covergroups sample these scalars)
    bit          c_write;
    bit [31:0]   c_addr, c_wdata;
    bit [3:0]    c_strb;
    bit [2:0]    c_prot;
    int unsigned c_gap;
    bit          c_err;
    bit [2:0]    c_adj;      // 0 none, 1 RAW, 2 WAW, 3 WAR, 4 RAR (consecutive tx, same addr)
    bit [1:0]    c_state;    // {PSEL,PENABLE}
    apb_tx       prev;

    covergroup cg_txn;
      option.per_instance = 1;
      cp_dir   : coverpoint c_write { bins rd = {0}; bins wr = {1}; }
      cp_addr  : coverpoint c_addr  { bins zero = {0};
                                      bins low  = {[1:15]};
                                      bins mid  = {[16:MEM_DEPTH-2]};
                                      bins last = {MEM_DEPTH-1}; }
      cp_strb  : coverpoint c_strb  { bins s[] = {[0:15]}; }
      cp_prot  : coverpoint c_prot  { bins p[] = {[0:7]}; }
      cp_wdata : coverpoint c_wdata { bins zero    = {0};
                                      bins ones    = {32'hFFFF_FFFF};
                                      bins msb_set = {[32'h8000_0000 : 32'hFFFF_FFFE]};
                                      bins other   = default; }
      cp_gap   : coverpoint c_gap   { bins b2b   = {0};
                                      bins short = {[1:4]};
                                      bins mid   = {[5:8]};
                                      bins long  = {[9:$]}; }
      cp_err   : coverpoint c_err   { bins ok = {0}; bins err = {1}; }
      cp_seq   : coverpoint c_write { bins wr_wr = (1 => 1);
                                      bins wr_rd = (1 => 0);
                                      bins rd_wr = (0 => 1);
                                      bins rd_rd = (0 => 0); }
      cp_adj   : coverpoint c_adj   { bins raw = {1}; bins waw = {2};
                                      bins war = {3}; bins rar = {4}; }

      cx_dir_strb : cross cp_dir, cp_strb {
        ignore_bins wr_zero_strb = binsof(cp_dir.wr) && binsof(cp_strb) intersect {0};
      }
      cx_dir_err  : cross cp_dir, cp_err {
        ignore_bins wr_err = binsof(cp_dir.wr) && binsof(cp_err.err);
      }
      cx_dir_prot : cross cp_dir, cp_prot;
      cx_gap_dir  : cross cp_gap, cp_dir;
    endgroup

    covergroup cg_bus;
      option.per_instance = 1;
      cp_state : coverpoint c_state {
        bins idle   = {2'b00};
        bins setup  = {2'b10};
        bins access = {2'b11};
        illegal_bins bad = {2'b01};          // PENABLE without PSEL
      }
      cp_trans : coverpoint c_state {
        bins idle_idle    = (2'b00 => 2'b00);
        bins idle_setup   = (2'b00 => 2'b10);
        bins setup_access = (2'b10 => 2'b11);
        bins access_idle  = (2'b11 => 2'b00);
        bins access_setup = (2'b11 => 2'b10);   // back-to-back
        illegal_bins idle_access  = (2'b00 => 2'b11);
        illegal_bins setup_idle   = (2'b10 => 2'b00);
        illegal_bins setup_setup  = (2'b10 => 2'b10);
      }
    endgroup

    function new();
      cg_txn = new();
      cg_bus = new();
    endfunction

    function void sample_state(bit [1:0] st);
      c_state = st;
      cg_bus.sample();
    endfunction

    function void sample_tx(apb_tx t);
      c_write = t.write; c_addr = t.addr; c_wdata = t.wdata; c_strb = t.strb;
      c_prot  = t.prot;  c_gap  = t.gap;  c_err   = t.slverr;
      c_adj   = 0;
      if (prev != null && prev.addr == t.addr) begin
        case ({prev.write, t.write})
          2'b10: c_adj = 1;   // WR -> RD : read-after-write
          2'b11: c_adj = 2;   // WR -> WR
          2'b01: c_adj = 3;   // RD -> WR
          2'b00: c_adj = 4;   // RD -> RD
        endcase
      end
      cg_txn.sample();
      prev = t;
    endfunction

    function void report();
      $display("[COV] transaction covergroup : %6.2f %%", cg_txn.get_inst_coverage());
      $display("[COV] bus FSM covergroup     : %6.2f %%", cg_bus.get_inst_coverage());
    endfunction
  endclass


  // =================================================================
  // GENERATOR
  // =================================================================
  class apb_generator;
    mailbox #(apb_tx) gen2drv;
    int unsigned      sent = 0;

    function new(mailbox #(apb_tx) m);
      gen2drv = m;
    endfunction

    // ---- directed helpers ----
    task send_wr(bit [31:0] addr, bit [31:0] wdata, bit [3:0] strb = 4'hF, int unsigned idle = 0);
      apb_tx t = new();
      t.write = 1; t.addr = addr; t.wdata = wdata; t.strb = strb;
      t.prot = $urandom_range(0, 7); t.idle_before = idle;
      gen2drv.put(t); sent++;
    endtask

    task send_rd(bit [31:0] addr, int unsigned idle = 0, bit [3:0] strb = 4'h0);
      apb_tx t = new();
      t.write = 0; t.addr = addr; t.wdata = 0; t.strb = strb;
      t.prot = $urandom_range(0, 7); t.idle_before = idle;
      gen2drv.put(t); sent++;
    endtask

    // ---- constrained-random ----
    task send_random(int unsigned n, bit fixed_idle_en = 0, int unsigned fixed_idle = 0, bit narrow = 0);
      repeat (n) begin
        apb_tx t = new();
        t.write = ($urandom_range(0, 99) < apb_tx::wr_weight);
        t.write.rand_mode(0);                       // treat as state var; other fields randomised around it
        if (fixed_idle_en) t.c_idle.constraint_mode(0);
        if (narrow) begin
          t.c_addr_wide.constraint_mode(0);
          t.c_addr_narrow.constraint_mode(1);
        end
        if (fixed_idle_en) begin
          if (!t.randomize() with { idle_before == fixed_idle; })
            $fatal(1, "[GEN] randomize() failed");
        end
        else begin
          if (!t.randomize()) $fatal(1, "[GEN] randomize() failed");
        end
        gen2drv.put(t); sent++;
      end
    endtask
  endclass


  // =================================================================
  // DRIVER
  //   Mirrors the master's handshake:
  //     transfer=1 seen in IDLE            -> SETUP
  //     transfer=1 seen at end of ACCESS   -> SETUP again (back-to-back)
  //     transfer=0 seen at end of ACCESS   -> IDLE
  //   So: present S* + transfer=1, drop transfer during ACCESS unless the
  //   next tx is back-to-back, and change S* only after the ACCESS-end edge.
  // =================================================================
  class apb_driver;
    virtual apb_if    vif;
    mailbox #(apb_tx) gen2drv, drv2scb;

    function new(virtual apb_if vif, mailbox #(apb_tx) g, mailbox #(apb_tx) s);
      this.vif = vif; gen2drv = g; drv2scb = s;
    endfunction

    task present(apb_tx t);
      vif.drv_cb.SWRITE   <= t.write;
      vif.drv_cb.SADDR    <= t.addr;
      vif.drv_cb.SWDATA   <= t.wdata;
      vif.drv_cb.SSTRB    <= t.strb;
      vif.drv_cb.SPROT    <= t.prot;
      vif.drv_cb.transfer <= 1'b1;
      drv2scb.put(t.copy());            // expected request for the scoreboard
    endtask

    task run();
      apb_tx cur, held;
      bit    have_held = 0, b2b = 0;
      int    got;

      wait (vif.PRESETn === 1'b1);
      forever begin
        // ---- 1. start a transfer from IDLE (skipped when previous decided b2b) ----
        if (!b2b) begin
          if (have_held) begin
            cur = held; have_held = 0;
          end
          else begin
            gen2drv.get(cur);
            @(vif.drv_cb);                       // align to the clock
          end
          repeat (cur.idle_before) @(vif.drv_cb);
          present(cur);
        end
        b2b = 0;

        // ---- 2. wait until SETUP cycle has ended ----
        do @(vif.drv_cb); while (!(vif.drv_cb.PSEL === 1'b1 && vif.drv_cb.PENABLE === 1'b0));

        // ---- 3. decide: back-to-back, gap, or done ----
        got = gen2drv.try_get(held);
        if (got) begin
          if (held.idle_before == 0) b2b = 1;
          else                       have_held = 1;
        end
        if (!b2b) vif.drv_cb.transfer <= 1'b0;   // master goes IDLE after ACCESS

        // ---- 4. wait for ACCESS to complete ----
        do @(vif.drv_cb);
        while (!(vif.drv_cb.PSEL === 1'b1 && vif.drv_cb.PENABLE === 1'b1 && vif.drv_cb.PREADY === 1'b1));

        // ---- 5. back-to-back: master is entering SETUP now, hand it the next tx ----
        if (b2b) begin
          cur = held;
          present(cur);
        end
      end
    endtask
  endclass


  // =================================================================
  // MONITOR
  //   Passive. Detects a completed transfer (PSEL&PENABLE&PREADY), then
  //   samples PRDATA/PSLVERR one cycle later because the slave registers them.
  // =================================================================
  class apb_monitor;
    virtual apb_if    vif;
    mailbox #(apb_tx) mon2scb;
    apb_coverage      cov;

    function new(virtual apb_if vif, mailbox #(apb_tx) m, apb_coverage c);
      this.vif = vif; mon2scb = m; cov = c;
    endfunction

    task run();
      apb_tx       pend;
      bit          have_pend = 0;
      int unsigned idle_cnt = 0, cur_gap = 0;

      forever begin
        @(vif.mon_cb);
        if (vif.mon_cb.PRESETn !== 1'b1) begin
          have_pend = 0; idle_cnt = 0; cur_gap = 0;
          continue;
        end

        cov.sample_state({vif.mon_cb.PSEL, vif.mon_cb.PENABLE});

        // finish previous transfer: registered outputs are valid now
        if (have_pend) begin
          pend.rdata  = vif.mon_cb.PRDATA;
          pend.slverr = vif.mon_cb.PSLVERR;
          cov.sample_tx(pend);
          mon2scb.put(pend);
          have_pend = 0;
        end

        if (vif.mon_cb.PSEL === 1'b0) begin
          idle_cnt++;
        end
        else if (vif.mon_cb.PENABLE === 1'b0) begin          // SETUP
          cur_gap  = idle_cnt;
          idle_cnt = 0;
        end
        else if (vif.mon_cb.PREADY === 1'b1) begin           // ACCESS completes on this edge
          pend        = new();
          pend.write  = vif.mon_cb.PWRITE;
          pend.addr   = vif.mon_cb.PADDR;
          pend.wdata  = vif.mon_cb.PWDATA;
          pend.strb   = vif.mon_cb.PSTRB;
          pend.prot   = vif.mon_cb.PPROT;
          pend.gap    = cur_gap;
          have_pend   = 1;
        end
      end
    endtask
  endclass


  // =================================================================
  // SCOREBOARD  (master check + slave reference model)
  //   drv2scb : what the system asked for
  //   mon2scb : what appeared on the APB bus
  // =================================================================
  class apb_scoreboard;
    mailbox #(apb_tx) drv2scb, mon2scb;

    bit [31:0]   mem [int];          // reference memory (DUT Cache is zero-initialised by tb top)
    bit [31:0]   exp_prdata = 0;     // PRDATA only changes on a good read
    bit          exp_slverr = 0;
    int unsigned checked = 0, errors = 0, wr_cnt = 0, rd_cnt = 0, rd_err_cnt = 0;

    function new(mailbox #(apb_tx) d, mailbox #(apb_tx) m);
      drv2scb = d; mon2scb = m;
    endfunction

    // Slave's documented write behaviour (sign-extend / zero-fill, whole word replaced)
    function bit [31:0] wr_word(bit [3:0] s, bit [31:0] w);
      case (s)
        4'b0001: return {{24{w[7]}},  w[7:0]};
        4'b0010: return {{16{w[15]}}, w[15:8], 8'h00};
        4'b0011: return {{16{w[15]}}, w[15:0]};
        4'b0100: return {{16{w[23]}}, w[23:16], 8'h00};
        4'b0101: return {{8{w[23]}},  w[23:16], 8'h00, w[7:0]};
        4'b0110: return {{8{w[23]}},  w[23:8],  8'h00};
        4'b0111: return {{8{w[23]}},  w[23:0]};
        4'b1000: return {w[31:24], 24'h0};
        4'b1001: return {w[31:24], 16'h0, w[7:0]};
        4'b1010: return {w[31:24], 8'h00, w[15:8], 8'h00};
        4'b1011: return {w[31:24], 8'h00, w[15:0]};
        4'b1100: return {w[31:16], 16'h0};
        4'b1101: return {w[31:16], 8'h00, w[7:0]};
        4'b1110: return {w[31:8],  8'h00};
        default: return w;                       // 4'b1111
      endcase
    endfunction

    function void fail(string msg, apb_tx e, apb_tx o);
      errors++;
      $error("[SCB] %s\n       exp: %s\n       obs: %s", msg, e.convert2string(), o.convert2string());
    endfunction

    // ---- master translation check ----
    function void check_master(apb_tx e, apb_tx o);
      if (o.write !== e.write) fail("PWRITE mismatch", e, o);
      if (o.addr  !== e.addr)  fail("PADDR mismatch",  e, o);
      if (o.strb  !== e.strb)  fail("PSTRB mismatch",  e, o);
      if (o.prot  !== e.prot)  fail("PPROT mismatch",  e, o);
      if (e.write && (o.wdata !== e.wdata)) fail("PWDATA mismatch", e, o);
    endfunction

    // ---- slave model + response check ----
    function void check_slave(apb_tx e, apb_tx o);
      if (e.write) begin
        wr_cnt++;
        // APB spec: PSTRB=0000 write is a no-op (DUT currently zeroes the word -> will mismatch)
        if (e.strb != 0 && e.addr < MEM_DEPTH) mem[e.addr] = wr_word(e.strb, e.wdata);
        exp_slverr = 0;
      end
      else begin
        rd_cnt++;
        if (e.strb != 0) begin
          exp_slverr = 1;                       // illegal read strobe -> error, PRDATA holds
          rd_err_cnt++;
        end
        else begin
          exp_prdata = (e.addr < MEM_DEPTH && mem.exists(e.addr)) ? mem[e.addr] : 32'h0;
          exp_slverr = 0;
        end
      end

      if (o.rdata  !== exp_prdata) fail($sformatf("PRDATA mismatch (expected 0x%08h)", exp_prdata), e, o);
      if (o.slverr !== exp_slverr) fail($sformatf("PSLVERR mismatch (expected %0b)", exp_slverr),  e, o);
    endfunction

    task run();
      apb_tx obs, exp;
      forever begin
        mon2scb.get(obs);
        drv2scb.get(exp);
        check_master(exp, obs);
        check_slave(exp, obs);
        checked++;
      end
    endtask
  endclass


  // =================================================================
  // ENVIRONMENT
  // =================================================================
  class apb_env;
    virtual apb_if    vif;
    mailbox #(apb_tx) gen2drv, drv2scb, mon2scb;
    apb_generator     gen;
    apb_driver        drv;
    apb_monitor       mon;
    apb_scoreboard    scb;
    apb_coverage      cov;

    function new(virtual apb_if vif);
      this.vif = vif;
      gen2drv = new(); drv2scb = new(); mon2scb = new();
      cov = new();
      gen = new(gen2drv);
      drv = new(vif, gen2drv, drv2scb);
      mon = new(vif, mon2scb, cov);
      scb = new(drv2scb, mon2scb);
    endfunction

    task start();
      fork
        drv.run();
        mon.run();
        scb.run();
      join_none
    endtask

    // wait until every generated tx has been checked (with timeout)
    task drain(string phase);
      fork
        begin
          fork
            wait (scb.checked == gen.sent);
            begin
              repeat (TIMEOUT_CYCLES) @(posedge vif.PCLK);
              $fatal(1, "[ENV] timeout in phase '%s': sent=%0d checked=%0d", phase, gen.sent, scb.checked);
            end
          join_any
          disable fork;
        end
      join
      repeat (3) @(posedge vif.PCLK);
      $display("[ENV] phase '%s' done  (sent=%0d checked=%0d errors=%0d)", phase, gen.sent, scb.checked, scb.errors);
    endtask

    function void report();
      bit pass = (scb.errors == 0) && (vif.assert_fails == 0) && (gen.sent == scb.checked);
      $display("");
      $display("==================== APB TB SUMMARY ====================");
      $display(" transactions sent / checked : %0d / %0d", gen.sent, scb.checked);
      $display(" writes / reads / err-reads  : %0d / %0d / %0d", scb.wr_cnt, scb.rd_cnt, scb.rd_err_cnt);
      $display(" scoreboard errors           : %0d", scb.errors);
      $display(" assertion failures          : %0d", vif.assert_fails);
      cov.report();
      if (pass) $display(" *** TEST PASSED ***");
      else      $display(" *** TEST FAILED ***");
      $display("========================================================");
    endfunction
  endclass


  // =================================================================
  // TESTS
  // =================================================================
  class apb_test;
    apb_env         env;
    virtual apb_if  vif;

    function new(apb_env e, virtual apb_if v);
      env = e; vif = v;
    endfunction

    // one write + immediate read back (back-to-back)
    task t_smoke();
      env.gen.send_wr(32'h10, 32'hDEAD_BEEF, 4'hF, 0);
      env.gen.send_rd(32'h10, 0);
      env.drain("smoke");
    endtask

    // every legal PSTRB value, write then read-back, data with MSBs set to expose sign-extend
    task t_strb_sweep();
      for (int s = 1; s < 16; s++) begin
        env.gen.send_wr(32'h40 + s, 32'hA1B2_C3D4 ^ (s * 32'h0101_0101), 4'(s), 0);
        env.gen.send_rd(32'h40 + s, 0);
      end
      env.drain("strb_sweep");
    endtask

    // first / last word, all-zero / all-one data
    task t_corner();
      env.gen.send_wr(32'h0,            32'hFFFF_FFFF, 4'hF, 0);
      env.gen.send_rd(32'h0,            0);
      env.gen.send_wr(MEM_DEPTH - 1,    32'h0000_0000, 4'hF, 2);
      env.gen.send_rd(MEM_DEPTH - 1,    0);
      env.gen.send_wr(MEM_DEPTH - 1,    32'h8000_0001, 4'hF, 3);
      env.gen.send_rd(MEM_DEPTH - 1,    1);
      env.drain("corner");
    endtask

    task t_random();
      env.gen.send_random(300);
      env.drain("random");
    endtask

    // continuous back-to-back (ACCESS -> SETUP) traffic
    task t_b2b();
      env.gen.send_random(200, 1, 0);
      env.drain("b2b");
    endtask

    // tiny address window => lots of RAW / WAW / WAR / RAR hits
    task t_raw();
      env.gen.send_random(200, 0, 0, 1);
      env.drain("raw");
    endtask

    // error injection: reads with PSTRB != 0 must return PSLVERR and leave PRDATA alone
    task t_err();
      apb_tx::allow_rd_strb_err = 1;
      vif.en_rd_strb_chk        = 0;      // master-side rule intentionally violated
      for (int s = 1; s < 16; s++)        // every illegal read strobe, deterministic
        env.gen.send_rd(32'h40 + s, 0, 4'(s));
      env.gen.send_random(150);
      env.drain("err_inject");
      apb_tx::allow_rd_strb_err = 0;
      vif.en_rd_strb_chk        = 1;
    endtask

    // PSTRB=0000 write should NOT modify memory (APB spec). Expect FAIL on the current slave.
    task t_zero_wstrb();
      env.gen.send_wr(32'h77, 32'h1234_5678, 4'hF, 0);
      env.gen.send_wr(32'h77, 32'hFFFF_FFFF, 4'h0, 0);
      env.gen.send_rd(32'h77, 0);
      env.drain("zero_wstrb");
    endtask

    task run(string name);
      case (name)
        "smoke"      : t_smoke();
        "strb"       : t_strb_sweep();
        "corner"     : t_corner();
        "random"     : t_random();
        "b2b"        : t_b2b();
        "raw"        : t_raw();
        "err"        : t_err();
        "zero_wstrb" : t_zero_wstrb();
        "full"       : begin
                         t_smoke(); t_strb_sweep(); t_corner();
                         t_random(); t_b2b(); t_raw(); t_err();
                       end
        default      : $fatal(1, "[TEST] unknown +TEST=%s", name);
      endcase
    endtask
  endclass

endpackage


// ---------------------------------------------------------------------
// 3. TOP
// ---------------------------------------------------------------------
module apb_tb;
  import apb_pkg::*;

  logic PCLK = 1'b0;
  always #5 PCLK = ~PCLK;               // 100 MHz

  apb_if vif (PCLK);

  APB_Wrapper dut (
    .PCLK    (PCLK),
    .PRESETn (vif.PRESETn),
    .SWRITE  (vif.SWRITE),
    .SADDR   (vif.SADDR),
    .SWDATA  (vif.SWDATA),
    .SSTRB   (vif.SSTRB),
    .SPROT   (vif.SPROT),
    .transfer(vif.transfer),
    .PRDATA  (vif.PRDATA)
  );

  // Tap the internal APB bus so the monitor and assertions can see it
  assign vif.PSEL    = dut.PSEL;
  assign vif.PENABLE = dut.PENABLE;
  assign vif.PWRITE  = dut.PWRITE;
  assign vif.PADDR   = dut.PADDR;
  assign vif.PWDATA  = dut.PWDATA;
  assign vif.PSTRB   = dut.PSTRB;
  assign vif.PPROT   = dut.PPROT;
  assign vif.PREADY  = dut.PREADY;
  assign vif.PSLVERR = dut.PSLVERR;

  // Slave memory has no reset -> zero it so the reference model can assume 0
  initial begin
    for (int i = 0; i < MEM_DEPTH; i++) dut.Slave.Cache[i] = 32'h0;
  end

  string test_name;

  initial begin
    apb_env  env;
    apb_test tst;

    vif.PRESETn = 1'b0;
    if (!$value$plusargs("TEST=%s", test_name)) test_name = "full";
    if ($test$plusargs("ZERO_WSTRB")) apb_tx::allow_zero_wstrb = 1;

    repeat (4) @(posedge PCLK);
    #1 vif.PRESETn = 1'b1;
    repeat (2) @(posedge PCLK);

    env = new(vif);
    tst = new(env, vif);
    env.start();

    $display("[TB] running test '%s'", test_name);
    tst.run(test_name);

    env.report();
    $finish;
  end

endmodule
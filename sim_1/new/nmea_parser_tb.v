`timescale 1ns / 1ps

// =============================================================================
// Testbench nmea_parser (self-checking)
//   Test 1 : sentence GGA dengan checksum benar (*4F)
//            -> valid=1, error=0, data ter-parse, output UART TX = 84 byte
//   Test 2 : checksum sengaja salah (*00)
//            -> valid=0, error=1, buffer dibersihkan, TIDAK ada output TX
//   Test 3 : checksum benar dengan digit hex huruf kecil (*4f)
//            -> valid=1, error=0 (menguji cabang a-f di ascii_to_hex)
//
// Karakter disuntikkan langsung ke uart_rx (force rx_data / rx_ready),
// jadi yang diuji adalah FSM, ekstraksi field, dan checksum.
// Jalur uart_rx (serial) TIDAK diuji di sini.
// =============================================================================

module tb_nmea_parser();

    // ------------------------------------------------------------------
    // Sinyal DUT
    // ------------------------------------------------------------------
    reg  sysclk;
    reg  btn_rst;
    reg  uart_rxd;
    wire uart_txd;
    wire eth_rst_b;
    wire led0, led1, led2, led3;

    nmea_parser uut (
        .sysclk(sysclk), .btn_rst(btn_rst), .uart_rxd(uart_rxd),
        .uart_txd(uart_txd), .eth_rst_b(eth_rst_b),
        .led0(led0), .led1(led1), .led2(led2), .led3(led3)
    );

    // ------------------------------------------------------------------
    // Clock 125 MHz (periode 8 ns)
    // ------------------------------------------------------------------
    initial begin
        sysclk = 0;
        forever #4 sysclk = ~sysclk;
    end

    // ------------------------------------------------------------------
    // Konstanta baud (harus sama dengan uart_tx: CLK_FREQ / BAUD_RATE)
    // uart_tx menghitung timer 0..BAUD_TICK -> (BAUD_TICK + 1) clock per bit
    // ------------------------------------------------------------------
    localparam integer CLK_FREQ  = 125000000;
    localparam integer BAUD_RATE = 115200;
    localparam integer BIT_NS    = (CLK_FREQ / BAUD_RATE + 1) * 8;   // 1086 clock * 8 ns = 8688 ns

    // ------------------------------------------------------------------
    // Sentence uji. Semuanya harus tepat 87 karakter.
    // ------------------------------------------------------------------
    reg [8*87-1:0] msg_ok  = "$GPGGA,172814.0,3723.46587704,N,12202.26957864,W,2,6,1.2,18.893,M,-25.669,M,2.0,0031*4F";
    reg [8*87-1:0] msg_bad = "$GPGGA,172814.0,3723.46587704,N,12202.26957864,W,2,6,1.2,18.893,M,-25.669,M,2.0,0031*00";
    reg [8*87-1:0] msg_lc  = "$GPGGA,172814.0,3723.46587704,N,12202.26957864,W,2,6,1.2,18.893,M,-25.669,M,2.0,0031*4f";

    // ------------------------------------------------------------------
    // Penghitung hasil test
    // ------------------------------------------------------------------
    integer pass_count;
    integer fail_count;

    task check;
        input condition;
        input [8*48-1:0] name;
        begin
            if (condition) begin
                $display("[PASS] %0s", name);
                pass_count = pass_count + 1;
            end else begin
                $display("[FAIL] %0s", name);
                fail_count = fail_count + 1;
            end
        end
    endtask

    // ------------------------------------------------------------------
    // Suntik 1 karakter ke uart_rx (pulsa rx_ready selebar 1 clock)
    // Mulai di negedge, jadi tiap pulsa mencakup tepat 1 posedge.
    // ------------------------------------------------------------------
    task inject_char;
        input [7:0] char_in;
        begin
            force uut.receiver_inst.rx_data  = char_in;
            force uut.receiver_inst.rx_ready = 1'b1;
            #8;
            force uut.receiver_inst.rx_ready = 1'b0;
            #40;
        end
    endtask

    // ------------------------------------------------------------------
    // Kirim 1 sentence (87 karakter, karakter pertama = MSB)
    // ------------------------------------------------------------------
    task send_sentence;
        input [8*87-1:0] s;
        input            verbose;
        integer k;
        reg [7:0] c;
        begin
            for (k = 87; k > 0; k = k - 1) begin
                c = s[((k-1)*8) +: 8];
                inject_char(c);
                if (verbose)
                    $display("-> Mesin menangkap huruf: '%c' | State: %0d | Koma ke-: %0d | XOR: %h",
                             c, uut.current_state, uut.comma_buffer, uut.calculated_checksum);
            end
        end
    endtask

    // ------------------------------------------------------------------
    // Cetak isi buffer hasil parsing
    // ------------------------------------------------------------------
    task print_parsed;
        begin
            $display("\n========================================");
            $display("             PARSED DATA                ");
            $display("========================================");

            $display("Message ID   : %c%c%c%c%c%c",
                     uut.message_id_buffer[0], uut.message_id_buffer[1], uut.message_id_buffer[2],
                     uut.message_id_buffer[3], uut.message_id_buffer[4], uut.message_id_buffer[5]);

            $display("Waktu (Time) : %c%c%c%c%c%c%c%c",
                     uut.time_buffer[0], uut.time_buffer[1], uut.time_buffer[2], uut.time_buffer[3],
                     uut.time_buffer[4], uut.time_buffer[5], uut.time_buffer[6], uut.time_buffer[7]);

            $display("Latitude     : %c%c%c%c%c%c%c%c%c%c%c%c%c",
                     uut.lat_buffer[0], uut.lat_buffer[1], uut.lat_buffer[2], uut.lat_buffer[3],
                     uut.lat_buffer[4], uut.lat_buffer[5], uut.lat_buffer[6], uut.lat_buffer[7],
                     uut.lat_buffer[8], uut.lat_buffer[9], uut.lat_buffer[10], uut.lat_buffer[11],
                     uut.lat_buffer[12]);

            $display("Lat Dir      : %c", uut.lat_dir_buffer[0]);

            $display("Longitude    : %c%c%c%c%c%c%c%c%c%c%c%c%c%c",
                     uut.lon_buffer[0], uut.lon_buffer[1], uut.lon_buffer[2], uut.lon_buffer[3],
                     uut.lon_buffer[4], uut.lon_buffer[5], uut.lon_buffer[6], uut.lon_buffer[7],
                     uut.lon_buffer[8], uut.lon_buffer[9], uut.lon_buffer[10], uut.lon_buffer[11],
                     uut.lon_buffer[12], uut.lon_buffer[13]);

            $display("Lon Dir      : %c", uut.lon_dir_buffer[0]);
            $display("GPS Quality  : %c", uut.gps_quality_buffer[0]);
            $display("Satellites   : %c", uut.sat_num_buffer[0]);

            $display("HDOP         : %c%c%c",
                     uut.hdop_buffer[0], uut.hdop_buffer[1], uut.hdop_buffer[2]);

            $display("Altitude     : %c%c%c%c%c%c",
                     uut.alt_buffer[0], uut.alt_buffer[1], uut.alt_buffer[2],
                     uut.alt_buffer[3], uut.alt_buffer[4], uut.alt_buffer[5]);

            $display("----------------------------------------");
            $display("Calculated checksum   : %h", uut.calculated_checksum);
            $display("Checksum Valid Status : %b", uut.checksum_valid_flag);
            $display("Checksum Error Status : %b", uut.checksum_error_flag);
            $display("========================================\n");
        end
    endtask

    // ------------------------------------------------------------------
    // Monitor UART TX (115200 8N1): rekam semua byte yang dikirim DUT
    // ------------------------------------------------------------------
    integer   tx_count;
    reg [7:0] tx_log [0:255];
    reg [7:0] tx_byte;
    integer   b;

    initial begin
        tx_count = 0;
        forever begin
            @(negedge uart_txd);
            #(BIT_NS/2);                       // tengah start bit
            if (uart_txd === 1'b0) begin
                for (b = 0; b < 8; b = b + 1) begin
                    #(BIT_NS);
                    tx_byte[b] = uart_txd;     // LSB dulu
                end
                #(BIT_NS);                     // tengah stop bit
                if (tx_count < 256) tx_log[tx_count] = tx_byte;
                tx_count = tx_count + 1;
            end
        end
    end

    // ------------------------------------------------------------------
    // Skenario utama
    // ------------------------------------------------------------------
    integer tx_count_before;

    initial begin
        pass_count = 0;
        fail_count = 0;

        btn_rst  = 1;
        uart_rxd = 1;

        #100 btn_rst = 0;
        #100;

        // ==============================================================
        // TEST 1 : checksum benar (*4F)
        // ==============================================================
        $display("========================================");
        $display("  TEST 1 : SENTENCE VALID (*4F)         ");
        $display("========================================");

        send_sentence(msg_ok, 1'b1);
        #200;

        print_parsed;

        check(uut.checksum_valid_flag === 1'b1, "T1 checksum_valid_flag = 1");
        check(uut.checksum_error_flag === 1'b0, "T1 checksum_error_flag = 0");
        check(uut.calculated_checksum === 8'h4F, "T1 calculated_checksum = 4F");
        check(uut.current_state === 3'd4,        "T1 FSM masuk DONE_OUTPUT");

        // Isi field (buffer masih terisi karena FSM di DONE_OUTPUT)
        check(uut.message_id_buffer[0] === "G" && uut.message_id_buffer[4] === "A", "T1 Message ID = GPGGA");
        check(uut.time_buffer[0] === "1" && uut.time_buffer[7] === "0",             "T1 Time = 172814.0");
        check(uut.lat_buffer[0] === "3" && uut.lat_buffer[12] === "4",              "T1 Latitude = 3723.46587704");
        check(uut.lat_dir_buffer[0] === "N",                                        "T1 Lat Dir = N");
        check(uut.lon_buffer[0] === "1" && uut.lon_buffer[13] === "4",              "T1 Longitude = 12202.26957864");
        check(uut.lon_dir_buffer[0] === "W",                                        "T1 Lon Dir = W");
        check(uut.gps_quality_buffer[0] === "2",                                    "T1 GPS Quality = 2");
        check(uut.sat_num_buffer[0] === "6",                                        "T1 Satellites = 6");
        check(uut.hdop_buffer[0] === "1" && uut.hdop_buffer[2] === "2",             "T1 HDOP = 1.2");
        check(uut.alt_buffer[0] === "1" && uut.alt_buffer[5] === "3",               "T1 Altitude = 18.893");

        // Tunggu DONE_OUTPUT selesai (sekitar 84 byte * ~87 us)
        wait (uut.current_state == 3'd0);
        #(BIT_NS * 20);

        $display("\nByte TX diterima monitor: %0d", tx_count);
        check(tx_count === 84, "T1 jumlah byte TX = 84");

        // Cek sebagian isi output (offset dihitung dari panjang field di DUT)
        check(tx_log[0]  === "G",  "T1 TX[0]  = 'G' (Message ID)");
        check(tx_log[6]  === 8'h0D && tx_log[7] === 8'h0A, "T1 TX[6..7] = CRLF");
        check(tx_log[8]  === "1",  "T1 TX[8]  = '1' (Time)");
        check(tx_log[25] === "3",  "T1 TX[25] = '3' (Latitude)");
        check(tx_log[42] === "N",  "T1 TX[42] = 'N' (Lat Dir)");
        check(tx_log[45] === "1",  "T1 TX[45] = '1' (Longitude)");
        check(tx_log[62] === "W",  "T1 TX[62] = 'W' (Lon Dir)");
        check(tx_log[65] === "2",  "T1 TX[65] = '2' (Quality)");
        check(tx_log[68] === "6",  "T1 TX[68] = '6' (Satellites)");
        check(tx_log[71] === "1",  "T1 TX[71] = '1' (HDOP)");
        check(tx_log[76] === "1",  "T1 TX[76] = '1' (Altitude)");
        check(tx_log[82] === 8'h0D && tx_log[83] === 8'h0A, "T1 TX[82..83] = CRLF akhir");

        // ==============================================================
        // TEST 2 : checksum salah (*00)
        // ==============================================================
        $display("\n========================================");
        $display("  TEST 2 : CHECKSUM SALAH (*00)         ");
        $display("========================================");

        tx_count_before = tx_count;

        send_sentence(msg_bad, 1'b0);
        #200;

        check(uut.checksum_valid_flag === 1'b0, "T2 checksum_valid_flag = 0");
        check(uut.checksum_error_flag === 1'b1, "T2 checksum_error_flag = 1");
        check(uut.current_state === 3'd0,        "T2 FSM kembali ke IDLE");
        check(uut.message_id_buffer[0] === 8'h20 && uut.lat_buffer[0] === 8'h20,
              "T2 buffer dibersihkan");

        #(BIT_NS * 20);
        check(tx_count === tx_count_before, "T2 tidak ada output TX");

        // ==============================================================
        // TEST 3 : checksum benar, hex huruf kecil (*4f)
        // ==============================================================
        $display("\n========================================");
        $display("  TEST 3 : HEX HURUF KECIL (*4f)        ");
        $display("========================================");

        send_sentence(msg_lc, 1'b0);
        #200;

        check(uut.checksum_valid_flag === 1'b1, "T3 checksum_valid_flag = 1");
        check(uut.checksum_error_flag === 1'b0, "T3 checksum_error_flag = 0");

        wait (uut.current_state == 3'd0);
        #(BIT_NS * 20);

        // ==============================================================
        // Ringkasan
        // ==============================================================
        $display("\n========================================");
        $display("  RINGKASAN : %0d PASS, %0d FAIL", pass_count, fail_count);
        $display("========================================\n");

        release uut.receiver_inst.rx_data;
        release uut.receiver_inst.rx_ready;

        $finish;
    end

    // ------------------------------------------------------------------
    // Pengaman: hentikan simulasi kalau macet (mis. FSM tidak kembali ke IDLE)
    // ------------------------------------------------------------------
    initial begin
        #100_000_000;   // 100 ms
        $display("[TIMEOUT] Simulasi terlalu lama, kemungkinan FSM macet");
        $finish;
    end

endmodule
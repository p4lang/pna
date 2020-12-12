// BEGIN:Programmable_blocks
parser ParserT<PH, PM>(
    packet_in pkt,
    out PH hdr,
    out PM user_meta,
    in  pna_parser_input_metadata_t istd);

control PreControlT<PH, PM, MM>(
    in    PH hdr,
    in    PM pre_user_meta,
    out   MM main_user_meta,
    in    pna_pre_input_metadata_t  istd,
    inout pna_pre_output_metadata_t ostd);

control MainControlT<PM, PH, MM>(
    in    PM pre_user_meta,
    inout PH hdr,
    inout MM main_user_meta,
    in    pna_main_input_metadata_t  istd,
    inout pna_main_output_metadata_t ostd);

control MainDeparserT<PH, MM>(
    packet_out pkt,
    in    PH hdr,
    in    MM main_user_meta,
    in    pna_main_output_metadata_t ostd);

package PNA_NIC<PH, PM, MM>(
    ParserT<PH, PM> parser,
    PreControlT<PH, PM> pre_control,
    MainControlT<PM, PH, MM> main_control,
    MainDeparserT<PH, MM> main_deparser);
// END:Programmable_blocks

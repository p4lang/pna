// BEGIN:ControlImpl_interface
control ControlImpl(
    in    pre_metadata_t pre_user_meta,
    inout headers_t hdr,
    inout MM main_user_meta,
    in    pna_pre_input_metadata_t  pre_istd,
    in    pna_main_input_metadata_t  main_istd,
    inout pna_pre_output_metadata_t pre_ostd,
    inout pna_main_output_metadata_t main_ostd)
{}
// END:ControlImpl_interface




// BEGIN:Package_Instantiation_Example
PNA_NIC(
    ParserImpl(),
    ControlImpl(),
    MainDeparserImpl()) main;
// END:Package_Instantiation_Example
